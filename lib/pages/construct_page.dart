import 'package:flutter/material.dart';

import '../widgets/deck_import_dialog.dart';

import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../models/lycee_card.dart';
import '../services/print_service.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/deck_dialogs.dart';
import '../widgets/motion.dart';
import 'deck_view_page.dart';
import 'mine_page.dart' show DeckEditorPage;
import '../widgets/glass.dart';
import '../widgets/scatter.dart';
import '../widgets/layout.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/card_route.dart';
import '../widgets/glass_menu.dart';
import 'scan_page.dart';
import '../widgets/deck_share_sheet.dart';
import '../l10n/l10n.dart';

/// 底栏「构筑」：全部构筑的列表
///
/// 每行左边一张**悬浮的大封面**（没设封面就用主战卡，再没有就用第一张卡），
/// 右边跟着几张卡面小图 + 构筑名 / 张数。
class ConstructPage extends StatelessWidget {
  const ConstructPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: WeightText(tr('构筑'), base: 500, max: 900),
        actions: [
          IconButton(
            tooltip: tr('扫码导入卡组'),
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () async {
              final r = await ScanPage.show(context);
              if (r == null || !context.mounted) return;
              await importDeckFromText(context, state, r);
            },
          ),
          IconButton(
            tooltip: tr('导入卡组（粘贴分享码）'),
            icon: const Icon(Icons.download_outlined),
            onPressed: () => showDeckImportDialog(context, state),
          ),
          IconButton(
            tooltip: tr('构筑编辑'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const DeckEditorPage())),
          ),
        ],
      ),
      body: state.decks.isEmpty
          ? const _EmptyDecks()
          : ScrollWeightScope(
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(12, 12, 12, kBottomBarSpace),
                itemCount: state.decks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (c, i) => ScatterItem(
                  index: i,
                  strength: 0.7,
                  child: SpringIn(
                    delay: Duration(milliseconds: i * 28),
                    child: _DeckRow(deck: state.decks[i]),
                  ),
                ),
              ),
            ),
      avoidBottomBar: true, // 底栏是悬浮胶囊，FAB 要让开
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showCreateDeckDialog(context, state),
        icon: const Icon(Icons.add),
        label: Text(tr('新建构筑')),
      ),
    );
  }
}

class _EmptyDecks extends StatelessWidget {
  const _EmptyDecks();

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 14),
          Text(tr('还没有构筑')),
          const SizedBox(height: 6),
          Text(
            tr('点右下角新建一套吧'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () => showCreateDeckDialog(context, state),
            icon: const Icon(Icons.add),
            label: Text(tr('新建构筑')),
          ),
        ],
      ),
    );
  }
}

/// 取封面卡：封面 → 主战卡 → 构筑里第一张卡
LyceeCard? deckCoverCard(Deck d) {
  final repo = CardRepository.instance;
  final c = repo.byCode(d.coverCode);
  if (c != null) return c;
  final m = repo.byCode(d.mainCardCode);
  if (m != null) return m;
  for (final code in d.cards.keys) {
    final f = repo.byCode(code);
    if (f != null) return f;
  }
  return null;
}

class _DeckRow extends StatelessWidget {
  const _DeckRow({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final repo = CardRepository.instance;
    final cover = deckCoverCard(deck);

    // 右边的几张卡面小图：取构筑里的前几张（跳过封面那张）
    final smallCodes = <String>[];
    for (final code in deck.cards.keys) {
      if (cover != null && code == cover.code) continue;
      smallCodes.add(code);
      if (smallCodes.length >= 4) break;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(state.cornerRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(state.cornerRadius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => DeckViewPage(deckId: deck.id)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 悬浮的大封面
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2, right: 12),
                child: Material(
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(
                    width: 66,
                    height: 92,
                    child: cover == null
                        ? Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.style_outlined,
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        : CardHero(
                            code: cover.code,
                            scope: 'deckrow',
                            child: CardArt(card: cover, showName: false),
                          ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            deck.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          tr('{0} 张', [deck.total]),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (_lackOf(state, deck) > 0 ||
                        _conflictOf(state, deck) > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (_lackOf(state, deck) > 0)
                            _miniTag(
                              tr('缺 {0} 张', [_lackOf(state, deck)]),
                              scheme.error,
                            ),
                          if (_conflictOf(state, deck) > 0)
                            _miniTag(
                              tr('多卡组卡数不足 {0} 张', [_conflictOf(state, deck)]),
                              scheme.tertiary,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 40,
                      child: Row(
                        children: [
                          for (final code in smallCodes)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Opacity(
                                opacity: state.isOwned(code) ? 1 : 0.45,
                                child: SizedBox(
                                  width: 28,
                                  child: CardArt(
                                    card: repo.byCode(code)!,
                                    showName: false,
                                  ),
                                ),
                              ),
                            ),
                          if (smallCodes.isEmpty)
                            Text(
                              tr('还没放卡'),
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              GlassMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'share') {
                    await showDeckShareSheet(context, state, deck);
                  } else if (v == 'print') {
                    await printDeckFlow(context, state, deck);
                  } else if (v == 'edit') {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DeckEditorPage()),
                    );
                  } else if (v == 'rename') {
                    final ctrl = TextEditingController(text: deck.name);
                    final name = await showDialog<String>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(tr('重命名构筑')),
                        content: TextField(controller: ctrl, autofocus: true),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: Text(tr('取消')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
                            child: Text(tr('保存')),
                          ),
                        ],
                      ),
                    );
                    if (name != null && name.isNotEmpty) {
                      state.renameDeck(deck, name);
                    }
                  } else if (v == 'delete') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: Text(tr('删除构筑')),
                        content: Text(tr('确定删除「{0}」吗？', [deck.name])),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: Text(tr('不删')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: Text(tr('删除')),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) state.deleteDeck(deck.id);
                  }
                },
                items: [
                  GlassMenuItem('share', tr('分享卡组'), icon: Icons.qr_code_2),
                  GlassMenuItem('print', tr('打印卡图…'),
                      icon: Icons.print_outlined),
                  GlassMenuItem('edit', tr('编辑卡表'), icon: Icons.list_alt),
                  GlassMenuItem(
                    'rename',
                    tr('重命名'),
                    icon: Icons.drive_file_rename_outline,
                  ),
                  GlassMenuItem(
                    'delete',
                    tr('删除'),
                    icon: Icons.delete_outline,
                    danger: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────── 构筑列表上的小提示 ─────────────────────

/// 这套构筑还缺几张（0 = 齐了）
int _lackOf(AppState state, Deck deck) =>
    state.missingOf(deck).fold<int>(0, (a, m) => a + (m.$2 - m.$3));

/// 这套构筑里「跟别的构筑抢同一张实物卡」的卡数
int _conflictOf(AppState state, Deck deck) {
  final conflicts = state.conflictCodes.toSet();
  return deck.cards.keys.where(conflicts.contains).length;
}

Widget _miniTag(String text, Color c) => Padding(
  padding: const EdgeInsets.only(right: 6),
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: c)),
  ),
);
