import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// 裁剪框（view 坐标系）：屏幕中央，按 [ratio] 取能放下的最大尺寸。
///
/// `ratio <= 0` 表示跟随屏幕比例。上下各留出空间给标题栏和比例选择条。
Rect cropFrameOf(Size view, double ratio) {
  final maxW = view.width - 28;
  final maxH = view.height - 180;
  final r = ratio <= 0 ? view.width / view.height : ratio;
  var w = maxW;
  var h = w / r;
  if (h > maxH) {
    h = maxH;
    w = h * r;
  }
  return Rect.fromCenter(
    center: Offset(view.width / 2, view.height / 2),
    width: w,
    height: h,
  );
}

/// 让图片「恰好盖住裁剪框」所需的缩放倍数
double coverScaleOf(Rect frame, Size img) =>
    math.max(frame.width / img.width, frame.height / img.height);

/// 由「图片左上角在 view 里的位置 + 缩放」反推出该裁原图的哪一块。
///
/// 这是整个裁剪功能唯一容易算错的地方，所以提成纯函数、单独测。
Rect cropRectOf(Rect frame, Offset offset, double scale, Size img) {
  final r = Rect.fromLTRB(
    (frame.left - offset.dx) / scale,
    (frame.top - offset.dy) / scale,
    (frame.right - offset.dx) / scale,
    (frame.bottom - offset.dy) / scale,
  );
  // 夹到图片范围内 —— 拖到边时框内可能有极小一撮露白，不夹会裁出透明边
  return Rect.fromLTRB(
    r.left.clamp(0, img.width),
    r.top.clamp(0, img.height),
    r.right.clamp(0, img.width),
    r.bottom.clamp(0, img.height),
  );
}

/// 把图片位置夹在「框内不露白」的范围内
Offset clampImageOffset(
    Offset offset, double scale, Rect frame, Size img) {
  final w = img.width * scale;
  final h = img.height * scale;
  return Offset(
    offset.dx.clamp(frame.right - w, frame.left),
    offset.dy.clamp(frame.bottom - h, frame.top),
  );
}

/// 把 [src] 的 [rect] 区域裁出来、编码成 PNG。
///
/// 抽成顶层函数是为了能单测 —— 光验证「坐标算对了」不够，
/// 得验证「真的裁到了那一块」（用四象限纯色图断言输出像素）。
Future<Uint8List?> cropImageToPng(ui.Image src, Rect rect) async {
  final outW = rect.width.round();
  final outH = rect.height.round();
  if (outW < 8 || outH < 8) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    src,
    rect,
    Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final out = await recorder.endRecording().toImage(outW, outH);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  out.dispose();
  return data?.buffer.asUint8List();
}

/// 背景图裁剪（要求 L117 里点名要的「裁剪」）。
///
/// 交互：图片可拖动/双指缩放，中间是固定的裁剪框（可切比例），
/// **框里就是留下来的部分** —— 所见即所得。
///
/// ## 为什么不用 `InteractiveViewer`
///
/// 它的 `toScene()` 只对变换矩阵求逆，**不考虑 `alignment`**
/// （源码里就三行：`Matrix4.inverted(value).transform3(...)`）。
/// 而 child 比 viewport 大时，`Transform` 的 `alignment: center`
/// 会让实际坐标系相对 viewport 平移半个差值 —— 于是 `toScene()` 算出来的
/// 位置和 child 的真实坐标对不上，裁出来的区域会偏。
/// 这里改成自己维护 `_offset`/`_scale`，数学完全可控，也能单测。
///
/// ## 另外两个要点
///
/// - **从原文件全分辨率解码**，不用 `AppState.bgRaw`（那张已缩到 1080 宽，会掉画质）。
/// - **把当前旋转烘焙进裁剪结果**：用户看到的背景是旋转过的，裁出来就该是那个样子；
///   裁完把 `rotation` 归零，否则会被再转一次。
class BgCropPage extends StatefulWidget {
  const BgCropPage({
    super.key,
    required this.imagePath,
    this.rotation = 0,
  });

  final String imagePath;

  /// 当前旋转角度（0/90/180/270），会烘焙进裁剪结果
  final int rotation;

  @override
  State<BgCropPage> createState() => _BgCropPageState();
}

/// 可选裁剪比例。0 = 跟随屏幕。
const _ratios = <String, double>{
  '跟随屏幕': 0,
  '1:1': 1,
  '3:4': 3 / 4,
  '4:3': 4 / 3,
  '9:16': 9 / 16,
  '16:9': 16 / 9,
};

class _BgCropPageState extends State<BgCropPage> {
  /// body 尺寸从 LayoutBuilder 拿（`context.findRenderObject()` 指向 Scaffold，
  /// 尺寸含 AppBar 和底栏，和裁剪框的口径不一样）
  final _bodyKey = GlobalKey();

