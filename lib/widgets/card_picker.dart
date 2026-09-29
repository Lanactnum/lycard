import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../l10n/l10n.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import 'card_art.dart';
import 'glass.dart';
import 'layout.dart';
import 'tags.dart';

/// 通用选卡弹窗：搜索框 + 卡图网格，点一张返回卡号。
///
/// [decks] 非空时，顶部会多一排「我的卡组」入口 —— 对局中摆牌时
/// 直接从自己的卡组里挑，比按卡名搜快得多。
///
/// 原来这个方法藏在 `mine_page.dart` 里（`_pickCard`），计算器也要用，
/// 就提出来放这儿；两边共用同一份，避免以后改一处漏一处。
Future<String?> pickCard(
  BuildContext context, {
  required String title,
  String? initialQuery,
  List<Deck>? decks,
}) {
  final ctrl = TextEditingController(text: initialQuery ?? '');

  // ⚠⚠ `res` / `fromDeck` 必须放在 showGlassSheet **外面**。
  //
  // 放在里面（builder 里）会出这个 bug：底部面板每次重建 —— 最典型的就是
  // 输入法弹出/收起改变 viewInsets、键盘一关触发路由重建 —— 都会重新执行
  // builder，把「现在正在看哪个卡组」清回 null，表现就是
  // 「点一下卡组只闪一下屏幕、切不过去，又被弹回搜索框」。
  //
  // 同一个坑 `deck_share_sheet.dart` 里也踩过（那里的注释写的是
  // 「注意必须放在 StatefulBuilder 外面，否则每次重建都会重置」）。
  var res = <LyceeCard>[];
  Deck? fromDeck; // 非空 = 正在看某个卡组

  return showGlassSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      return StatefulBuilder(
        builder: (c, setSheet) {
          final List<Deck> deckList = decks ?? const <Deck>[];

          List<LyceeCard> deckCards() {
            final Deck? d = fromDeck;
            if (d == null) return const <LyceeCard>[];
            final List<LyceeCard> out = <LyceeCard>[];
            for (final String code in d.cards.keys) {
              final LyceeCard? card = CardRepository.instance.byCode(code);
              if (card != null) out.add(card);
            }
            return out;
          }

          final bool browsingDeck = fromDeck != null;
          final List<LyceeCard> shown = browsingDeck ? deckCards() : res;

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(c).bottom,
            ),
            child: SizedBox(
              height: MediaQuery.sizeOf(c).height * 0.78,
              child: Column(
                children: [
                  ListTile(title: Text(title)),
                  if (deckList.isNotEmpty) ...[
                    // 卡组切换：默认「卡库搜索」，点卡组名就换成该卡组的牌
                    SizedBox(
                      height: 34,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          LyTag(
                            label: tr('卡库搜索'),
                            selected: !browsingDeck,
                            onTap: () => setSheet(() => fromDeck = null),
                          ),
                          for (final Deck d in deckList) ...[
                            const SizedBox(width: 8),
                            LyTag(
                              label: '${d.name}（${d.total}）',
                              selected: fromDeck?.id == d.id,
                              onTap: () => setSheet(() => fromDeck = d),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (!browsingDeck)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        keyboardType: context.read<AppState>().searchNumberPad
                            ? const TextInputType.numberWithOptions()
                            : TextInputType.text,
                        decoration: InputDecoration(hintText: tr('卡名/卡号')),
                        onChanged: (q) => setSheet(() {
                          res = CardRepository.instance.search(q, limit: 60);
                        }),
                      ),
                    ),
                  Expanded(
                    child: shown.isEmpty
                        ? Center(
                            child: Text(
                              browsingDeck
                                  ? tr('这个卡组还是空的')
                                  : tr('输入卡名或卡号开始搜索'),
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(
                              12,
                              12,
                              12,
                              kBottomBarSpace,
                            ),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 8,
                              crossAxisSpacing: 8,
                              childAspectRatio: 2 / 3,
                            ),
                            itemCount: shown.length,
                            itemBuilder: (c, i) => InkWell(
                              onTap: () => Navigator.pop(c, shown[i].code),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CardArt(card: shown[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
