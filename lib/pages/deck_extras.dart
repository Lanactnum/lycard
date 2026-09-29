import 'package:flutter/material.dart';
import '../widgets/deck_share_sheet.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../data/haptics.dart';
import '../services/print_service.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/glass.dart';
import 'draw_sim_page.dart';
import '../l10n/l10n.dart';

/// 构筑速览页的扩展块：简介 / 战绩 / 备卡区 / 快照 / 单卡菜单
/// （放在单独文件里，免得 deck_view_page.dart 太长）

String twoDigits(int n) => n < 10 ? '0$n' : '$n';

Future<String?> askDeckText(
    BuildContext context, String title, String hint) async {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration:
            InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: Text(tr('确定'))),
      ],
    ),
  );
}

/// 标题下面那一行：简介（细体斜体）+ 战绩
class DeckHeadline extends StatelessWidget {
  const DeckHeadline({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => editIntro(context, state, deck),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    deck.intro.isEmpty ? tr('点这里写简介…') : deck.intro,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: deck.intro.isEmpty
                          ? scheme.outline
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Icon(Icons.edit, size: 13, color: scheme.outline),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 6, 4),
          child: Row(
            children: [
              Icon(Icons.emoji_events_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                deck.hasBattles
                    ? tr('{0} 胜 {1} 负 · 胜率 {2}', [deck.wins, deck.losses, deck.winRateText])
                    : tr('还没记战绩'),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  final hasErr = state
                      .checkDeck(deck)
                      .any((i) => i.level == IssueLevel.error);
                  if (hasErr) Haptics.strong(state.haptics);
                  formatSheet(context, state, deck);
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.rule, size: 12, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 3),
                      Text(kFormatName[deck.format]!,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSecondaryContainer)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => battleSheet(context, state, deck),
                child: Text(tr('记录战绩')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 备卡区（0~10 张，可选）：点一下挪回主卡组，也能把主卡区的卡拖进来
class SideboardBar extends StatelessWidget {
  const SideboardBar({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final repo = CardRepository.instance;
    final codes = deck.sideboard.keys.toList();

    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => (deck.cards[d.data] ?? 0) > 0,
      onAcceptWithDetails: (d) => state.moveToSideboard(deck, d.data, 1),
      builder: (c, cand, rej) => Material(
        color: Colors.transparent,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz, size: 16, color: scheme.secondary),
                const SizedBox(width: 6),
                Text(tr('备卡区 {0}/{1}', [deck.sideTotal, Deck.maxSideboard]),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                if (codes.isEmpty)
                  Text(tr('（可选）'),
                      style: TextStyle(
                          fontSize: 11, color: scheme.onSurfaceVariant)),
                const Spacer(),
                TextButton(
                  onPressed: deck.cards.isEmpty
                      ? null
                      : () => pickToSideboard(context, state, deck),
                  child: Text(tr('加入备卡')),
                ),
              ],
            ),
            if (codes.isNotEmpty)
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: codes.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (c, i) {
                    final code = codes[i];
                    final card = repo.byCode(code);
                    return Tooltip(
                      message: tr('{0} ×{1}（点击撤回主卡组，也可拖出）', [code, deck.sideboard[code]]),
                      child: LongPressDraggable<String>(
                        data: code,
                        feedback: SizedBox(
                          width: 44,
                          child: Material(
                            elevation: 0,
                            borderRadius: BorderRadius.circular(8),
                            child: card == null
                                ? const Icon(Icons.help_outline)
                                : CardArt(card: card, showName: false),
                          ),
                        ),
                        childWhenDragging: Opacity(
                          opacity: 0.3,
                          child: SizedBox(
                            width: 38,
                            child: card == null
                                ? const Icon(Icons.help_outline)
                                : CardArt(card: card, showName: false),
                          ),
                        ),
                        child: InkWell(
                          onTap: () => state.moveToMain(deck, code, 1),
                          child: Stack(
                          children: [
                            SizedBox(
                              width: 38,
                              child: card == null
                                  ? const Icon(Icons.help_outline)
                                  : CardArt(card: card, showName: false),
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: scheme.secondary,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('${deck.sideboard[code]}',
                                    style: TextStyle(
                                        fontSize: 9, color: scheme.onSecondary)),
                              ),
                            ),
                          ],
                        ),
                          ),
                        ),
                      );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部「更多」菜单
Future<void> deckMenu(
    BuildContext context, AppState state, Deck deck, String v) async {
  switch (v) {
    case 'draw':
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DrawSimPage(deck: deck),
      ));
    case 'share':
      await showDeckShareSheet(context, state, deck);
    case 'print':
      await printDeckFlow(context, state, deck);
    case 'intro':
      await editIntro(context, state, deck);
    case 'battles':
      await battleSheet(context, state, deck);
    case 'snapshot':
      final label =
          await askDeckText(context, tr('存一个版本快照'), tr('名称'));
      if (label != null && label.isNotEmpty) {
        state.saveSnapshot(deck, label);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(tr('已保存快照「{0}」', [label]))));
        }
      }
    case 'versions':
      await versionsSheet(context, state, deck);
    case 'format':
      await formatSheet(context, state, deck);
    case 'cover':
      await coverSheet(context, state, deck);
    case 'stats':
      await statsSheet(context, state, deck);
    case 'missing':
      state.setHideMissing(deck, !deck.hideMissing);
  }
}

/// 设置构筑封面（要求 L75）
Future<void> coverSheet(
    BuildContext context, AppState state, Deck deck) async {
  final repo = CardRepository.instance;
  final codes = deck.cards.keys.toList()..sort();
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('构筑封面'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text(tr('未设置封面时，使用主战卡或构筑里第一张卡'),
                style: TextStyle(fontSize: 11)),
            const SizedBox(height: 8),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome),
              title: Text(tr('自动'), style: TextStyle(fontSize: 13)),
              onTap: () {
                state.setDeckCover(deck, '');
                Navigator.pop(c);
              },
            ),
            const Divider(height: 1),
            if (codes.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('构筑里还没有卡'), style: TextStyle(fontSize: 13)),
              )
            else
              SizedBox(
                height: 300,
                child: GridView.builder(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: codes.length,
                  itemBuilder: (c, i) {
                    final card = repo.byCode(codes[i]);
                    return InkWell(
                      onTap: () {
                        state.setDeckCover(deck, codes[i]);
                        Navigator.pop(c);
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: card == null
                                ? const Icon(Icons.help_outline)
                                : CardArt(card: card, showName: false),
                          ),
                          if (deck.coverCode == codes[i])
                            const Positioned(
                              right: 2,
                              top: 2,
                              child: Icon(Icons.check_circle,
                                  size: 16, color: Colors.lightGreen),
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
    ),
  );
}

/// 统计图显示方式（要求 L92：浮窗显示 / 可选择性显示）
Future<void> statsSheet(
    BuildContext context, AppState state, Deck deck) async {
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tr('统计图'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            subtitle: Text(tr('属性分布/费用分布/卡种比例（只统计主卡区）'),
                style: TextStyle(fontSize: 11)),
          ),
          SwitchListTile(
            title: Text(tr('显示统计图')),
            value: state.statsVisible,
            onChanged: state.setStatsVisible,
          ),
        ],
      ),
    ),
  );
}

