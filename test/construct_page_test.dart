import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/pages/construct_page.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 底栏「构筑」页的新布局：封面大图（悬浮）+ 卡面小图 + 构筑名/张数
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('封面回退顺序：封面 → 主战卡 → 第一张卡', () async {
    SharedPreferences.setMockInitialValues({});
    await CardRepository.instance.load();
    final state = await AppState.create();
    final repo = CardRepository.instance;

    final deck = state.createDeck('测试套牌');
    expect(deckCoverCard(deck), isNull, reason: '空构筑没有封面');

    // 放两张卡 → 没设主战卡时，封面应当回退到「第一张卡」
    state.addCard(deck, repo.byCode('LO-0575')!, 4);
    state.addCard(deck, repo.byCode('LO-6281')!, 2);
    final first = deck.cards.keys.first;
    // ignore: avoid_print
    debugPrint('无主战卡时封面 = ${deckCoverCard(deck)?.code}（第一张是 $first）');
    expect(deckCoverCard(deck)?.code, first);

    // 设了主战卡 → 用主战卡
    state.setDeckMain(deck, 'LO-6281');
    // ignore: avoid_print
    debugPrint('设主战卡后封面 = ${deckCoverCard(deck)?.code}');
    expect(deckCoverCard(deck)?.code, 'LO-6281');

    // 设了封面 → 用封面
    state.setDeckCover(deck, 'LO-0575');
    expect(deckCoverCard(deck)?.code, 'LO-0575');

    // 终极回退：封面/主战卡都无效 → 第一张卡
    state.setDeckCover(deck, '');
    deck.mainCardCode = '';
    expect(deckCoverCard(deck)?.code, first);
  });

  testWidgets('构筑页能渲染出构筑行', (tester) async {
    late AppState state;
    // 真实 IO（读资产 / 写偏好）必须用 runAsync，否则 FakeAsync 里永远等不到
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      await CardRepository.instance.load();
      state = await AppState.create();
      final deck = state.createDeck('雪之铁槌');
      state.addCard(deck, CardRepository.instance.byCode('LO-0575')!, 4);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: ConstructPage()),
      ),
    );
    await tester.pump();

    expect(find.text('雪之铁槌'), findsOneWidget);
    expect(find.text('4 张'), findsOneWidget);
    expect(find.text('新建构筑'), findsWidgets);
  });
}
