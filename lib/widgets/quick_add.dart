import 'package:flutter/material.dart';

import '../data/haptics.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import 'motion.dart';
import 'glass.dart';
import '../l10n/l10n.dart';

/// 快速编辑已有卡牌（要求 L62）：直接在当前页面 「+1 / -1」 放进某套构筑。
///
/// 单张卡 → 列出所有构筑，每套一行带 -/+；
/// 多张卡 → 先选一套构筑，然后每张各加 1。
Future<void> quickAddSheet(
  BuildContext context,
  AppState state,
  List<LyceeCard> cards,
) async {
  if (cards.isEmpty) return;
  final single = cards.length == 1;

  await showGlassSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setLocal) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                single ? cards.first.displayName : tr('把 {0} 张卡加进构筑', [cards.length]),
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                single
                    ? tr('{0} · 直接使用 +/- 修改张数', [cards.first.code])
                    : '每套牌各增加 1 张：${cards.map((e) => e.code).take(4).join(' ')}'
                        '${cards.length > 4 ? ' …' : ''}',
                style: const TextStyle(fontSize: 11),
              ),
              const Divider(height: 18),
              if (state.decks.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(tr('还没有构筑 —— 先去底栏「构筑」新建一套'),
                      style: TextStyle(fontSize: 13)),
                )
              else
                SizedBox(
                  height: 300,
                  child: ListView(
                    children: [
                      for (final d in state.decks)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(d.name, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            single
                                ? tr('现在 {0} 张 · 主卡组 {1} 张', [d.cards[cards.first.code] ?? 0, d.total])
                                : tr('主卡组 {0} 张', [d.total]),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: single
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '-1',
                                      icon: const Icon(
                                          Icons.remove_circle_outline),
                                      onPressed: () {
                                        state.removeCard(d, cards.first.code, 1);
                                        Haptics.tick(state.haptics);
                                        setLocal(() {});
                                      },
                                    ),
                                    Jelly(
                                      trigger: d.cards[cards.first.code] ?? 0,
                                      child: Text(
                                        '${d.cards[cards.first.code] ?? 0}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: '+1',
                                      icon: const Icon(Icons.add_circle_outline),
                                      onPressed: () {
                                        state.addCard(d, cards.first, 1);
                                        Haptics.tap(state.haptics);
                                        setLocal(() {});
                                      },
                                    ),
                                  ],
                                )
                              : FilledButton.tonal(
                                  onPressed: () {
                                    for (final card in cards) {
                                      state.addCard(d, card, 1);
                                    }
                                    Haptics.tap(state.haptics);
                                    Navigator.pop(c);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              tr('已把 {0} 张卡加进「{1}」', [cards.length, d.name]))),
                                    );
                                  },
                                  child: Text(tr('全加 1 张')),
                                ),
                          onTap: single
                              ? null
                              : () {
                                  for (final card in cards) {
                                    state.addCard(d, card, 1);
                                  }
                                  Haptics.tap(state.haptics);
                                  Navigator.pop(c);
                                },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