/// 规则模式选择：不同比赛规则用不同的构筑校验算法
Future<void> formatSheet(
    BuildContext context, AppState state, Deck deck) async {
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tr('规则模式'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            subtitle: Text(tr('切换后构筑校验按新规则重新检查'),
                style: TextStyle(fontSize: 11)),
          ),
          for (final f in DeckFormat.values)
            ListTile(
              title: Text(kFormatName[f] ?? f.name),
              subtitle: Text(kFormatDesc[f] ?? '',
                  style: const TextStyle(fontSize: 11)),
              trailing: deck.format == f
                  ? Icon(Icons.check,
                      color: Theme.of(c).colorScheme.primary)
                  : null,
              onTap: () {
                state.setDeckFormat(deck, f);
                Navigator.pop(c);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> editIntro(BuildContext context, AppState state, Deck deck) async {
  final ctrl = TextEditingController(text: deck.intro);
  final t = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('构筑简介')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: tr('打法思路、针对对象…'),
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text),
            child: Text(tr('保存'))),
      ],
    ),
  );
  if (t != null) state.setIntro(deck, t.trim());
}

/// 胜负记录：记一场 + 看历史
Future<void> battleSheet(
    BuildContext context, AppState state, Deck deck) async {
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                tr('胜负记录 · {0} 胜 {1} 负 · 胜率 {2}', [deck.wins, deck.losses, deck.winRateText]),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        addBattleDialog(context, state, deck, true),
                    icon: const Icon(Icons.check),
                    label: Text(tr('记一胜')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        addBattleDialog(context, state, deck, false),
                    icon: const Icon(Icons.close),
                    label: Text(tr('记一负')),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (deck.battles.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('还没有战绩记录'), style: TextStyle(fontSize: 13)),
              )
            else
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: deck.battles.length,
                  itemBuilder: (c, i) {
                    final b = deck.battles[i];
                    final d = b.at;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        b.win
                            ? Icons.emoji_events
                            : Icons.sentiment_dissatisfied,
                        color: b.win ? Colors.amber.shade600 : null,
                      ),
                      title: Text(
                        '${b.win ? '胜' : '负'}'
                        '${b.opponent.isEmpty ? '' : ' · vs ${b.opponent}'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${d.year}-${twoDigits(d.month)}-${twoDigits(d.day)}'
                        '${b.memo.isEmpty ? '' : ' · ${b.memo}'}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () => state.removeBattle(deck, b.id),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> addBattleDialog(
    BuildContext context, AppState state, Deck deck, bool win) async {
  final memo = TextEditingController();
  final opp = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(win ? tr('记一胜') : tr('记一负')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: opp,
            decoration: InputDecoration(
                labelText: tr('对手（选填）'), border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: memo,
            decoration: InputDecoration(
                labelText: tr('备注（选填）'), border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: Text(tr('记下'))),
      ],
    ),
  );
  if (ok == true) {
    state.addBattle(deck,
        win: win, memo: memo.text.trim(), opponent: opp.text.trim());
  }
}

