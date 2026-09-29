import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../data/card_saver.dart';
import '../data/deck_share.dart';
import '../state/app_state.dart';
import 'glass.dart';
import '../l10n/l10n.dart';

/// 分享构筑：分享码 + 二维码（要求 L67）
///
/// · 分享码头部带特征码 LYD1，gzip + base64，控制在 500 字以内
/// · 二维码固定「玻璃质感」：透明底 + 白色模块（不嵌任何图片）
Future<void> showDeckShareSheet(
  BuildContext context,
  AppState state,
  Deck deck,
) async {
  final code = state.shareDeck(deck);
  final cards = deck.total;
  final scheme = Theme.of(context).colorScheme;

  // 二维码样式：默认玻璃质感（透明底 + 白模块），可切黑白（白底 + 黑模块，最保险）
  // 注意必须放在 StatefulBuilder 外面，否则每次重建都会重置
  var mono = false;

  await showGlassSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          height: MediaQuery.sizeOf(c).height * 0.78,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.ios_share, size: 17, color: scheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tr('分享构筑「{0}」', [deck.name]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                  Text(tr('{0} 张 · {1}/500', [cards, code.length]),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: code.length <= DeckShare.maxLen
                            ? scheme.onSurfaceVariant
                            : scheme.error,
                      )),
                ],
              ),
              const SizedBox(height: 12),

              // ── 二维码：透明底 + 白色模块（玻璃质感）──
              Center(
                child: RepaintBoundary(
                  key: _qrKey,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Container(
                      color: mono ? Colors.white : Colors.transparent,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                        data: code,
                        version: QrVersions.auto,
                        size: 200,
                        gapless: true,
                        backgroundColor: Colors.transparent,
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: mono ? Colors.black : Colors.white,
                        ),
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: mono ? Colors.black : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _qrStyleTag(c, tr('玻璃质感'), !mono,
                      () => setLocal(() => mono = false)),
                  const SizedBox(width: 8),
                  _qrStyleTag(c, tr('黑白'), mono, () => setLocal(() => mono = true)),
                ],
              ),
              const SizedBox(height: 10),

              // ── 分享码 ──
              Text(tr('分享码'),
                  style:
                      TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      code,
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.copy, size: 17),
                      label: Text(tr('复制分享码')),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        if (c.mounted) {
                          ScaffoldMessenger.of(c).showSnackBar(
                              SnackBar(content: Text(tr('已复制到剪贴板'))));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download, size: 17),
                      label: Text(tr('存二维码')),
                      onPressed: () async {
                        final bytes = await _captureQr();
                        if (bytes == null) return;
                        if (!await CardSaver.instance.hasAccess()) {
                          await CardSaver.instance.requestAccess();
                        }
                        final ok = await CardSaver.instance
                            .savePngBytes(bytes, name: 'lycard_deck');
                        if (c.mounted) {
                          ScaffoldMessenger.of(c).showSnackBar(SnackBar(
                              content: Text(ok
                                  ? tr('二维码已存到相册')
                                  : tr('保存失败（可能未获得相册权限）'))));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    ),
  );
}

final GlobalKey _qrKey = GlobalKey();

Future<Uint8List?> _captureQr() async {
  try {
    final ctx = _qrKey.currentContext;
    if (ctx == null) return null;
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final img = await boundary.toImage(pixelRatio: 3);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}


/// 二维码样式的小切换（全 app 的小标签用同一套做法）
Widget _qrStyleTag(
  BuildContext c,
  String label,
  bool on,
  VoidCallback onTap,
) {
  final cs = Theme.of(c).colorScheme;
  return GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: on ? cs.primary.withValues(alpha: 0.24) : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          color: on ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    ),
  );
}
