import 'dart:async';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../data/card_repository.dart';
import '../widgets/card_route.dart';
import '../widgets/glass.dart';
import '../data/deck_share.dart';
import '../l10n/l10n.dart';

/// 扫码识别卡号 / 二维码（要求 L71）
///
/// · 实时相机预览，画面正中画一个矩形取景框
/// · **只有落在框内**的识别结果会被采纳（其它区域一律忽略）
/// · 识别到合规卡号 → 轻微震动 → 浮窗显示卡详情
/// · 点浮窗外区域 → 关掉浮窗，继续扫下一张
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  /// 只在扫到卡组分享码（LYD1…）时返回那个码；
  /// 扫到卡号会**留在本页**就地进卡详情，返回后继续扫。
  static Future<String?> show(BuildContext context) =>
      Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanPage()));

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver, RouteAware {
  CameraController? _cam;
  CameraDescription? _back;
  bool _busy = false;
  bool _torch = false;
  String? _initError;

  final _text = TextRecognizer(script: TextRecognitionScript.latin);
  final _code = BarcodeScanner(formats: [BarcodeFormat.qrCode]);

  /// 识别到的卡号 → 展示中的浮窗
  String? _hit;

  /// 已经决定要离开这一页了（扫到分享码）。
  /// 二维码会在连续很多帧里被识别到，如果每帧都 Navigator.pop，
  /// 就会一路把下面的页面全弹掉，最后只剩一个背景层 —— 表现为
  /// "进了个纯背景界面、点不动"。所以必须上锁 + 立刻停流。
  bool _leaving = false;

  /// 正在识别相册里选的那张图（显示个转圈）
  bool _scanning = false;

  /// 取景框（相对屏幕的比例），识别到的东西必须落在里面
  static const double _frameW = 0.86;
  static const double _frameH = 0.20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  Future<void> _boot() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _initError = tr('这台设备没有可用摄像头'));
        return;
      }
      _back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        _back!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
      await ctrl.startImageStream(_onFrame);
    } catch (e) {
      if (mounted) setState(() => _initError = tr('相机打开失败：{0}', [e]));
    }
  }

  /// 卡详情盖上来 → 停止识别（省电，也不白占 CPU）；
  /// 从详情返回 → 清掉上一张的浮窗，恢复识别。
  /// 相机与手电筒全程不销毁，所以返回后界面和离开前完全一样。
  @override
  void didPushNext() {
    _cam?.stopImageStream().catchError((_) {});
  }

  @override
  void didPopNext() {
    if (!mounted || _leaving) return;
    setState(() => _hit = null);
    _cam?.startImageStream(_onFrame).catchError((_) {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) appRouteObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _cam?.stopImageStream().catchError((_) {});
    _cam?.dispose();
    _text.close();
    _code.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.inactive) {
      _cam?.stopImageStream().catchError((_) {});
    } else if (s == AppLifecycleState.resumed && _cam != null) {
      _cam!.startImageStream(_onFrame).catchError((_) {});
    }
  }

  /// 取景框在图像坐标系里的范围（用相对比例，省得算旋转）
  Rect _frameRectIn(Size img) {
    final w = img.width * _frameW;
    final h = img.height * _frameH;
    return Rect.fromLTWH((img.width - w) / 2, (img.height - h) / 2, w, h);
  }

  void _onFrame(CameraImage image) async {
    if (_busy || _hit != null || _leaving) return; // 有结果/要走人了就别再重识别
    _busy = true;
    try {
      final rot = _rotationFor(_back!);
      final input = InputImage.fromBytes(
        bytes: _nv21(image),
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rot,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );

      // 取景框（按图像尺寸换算；旋转 90/270 时宽高对调）
      final swapped = rot == InputImageRotation.rotation90deg ||
          rot == InputImageRotation.rotation270deg;
      final imgSize = swapped
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());
      final frame = _frameRectIn(imgSize);

      // ① 二维码：优先（扫别人的分享码）
      final qrs = await _code.processImage(input);
      for (final b in qrs) {
        final raw = b.rawValue;
        if (raw == null || raw.isEmpty) continue;
        if (raw.startsWith('LYD1')) {
          _acceptQr(raw);
          return;
        }
      }

      // ② 文字：抠卡号
      final recognized = await _text.processImage(input);
      for (final block in recognized.blocks) {
        // 只认取景框里的文字
        if (!frame.overlaps(block.boundingBox)) continue;
        final c = _findCode(block.text.replaceAll('\n', ' '));
        if (c != null) {
          _accept(c);
          return;
        }
      }
    } catch (_) {
      // 单帧失败无所谓，继续
    } finally {
      _busy = false;
    }
  }

  /// 从相册挑一张图来识别（没有取景框，整张图都看）
  Future<void> _pickFromGallery() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _hit = null;
      _scanning = true;
    });
    try {
      final input = InputImage.fromFilePath(path);
      // 二维码优先
      for (final b in await _code.processImage(input)) {
        final raw = b.rawValue;
        if (raw == null || raw.isEmpty) continue;
        if (raw.startsWith('LYD1')) {
          await _acceptQr(raw);
          return;
        }
      }
      // 再找卡号（全图，不套取景框）
      final recognized = await _text.processImage(input);
      for (final block in recognized.blocks) {
        final c = _findCode(block.text.replaceAll('\n', ' '));
        if (c != null) {
          _accept(c);
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('这张图里没认出卡号或分享码'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('识别失败：{0}', [e]))));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// 从任意文本里找出第一个合规卡号
  static String? _findCode(String text) {
    final m = RegExp(r'LO\D{0,2}(\d{3,5})(?:\D{0,2}([KSL]))?', caseSensitive: false)
        .firstMatch(text.toUpperCase());
    if (m == null) return null;
    final code = 'LO-${m.group(1)}${m.group(2) == null ? '' : '-${m.group(2)}'}';
    return CardRepository.instance.byCode(code) == null ? null : code;
  }

  void _accept(String code) {
    if (!mounted) return;
    HapticFeedback.lightImpact(); // 轻微震动反馈
    setState(() => _hit = code);
  }

  Future<void> _acceptQr(String raw) async {
    if (!mounted || _leaving) return;
    _leaving = true;
    HapticFeedback.mediumImpact();
    // 先把帧流掐掉，否则下一帧还会识别到同一个二维码再 pop 一次
    _cam?.stopImageStream().catchError((_) {});

    // 问一句再走：扫到码不等于想导入（可能只是路过 / 扫错）
    final info = deckSummaryFromShareCode(raw);
    final ok = await showGlassConfirm(
      context,
      title: info.name.isEmpty ? tr('发现卡组分享码') : tr('发现「{0}」', [info.name]),
      message: info.line,
      confirmText: tr('导入'),
      cancelText: tr('不导入'),
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.pop(context, raw);
    } else {
      // 不导入：留在扫描页接着扫
      _leaving = false;
      _hit = null;
      _cam?.startImageStream(_onFrame).catchError((_) {});
    }
  }

  static InputImageRotation _rotationFor(CameraDescription d) {
    switch (d.sensorOrientation) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  /// YUV420 / NV21 → nv21
  static Uint8List _nv21(CameraImage img) {
    if (img.format.group == ImageFormatGroup.nv21 && img.planes.length == 1) {
      return img.planes.first.bytes;
    }
    final y = img.planes[0].bytes;
    final u = img.planes[1].bytes;
    final v = img.planes.length > 2 ? img.planes[2].bytes : img.planes[1].bytes;
    final out = Uint8List(y.length + u.length + v.length);
    out.setRange(0, y.length, y);
    var i = y.length;
    for (var j = 0; j < u.length; j++) {
      out[i++] = v[j];
      out[i++] = u[j];
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (cam != null && cam.value.isInitialized)
            Positioned.fill(child: CameraPreview(cam))
          else
            Center(
              child: Text(
                _initError ?? tr('正在打开相机…'),
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),

          // 取景框 + 遮罩
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _FramePainter(_frameW, _frameH)),
            ),
          ),

          // 相册识别中
          if (_scanning)
            Positioned(
              left: 0,
              right: 0,
              bottom: 60,
              child: const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                ),
              ),
            ),

          // 提示
          Positioned(
            left: 0,
            right: 0,
            top: MediaQuery.sizeOf(context).height * (0.5 + _frameH / 2) + 14,
            child: Center(
              child: Text(
                tr('将卡号或二维码对准框内'),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)]),
              ),
            ),
          ),

          // 顶部：返回 + 手电筒
          Positioned(
            left: 8,
            right: 8,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Row(
              children: [
                _circleBtn(Icons.arrow_back, () => Navigator.pop(context)),
                const Spacer(),
                _circleBtn(Icons.photo_library_outlined, _pickFromGallery),
                const SizedBox(width: 8),
                _circleBtn(
                  _torch ? Icons.flash_on : Icons.flash_off,
                  () async {
                    final c = _cam;
                    if (c == null) return;
                    final on = !_torch;
                    await c.setFlashMode(
                        on ? FlashMode.torch : FlashMode.off);
                    setState(() => _torch = on);
                  },
                ),
              ],
            ),
          ),

          // 识别到的卡详情浮窗
          if (_hit != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _hit = null), // 点浮窗外继续扫
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {}, // 吃掉点击
                      child: _hitCard(_hit!, scheme),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _hitCard(String code, ColorScheme scheme) {
    final card = CardRepository.instance.byCode(code);
    final name = card == null
        ? code
        : (card.nameZh?.isNotEmpty == true ? card.nameZh! : card.nameJp);
    return Glass(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 26, color: Colors.greenAccent),
            const SizedBox(height: 8),
            Text(code,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => setState(() => _hit = null),
                  child: Text(tr('继续扫')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    // 先收掉浮窗，再就地进卡详情：
                    // 扫描页留在栈上不销毁 → 相机、手电筒、取景框全部保持原状，
                    // 从详情返回就能接着扫下一张。
                    setState(() => _hit = null);
                    await openCardDetail(context, code, scope: 'scan');
                  },
                  child: Text(tr('看卡详情')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      );
}

/// 半透明遮罩 + 中间镂空矩形 + 四角标记
class _FramePainter extends CustomPainter {
  _FramePainter(this.wRatio, this.hRatio);

  final double wRatio;
  final double hRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * wRatio;
    final h = size.height * hRatio;
    final rect = Rect.fromLTWH((size.width - w) / 2, (size.height - h) / 2, w, h);

    final mask = Paint()..color = Colors.black.withValues(alpha: 0.45);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(14))),
      ),
      mask,
    );

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.85);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(14)), border);

    // 四角加粗
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    const len = 22.0;
    final r = Radius.circular(14);
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + len)
        ..lineTo(rect.left, rect.top + r.y)
        ..arcToPoint(Offset(rect.left + r.x, rect.top), radius: r)
        ..lineTo(rect.left + len, rect.top),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.top)
        ..lineTo(rect.right - r.x, rect.top)
        ..arcToPoint(Offset(rect.right, rect.top + r.y), radius: r)
        ..lineTo(rect.right, rect.top + len),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - len)
        ..lineTo(rect.left, rect.bottom - r.y)
        ..arcToPoint(Offset(rect.left + r.x, rect.bottom),
            radius: r, clockwise: false)
        ..lineTo(rect.left + len, rect.bottom),
      corner,
    );
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - len, rect.bottom)
        ..lineTo(rect.right - r.x, rect.bottom)
        ..arcToPoint(Offset(rect.right, rect.bottom - r.y),
            radius: r, clockwise: false)
        ..lineTo(rect.right, rect.bottom - len),
      corner,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.wRatio != wRatio || old.hRatio != hRatio;
}