/// 版本快照列表：可回滚 / 删除
Future<void> versionsSheet(
    BuildContext context, AppState state, Deck deck) async {
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('版本快照'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(tr('回滚会将卡表和「该版本的胜负记录」一起回滚'),
                style: TextStyle(fontSize: 11)),
            const Divider(height: 18),
            if (deck.snapshots.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(tr('还没有快照。点右上角「⋮ → 存一个版本快照」'),
                    style: TextStyle(fontSize: 13)),
              )
            else
              SizedBox(
                height: 260,
                child: ListView.builder(
                  itemCount: deck.snapshots.length,
                  itemBuilder: (c, i) {
                    final s = deck.snapshots[i];
                    return ListTile(
                      dense: true,
                      title: Text(s.label,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        tr('{0} 张 · {1} 胜 {2} 负 · {3}-{4}-{5}', [s.total, s.wins, s.losses, s.at.year, twoDigits(s.at.month), twoDigits(s.at.day)]),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (cc) => AlertDialog(
                                  title: Text(tr('回滚到这个版本？')),
                                  content:
                                      Text(tr('当前卡表会被「{0}」覆盖，包括胜负记录。', [s.label])),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(cc, false),
                                        child: Text(tr('算了'))),
                                    FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(cc, true),
                                        child: Text(tr('回滚'))),
                                  ],
                                ),
                              );
                              if (ok == true) {
                                state.rollbackSnapshot(deck, s.id);
                                if (context.mounted) Navigator.pop(context);
                              }
                            },
                            child: Text(tr('回滚')),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => state.deleteSnapshot(deck, s.id),
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
    ),
  );
}

/// 长按某张卡：MVP / 心得 / 挪到备卡区
Future<void> cardMenu(
    BuildContext context, AppState state, Deck deck, String code) async {
  final card = CardRepository.instance.byCode(code);
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(card?.displayName ?? code,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('{0} · 主卡组 {1} 张', [code, deck.cards[code] ?? 0])),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(deck.mvpCodes.contains(code)
                ? Icons.star
                : Icons.star_border),
            title:
                Text(deck.mvpCodes.contains(code) ? tr('取消 MVP 标记') : tr('标记为 MVP')),
            onTap: () {
              state.toggleMvp(deck, code);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.sticky_note_2_outlined),
            title: Text(tr('写单卡心得')),
            subtitle: Text(
              (deck.cardNotes[code] ?? '').isEmpty
                  ? tr('还没有')
                  : deck.cardNotes[code]!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
            onTap: () async {
              Navigator.pop(context);
              final t = await askDeckText(
                  context, tr('单卡心得'), tr('比如：这套牌靠它在第2回合出场'));
              if (t != null) state.setCardNote(deck, code, t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(tr('放到备卡区')),
            enabled: (deck.cards[code] ?? 0) > 0 &&
                deck.sideTotal < Deck.maxSideboard,
            onTap: () {
              state.moveToSideboard(deck, code, 1);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    ),
  );
}

/// 从主卡组挑一张挪进备卡区
Future<void> pickToSideboard(
    BuildContext context, AppState state, Deck deck) async {
  final repo = CardRepository.instance;
  final codes = deck.cards.keys.toList()..sort();
  final code = await showGlassSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: codes.length,
        itemBuilder: (cc, i) => ListTile(
          dense: true,
          title: Text(repo.byCode(codes[i])?.displayName ?? codes[i],
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(tr('{0} · {1} 张', [codes[i], deck.cards[codes[i]]])),
          onTap: () => Navigator.pop(cc, codes[i]),
        ),
      ),
    ),
  );
  if (code != null) state.moveToSideboard(deck, code, 1);
}
