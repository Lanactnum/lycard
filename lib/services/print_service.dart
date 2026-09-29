import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data/card_image_source.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../widgets/image_quality_dialog.dart';

/// 要打印的一张卡（同一张卡放 4 张就会展开成 4 条）
class PrintCard {
  PrintCard(this.code, this.png);

  final String code;

  /// 已转成 PDF 能吃的格式（PNG/JPEG）；null = 没图，印出来是占位框
  final Uint8List? png;
}

/// 卡图打印：把卡组排成 A4 页面，交给系统打印服务（或导出 PDF）。
///
/// 排版固定 3×3 = 每页 9 张，按真实卡牌尺寸 63×88mm 居中摆放，
/// 每张带一圈极细裁切框 —— 打印店按框裁就行。
///
/// 用官方原图包时是无损 PNG；只有内置压缩图时会先提示（见
/// [confirmCardImageQuality]），不会偷偷拿压缩图去印。
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  /// 真实卡牌尺寸（mm）
  static const double cardWidthMm = 63;
  static const double cardHeightMm = 88;

  /// 每页排布
  static const int columns = 3;
  static const int rows = 3;

  static int get perPage => columns * rows;

  /// 卡组 → 展开成一张张要印的卡（按卡号排序，同编号连续）
  static List<String> expandDeck(Deck deck) {
    final codes = deck.cards.keys.toList()..sort();
    final out = <String>[];
    for (final c in codes) {
      final n = deck.cards[c] ?? 0;
      for (var i = 0; i < n; i++) {
        out.add(c);
      }
    }
    return out;
  }

  /// 加载并转换卡图。返回的列表与 [codes] 一一对应。
  static Future<List<PrintCard>> loadImages(
    List<String> codes, {
    void Function(int done, int total)? onProgress,
  }) => loadPrintableImages(codes, onProgress: onProgress);

  /// 把任意图片字节转成 PDF 库支持的格式。
  ///
  /// 内置卡图是 WebP，而 PDF 只认 PNG/JPEG，所以这里用 Flutter 自己的
  /// 解码器解一遍再编成 PNG —— 不用为了转格式再引一个图像依赖。
  static Uint8List? _toPdfImage(Uint8List? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (_isPng(raw) || _isJpeg(raw)) return raw;
    return null;
  }

  static bool _isPng(Uint8List b) =>
      b.length > 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47;

  static bool _isJpeg(Uint8List b) =>
      b.length > 3 && b[0] == 0xFF && b[1] == 0xD8;

  /// WebP 等格式 → PNG（异步，需要 Flutter 引擎）
  static Future<Uint8List?> decodeToPng(Uint8List raw) async {
    if (_isPng(raw) || _isJpeg(raw)) return raw;
    try {
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      codec.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// 加载卡图（含 WebP→PNG 转换），保证 [PrintCard.png] 一定可用
  static Future<List<PrintCard>> loadPrintableImages(
    List<String> codes, {
    void Function(int done, int total)? onProgress,
  }) async {
    final out = <PrintCard>[];
    for (var i = 0; i < codes.length; i++) {
      final code = codes[i];
      CardImageData data;
      try {
        data = await CardImageSource.instance.load(code);
      } catch (_) {
        data = const CardImageData(CardImageKind.unavailable, null);
      }
      final raw = data.bytes;
      var png = _toPdfImage(raw);
      if (png == null && raw != null) {
        png = await decodeToPng(raw);
      }
      out.add(PrintCard(code, png));
      onProgress?.call(i + 1, codes.length);
    }
    return out;
  }

  /// 生成 PDF（A4，3×3 居中 + 裁切框）
  static Future<Uint8List> buildPdf(
    List<PrintCard> cards, {
    String title = '',
  }) async {
    final doc = pw.Document(title: title.isEmpty ? 'lycard' : title);

    final cw = cardWidthMm * PdfPageFormat.mm;
    final ch = cardHeightMm * PdfPageFormat.mm;
    final totalW = columns * cw;
    final totalH = rows * ch;
    // 居中：A4 210×297，9 张卡 189×264，四边留白对称
    final offX = (PdfPageFormat.a4.width - totalW) / 2;
    final offY = (PdfPageFormat.a4.height - totalH) / 2;

    for (var start = 0; start < cards.length; start += perPage) {
      final end = math.min(start + perPage, cards.length);
      final slice = cards.sublist(start, end);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (ctx) => pw.Stack(
            children: [
              for (var i = 0; i < slice.length; i++)
                pw.Positioned(
                  left: offX + (i % columns) * cw,
                  top: offY + (i ~/ columns) * ch,
                  child: pw.Container(
                    width: cw,
                    height: ch,
                    decoration: pw.BoxDecoration(
                      // 极细裁切框：打印店按框裁
                      border: pw.Border.all(
                        color: PdfColors.grey500,
                        width: 0.25,
                      ),
                    ),
                    child: slice[i].png == null
                        ? pw.Center(
                            child: pw.Text(
                              slice[i].code,
                              style: const pw.TextStyle(fontSize: 9),
                            ),
                          )
                        : pw.Image(
                            pw.MemoryImage(slice[i].png!),
                            fit: pw.BoxFit.fill,
                          ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// 走系统打印（用户在系统界面里选打印机/存成 PDF）
  static Future<bool> printBytes(Uint8List bytes, String jobName) =>
      Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: jobName,
      );

  /// 导出/分享 PDF 文件
  static Future<bool> shareBytes(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}

/// 卡组打印入口：确认卡图来源 → 生成 PDF → 交给系统打印
///
/// 返回 true 表示已经把 PDF 交给系统了。
Future<bool> printDeckFlow(
  BuildContext context,
  AppState state,
  Deck deck,
) async {
  final codes = PrintService.expandDeck(deck);
  if (codes.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('这个卡组还没有卡，没法打印'))));
    return false;
  }

  // 先探一遍图源：找到「不是原图」就停下，明确提示一次
  var worst = CardImageKind.originalPack;
  for (final c in codes) {
    final d = await CardImageSource.instance.load(c);
    if (d.kind != CardImageKind.originalPack) {
      worst = d.kind;
      break;
    }
  }
  if (!context.mounted) return false;

  if (worst != CardImageKind.originalPack) {
    final ok = await confirmCardImageQuality(context, worst);
    if (!ok) return false;
  }
  if (!context.mounted) return false;

  final progress = ValueNotifier<double>(0);
  // 进度提示：60 张要转格式，不能让界面看着像卡死
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (c, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: v == 0 ? null : v),
              const SizedBox(height: 12),
              Text(tr('正在排版 {0} 张卡…', [codes.length])),
            ],
          ),
        ),
      ),
    ),
  );

  Uint8List pdf;
  try {
    final items = await PrintService.loadPrintableImages(
      codes,
      onProgress: (done, total) {
        progress.value = total == 0 ? 0 : done / total;
      },
    );
    pdf = await PrintService.buildPdf(items, title: deck.name);
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('排版失败：{0}', ['$e']))));
    }
    return false;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!context.mounted) return false;

  // 打印还是导出，让用户选
  final action = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('打印卡图')),
      content: Text(tr('已排好 {0} 页 A4（每页 9 张，带裁切框）。', [
        '${(codes.length / PrintService.perPage).ceil()}',
      ])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, 'pdf'),
          child: Text(tr('导出 PDF')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, 'print'),
          child: Text(tr('打印')),
        ),
      ],
    ),
  );
  if (action == null) return false;

  final safeName = deck.name.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  if (action == 'pdf') {
    final ok = await PrintService.shareBytes(
      pdf,
      'lycard_${safeName.isEmpty ? 'deck' : safeName}.pdf',
    );
    return ok;
  }
  return PrintService.printBytes(pdf, deck.name);
}