  ui.Image? _src;
  bool _failed = false;
  bool _busy = false;
  double _ratio = 0;

  double _scale = 1;
  Offset _offset = Offset.zero;

  // 手势起点
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _src?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      var img = await _decode(bytes);
      final rot = widget.rotation % 360;
      if (rot != 0) {
        final rotated = await _rotateImage(img, rot);
        img.dispose();
        img = rotated;
      }
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() => _src = img);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// 旋转 90 的倍数，返回新位图
  static Future<ui.Image> _rotateImage(ui.Image src, int deg) async {
    final w = src.width.toDouble(), h = src.height.toDouble();
    final swap = deg == 90 || deg == 270;
    final outW = (swap ? h : w).round();
    final outH = (swap ? w : h).round();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(outW / 2, outH / 2);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-w / 2, -h / 2);
    canvas.drawImage(src, Offset.zero, Paint());
    return recorder.endRecording().toImage(outW, outH);
  }

  Size get _imgSize =>
      Size(_src!.width.toDouble(), _src!.height.toDouble());

  /// 把图片摆到「恰好盖住裁剪框、居中」
  void _fitToFrame(Size view) {
    final img = _imgSize;
    final frame = cropFrameOf(view, _ratio);
    _scale = coverScaleOf(frame, img);
    _offset = Offset(
      frame.center.dx - img.width * _scale / 2,
      frame.center.dy - img.height * _scale / 2,
    );
    _offset = clampImageOffset(_offset, _scale, frame, img);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d, Size view) {
    final img = _imgSize;
    final frame = cropFrameOf(view, _ratio);
    final minS = coverScaleOf(frame, img);
    final s = (_startScale * d.scale).clamp(minS, minS * 8);

    // 以手势焦点为锚：焦点下的那个图片像素保持不动
    final anchor = (_startFocal - _startOffset) / _startScale;
    final off = d.localFocalPoint - anchor * s;

    setState(() {
      _scale = s;
      _offset = clampImageOffset(off, s, frame, img);
    });
  }

  Future<Uint8List?> _crop(Rect frame) async {
    final src = _src;
    if (src == null) return null;
    return cropImageToPng(src, cropRectOf(frame, _offset, _scale, _imgSize));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(tr('裁剪背景'), style: const TextStyle(fontSize: 16)),
        actions: [
          if (_src != null)
            TextButton(
              onPressed: _busy ? null : _confirm,
              child: Text(tr('确定'),
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: _failed
          ? const Center(
              child: Text('这张背景图读不出来',
                  style: TextStyle(color: Colors.white70)))
          : _src == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  key: _bodyKey,
                  builder: (context, c) {
                    final view = Size(c.maxWidth, c.maxHeight);
                    final frame = cropFrameOf(view, _ratio);
                    final img = _imgSize;
                    return GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: (d) => _onScaleUpdate(d, view),
                      child: ClipRect(
                        child: Stack(
                          children: [
                            Positioned(
                              left: _offset.dx,
                              top: _offset.dy,
                              width: img.width * _scale,
                              height: img.height * _scale,
                              child: RawImage(
                                image: _src,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter:
                                      _FramePainter(frame, scheme.primary),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      bottomNavigationBar: _src == null
          ? null
          : Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in _ratios.entries)
                        ChoiceChip(
                          label:
                              Text(e.key, style: const TextStyle(fontSize: 12)),
                          selected: _ratio == e.value,
                          onSelected: (_) {
                            final box = _bodyKey.currentContext
                                ?.findRenderObject();
                            setState(() => _ratio = e.value);
                            if (box is RenderBox && _src != null) {
                              _fitToFrame(box.size);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        tr('拖动/双指缩放，框内就是留下来的部分'),
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: () {
                          final box =
                              _bodyKey.currentContext?.findRenderObject();
                          if (box is RenderBox && _src != null) {
                            setState(() => _fitToFrame(box.size));
                          }
                        },
                        child: Text(tr('复位'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _confirm() async {
    final box = _bodyKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final frame = cropFrameOf(box.size, _ratio);
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final bytes = await _crop(frame);
    if (!mounted) return;
    setState(() => _busy = false);
    if (bytes == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('裁剪区域太小了'))),
      );
      return;
    }
    nav.pop(bytes);
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame, this.accent);

  final Rect frame;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // 框外压暗：整屏减去框（even-odd 一次画完，比画四块干净）
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()..addRect(frame);
    canvas.drawPath(
      Path.combine(PathOperation.difference, outer, inner),
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
    canvas.drawRect(
      frame,
      Paint()
        ..color = accent
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke,
    );
    // 三分线
    final thin = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 0.8;
    for (var i = 1; i <= 2; i++) {
      final dx = frame.left + frame.width * i / 3;
      final dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), thin);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), thin);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.frame != frame || old.accent != accent;
}
