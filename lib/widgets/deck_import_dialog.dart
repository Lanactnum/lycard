import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/deck_official.dart';
import '../data/deck_share.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'tags.dart';
import '../l10n/l10n.dart';

/// 两套识别系统：自家的和官方的。
///
/// 用户自己选，避免「粘了官方链接却被当成分享码报错」这种来回试。
enum DeckImportSource {
  /// 自动判断：LYD1 开头当分享码，含官方域名当官方链接
  auto,

  /// lycard 分享码（LYD1…），离线可解析
  shareCode,

  /// 官方卡组链接（lyc.ee / lycee-tcg.com），需要联网抓取
  official,
}

String deckImportSourceLabel(DeckImportSource s) {
  switch (s) {
    case DeckImportSource.auto:
      return tr('自动识别');
    case DeckImportSource.shareCode:
      return tr('lycard 分享码');
    case DeckImportSource.official:
      return tr('官方卡组链接');
  }
}

/// 导入构筑：两套识别系统 —— lycard 分享码 / 官方卡组链接（要求 L69，与 L73 联动）
///
/// 返回导入出来的构筑（取消或码不合法则返回 null）。
Future<Deck?> showDeckImportDialog(BuildContext context, AppState state) async {
  final ctrl = TextEditingController();
  var source = DeckImportSource.auto;
  String? err;
  String? note;
  DeckData? preview;
  var busy = false;

  final result = await showGlassSheet<Deck>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: StatefulBuilder(
        builder: (ctx, setLocal) {
          final scheme = Theme.of(ctx).colorScheme;

          /// 按当前识别系统解析文本；官方链接要联网
          Future<void> parse(String t) async {
            final v = t.trim();
            setLocal(() {
              err = null;
              note = null;
              preview = null;
              busy = false;
            });
            if (v.isEmpty) return;

            // 选「自动识别」时先看形态，再决定用哪套
            var use = source;
            if (use == DeckImportSource.auto) {
              if (DeckShare.looksLike(v)) {
                use = DeckImportSource.shareCode;
              } else if (OfficialDeck.looksLike(v)) {
                use = DeckImportSource.official;
              } else {
                setLocal(() {
                  err = tr('认不出来：既不是 LYD1 分享码，也不是官方卡组链接');
                });
                return;
              }
            }

            if (use == DeckImportSource.shareCode) {
              if (!DeckShare.looksLike(v)) {
                setLocal(() => err = tr('这不是构筑分享码（应以 LYD1 开头）'));
                return;
              }
              final d = DeckShare.decode(v);
              setLocal(() {
                if (d == null) {
                  err = tr('分享码解析失败，可能复制不完整');
                } else {
                  preview = d;
                }
              });
              return;
            }

            // 官方链接
            if (!OfficialDeck.looksLike(v)) {
              setLocal(() => err = tr('这不是官方卡组链接（lyc.ee 或 lycee-tcg.com）'));
              return;
            }
            setLocal(() => busy = true);
            final r = await OfficialDeck.fetch(v);
            if (!ctx.mounted) return;
            setLocal(() {
              busy = false;
              if (r.deck == null) {
                err = r.error ?? tr('官方卡组读取失败');
              } else {
                preview = r.deck;
                note = tr('官方页不提供主战卡，导入后请自己补上');
              }
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.viewInsetsOf(ctx).bottom + 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.download, size: 17, color: scheme.primary),
                    const SizedBox(width: 6),
                    Text(tr('导入卡组'),
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.content_paste, size: 16),
                      label: Text(tr('读剪贴板')),
                      onPressed: () async {
                        final d = await Clipboard.getData(Clipboard.kTextPlain);
                        final t = d?.text ?? '';
                        if (t.trim().isEmpty) {
                          setLocal(() => err = tr('剪贴板是空的'));
                          return;
                        }
                        ctrl.text = t.trim();
                        await parse(t);
                      },
                    ),
                  ],
                ),
                Text(tr('选一套识别系统，再把内容粘进来'),
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                // 识别系统用 LyTag 选（项目里禁用 SegmentedButton：高亮块和外框
                // 永远对不齐；也禁用 Chip 系列：去不掉自带的 surface 底）
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final DeckImportSource s in DeckImportSource.values)
                      LyTag(
                        label: deckImportSourceLabel(s),
                        selected: source == s,
                        onTap: () {
                          setLocal(() => source = s);
                          parse(ctrl.text);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  maxLines: 4,
                  minLines: 2,
                  autofocus: true,
                  onChanged: parse,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    hintText: source == DeckImportSource.official
                        ? tr('https://lyc.ee/d200009005189')
                        : tr('LYD1.... 或官方卡组链接'),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(tr('正在读取官方卡组…'),
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ],
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 15, color: scheme.error),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(err!,
                            style:
                                TextStyle(fontSize: 12, color: scheme.error)),
                      ),
                    ],
                  ),
                ],
                if (preview != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '「${preview!.name.isEmpty ? '未命名构筑' : preview!.name}」',
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '主卡组 ${preview!.total} 张'
                          '${preview!.sideboard.isEmpty ? '' : ' · 备卡区 ${preview!.sideboard.values.fold(0, (a, b) => a + b)} 张'}'
                          '${preview!.mainCardCode.isEmpty ? '' : ' · 主战卡 ${preview!.mainCardCode}'}',
                          style: TextStyle(
                              fontSize: 11.5, color: scheme.onSurfaceVariant),
                        ),
                        if (note != null) ...[
                          const SizedBox(height: 4),
                          Text(note!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check, size: 17),
                    label: Text(tr('导入为新卡组')),
                    onPressed: preview == null || busy
                        ? null
                        : () {
                            final deck = state.importDeckData(preview!);
                            if (deck == null) {
                              setLocal(() => err = tr('导入失败'));
                              return;
                            }
                            Navigator.pop(ctx, deck);
                          },
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          );
        },
      ),
    ),
  );

  ctrl.dispose();
  if (result != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('已导入「{0}」', [result.name]))));
  }
  return result;
}

/// 直接从一段文本导入（给剪贴板/浮窗用，不再弹输入框）。
///
/// 分享码和官方链接都能吃：官方链接会联网抓取。
Future<Deck?> importDeckFromText(
    BuildContext context, AppState state, String text) async {
  final t = text.trim();
  DeckData? data;
  String? err;

  if (DeckShare.looksLike(t)) {
    data = DeckShare.decode(t);
    if (data == null) err = tr('分享码解析失败，可能复制不完整');
  } else if (OfficialDeck.looksLike(t)) {
    final r = await OfficialDeck.fetch(t);
    data = r.deck;
    err = r.error;
  } else {
    err = tr('认不出来：既不是 LYD1 分享码，也不是官方卡组链接');
  }

  if (!context.mounted) return null;
  if (data == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? tr('导入失败'))));
    return null;
  }
  final deck = state.importDeckData(data);
  if (deck != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('已导入「{0}」', [deck.name]))));
  }
  return deck;
}

/// 供别处取用（避免重复 import provider）
AppState watchState(BuildContext c) => c.read<AppState>();
