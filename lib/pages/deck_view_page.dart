import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/deck_stats.dart';
import '../widgets/responsive.dart';
import 'deck_extras.dart';
import 'mine_page.dart' show DeckEditorPage;
import '../widgets/glass.dart';
import '../widgets/card_route.dart';
import '../widgets/scatter.dart';
import '../widgets/layout.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/glass_menu.dart';
import '../l10n/l10n.dart';

/// 一套构筑的速览（主战卡 + 全部卡面 + 张数）
class DeckViewPage extends StatelessWidget {
  const DeckViewPage({super.key, required this.deckId});

  final String deckId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final deck = state.decks.where((d) => d.id == deckId).firstOrNull;
    if (deck == null) {
      return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
        appBar: GlassAppBar(),
        body: Center(child: Text(tr('这套构筑已经不在了'))),
      );
    }
    final repo = CardRepository.instance;
    final cols = resolveColumns(context, state.gridColumns);
    final gap = resolveGap(context);

    final entries = deck.cards.entries
        .map((e) => (card: repo.byCode(e.key), n: e.value))
        .where((e) => e.card != null)
        .toList();

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(deck.name),
        actions: [
          IconButton(
            tooltip: tr('编辑构筑'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeckEditorPage()),
            ),
          ),
          IconButton(
            tooltip: tr('手动列数'),
            icon: const Icon(Icons.grid_view),
            onPressed: () async {
              final v = await showColumnPicker(context, state);
              if (v != null) state.setGridColumns(v);
            },
          ),
          GlassMenuButton<String>(
            tooltip: tr('更多'),
            onSelected: (v) => deckMenu(context, state, deck, v),
            items: [
              GlassMenuItem('draw', tr('起手模拟/摸牌测试'),
                  icon: Icons.casino_outlined),
              GlassMenuItem('share', tr('分享卡组'),
                  icon: Icons.ios_share),
              GlassMenuItem('print', tr('打印卡图…'),
                  icon: Icons.print_outlined),
              GlassMenuItem('intro', tr('编辑简介'), icon: Icons.notes),
              GlassMenuItem('cover', tr('设置封面…'), icon: Icons.image_outlined),
              GlassMenuItem('battles', tr('胜负记录'), icon: Icons.sports_score),
              GlassMenuItem('format', tr('规则模式…'), icon: Icons.rule),
              GlassMenuItem('stats', tr('统计图…'), icon: Icons.pie_chart_outline),
              GlassMenuItem('missing',
                  deck.hideMissing ? tr('显示缺卡提醒') : tr('忽略缺卡提醒'),
                  icon: deck.hideMissing
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
              GlassMenuItem('snapshot', tr('存一个版本快照'),
                  icon: Icons.camera_alt_outlined),
              GlassMenuItem('versions', tr('版本快照（{0}）', [deck.snapshots.length]),
                  icon: Icons.history),
            ],
          ),
        ],
      ),
      // 整页一个 CustomScrollView：顶部那些信息（主战卡条 / 标题 / 统计 /
      // 缺卡条 / 备卡区）以前是固定的 Column，往上划不动，把下面看卡面的
      // 区域挤得很小。现在它们是会跟着滚走的 sliver。
      body: DragTarget<String>(
        onAcceptWithDetails: (d) => state.moveToMain(deck, d.data, 1),
        builder: (c, cand, rej) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  _MainCardBar(deck: deck),
                  DeckHeadline(deck: deck),
                  if (state.statsVisible) DeckStats(deck: deck),
                  const Divider(height: 1),
                  _MissingBar(deck: deck),
                  SideboardBar(deck: deck),
                ],
              ),
            ),
            if (entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(tr('这套构筑还是空的'))),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gap, gap, gap, kBottomBarSpace),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: entries.length,
                  itemBuilder: (c, i) {
                      final e = entries[i];
                      return ScatterItem(
                        index: i,
                        strength: 0.6,
                        code: e.card!.code,
                        child: Stack(
                        children: [
                          Positioned.fill(
                            child: InkWell(
                              onTap: () => openCardDetail(context, e.card!.code, scope: 'deck$i'),
                              onLongPress: () =>
                                  cardMenu(context, state, deck, e.card!.code),
                              child: LongPressDraggable<String>(
                                data: e.card!.code,
                                feedback: SizedBox(
                                  width: 70,
                                  child: Material(
                                    elevation: 0,
                                    borderRadius: BorderRadius.circular(10),
                                    child: CardArt(
                                        card: e.card!, showName: false),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.3,
                                  child: CardArt(card: e.card!),
                                ),
                                child: CardHero(
                                  code: e.card!.code,
                                  scope: 'deck$i',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: CardArt(card: e.card!),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (deck.mvpCodes.contains(e.card!.code))
                            Positioned(
                              left: 4,
                              top: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text('MVP',
                                    style: TextStyle(
                                        fontSize: 9, color: Colors.black)),
                              ),
                            ),
                          if ((deck.cardNotes[e.card!.code] ?? '').isNotEmpty)
                            Positioned(
                              left: 4,
                              bottom: 4,
                              child: Icon(Icons.sticky_note_2,
                                  size: 14,
                                  color: Theme.of(context).colorScheme.tertiary),
                            ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              child: Text('${e.n}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary)),
                            ),
                          ),
                        ],
                      ),
                      );
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// 缺卡条：还缺几张 / 预计多少钱 / 一键入想要
class _MissingBar extends StatelessWidget {
  const _MissingBar({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final missing = state.missingOf(deck);
    // 缺卡提醒可以手动忽略
    if (missing.isEmpty || deck.hideMissing) return const SizedBox.shrink();

    final totalLack = missing.fold<int>(0, (a, m) => a + (m.$2 - m.$3));
    final cost = state.missingCostOf(deck);

    // 融入背景：和统计块 / 备卡区一样不铺底
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(state.cornerRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '还缺 ${missing.length} 种 / $totalLack 张 · 预计补齐 '
                '${cost == null ? '-' : '¥${cost.toStringAsFixed(2)}'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => _missingDialog(context, state, deck, missing),
              child: Text(tr('入想要')),
            ),
            TextButton(
              onPressed: () => state.setHideMissing(deck, true),
              child: Text(tr('忽略')),
            ),
          ],
        ),
      ),
    );
  }
}

/// 弹窗：勾选要加进「想要」的缺卡
Future<void> _missingDialog(
  BuildContext context,
  AppState state,
  Deck deck,
  List<(String code, int need, int have)> missing,
) async {
  final picked = <String>{for (final m in missing) m.$1};
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => AlertDialog(
        title: Text(tr('缺卡入「想要」（{0} 种）', [missing.length])),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in missing)
                CheckboxListTile(
                  dense: true,
                  value: picked.contains(m.$1),
                  onChanged: (v) => setLocal(() {
                    v == true ? picked.add(m.$1) : picked.remove(m.$1);
                  }),
                  title: Text(
                    CardRepository.instance.byCode(m.$1)?.displayName ?? m.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(tr('{0} · 需要 {1} 张，已有 {2} 张', [m.$1, m.$2, m.$3]),
                      style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('加入 {0} 张', [picked.length])),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  final n = state.addMissingToWant(deck, picked.toList());
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(n == 0 ? tr('这些卡已经在「想要」里了') : tr('已把 {0} 张卡加入「想要」', [n]))),
  );
}

/// 列数选择弹窗（构筑页和速览页共用）
Future<int?> showColumnPicker(BuildContext context, AppState state) {
  return showGlassSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(tr('每行卡片数'))),
          for (final n in [0, 2, 3, 4, 5, 6, 8])
            ListTile(
              title: Text(n == 0 ? tr('自动') : tr('{0} 列', [n])),
              trailing: state.gridColumns == n ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(c, n),
            ),
        ],
      ),
    ),
  );
}

class _MainCardBar extends StatelessWidget {
  const _MainCardBar({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final card = CardRepository.instance.byCode(deck.mainCardCode);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: card == null
                ? Icon(Icons.military_tech_outlined,
                    color: scheme.onSurfaceVariant)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: CardArt(card: card),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('主战'),
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                Text(
                  card?.displayName ?? tr('未设置主战卡'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                Text(tr('{0} / {1} 张', [deck.total, DeckRules.mainDeckSize]),
                    style:
                        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
