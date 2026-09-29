import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:lycee_app/widgets/deck_stats.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 要求 60：构筑规则模式切换（自由 / 单作品 / 混合属性 / 限定赛）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh() async {
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await AppState.create();
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await CardRepository.instance.load();
    return AppState.create();
  }

  List<String> errorsOf(AppState s, Deck d) => s
      .checkDeck(d)
      .where((i) => i.level == IssueLevel.error)
      .map((i) => i.message)
      .toList();

  test('自由构筑：只查 60 张 / 同编号 / leader / 备卡区', () async {
    final s = await fresh();
    final d = s.createDeck('自由套牌');
    d.cards['LO-0575'] = 60;
    final errs = errorsOf(s, d);
    // ignore: avoid_print
    debugPrint('自由构筑 60 张同一张卡：${errs.join(' | ')}');
    expect(errs.any((m) => m.contains('相同编号上限 4 张')), isTrue);
    expect(errs.any((m) => m.contains('应为 60 张')), isFalse);
  });

  test('限定赛：30 张 / 同编号 2 张 / 不能带备卡', () async {
    final s = await fresh();
    final d = s.createDeck('限定赛套牌');
    s.setDeckFormat(d, DeckFormat.sealed);
    d.cards['LO-0575'] = 31; // 张数也不对
    d.sideboard['LO-0575'] = 1;

    final errs = errorsOf(s, d);
    // ignore: avoid_print
    debugPrint('限定赛：${errs.join(' | ')}');
    expect(errs.any((m) => m.contains('应为 30 张')), isTrue);
    expect(errs.any((m) => m.contains('相同编号上限 2 张')), isTrue);
    expect(errs.any((m) => m.contains('不能带备卡区')), isTrue);

    // 改回自由构筑 → 30 张就变成「还差 30 张」了
    s.setDeckFormat(d, DeckFormat.libre);
    final errs2 = errorsOf(s, d);
    // ignore: avoid_print
    debugPrint('改回自由构筑后：${errs2.first}');
    expect(errs2.any((m) => m.contains('应为 60 张')), isTrue);
  });

  test('单作品构筑：混了两个作品就报错', () async {
    final s = await fresh();
    final repo = CardRepository.instance;
    final d = s.createDeck('单作品套牌');
    s.setDeckFormat(d, DeckFormat.neoClassic);

    // 找两张不同作品的卡
    final a = repo.all.firstWhere(
        (c) => (c.series ?? '').trim().isNotEmpty && c.kind == 'キャラクター');
    final b = repo.all.firstWhere((c) =>
        (c.series ?? '').trim().isNotEmpty &&
        c.series != a.series &&
        c.kind == 'キャラクター');
    // ignore: avoid_print
    debugPrint('选了两张：${a.code}(${a.series}) 和 ${b.code}(${b.series})');
    expect(a.series, isNot(b.series));

    d.cards[a.code] = 30;
    final same = errorsOf(s, d);
    expect(same.any((m) => m.contains('单作品')), isFalse,
        reason: '只有一个作品时不该报错');

    d.cards[b.code] = 30;
    final mixed = errorsOf(s, d);
    // ignore: avoid_print
    debugPrint('混两个作品：${mixed.where((m) => m.contains('单作品')).join()}');
    expect(mixed.any((m) => m.contains('单作品')), isTrue);
  });

  test('混合属性构筑：属性最多 2 种', () async {
    final s = await fresh();
    final repo = CardRepository.instance;
    final d = s.createDeck('混合属性套牌');
    s.setDeckFormat(d, DeckFormat.hybrid);

    final byColor = <String, String>{};
    for (final c in repo.all) {
      final col = (c.color ?? '').trim();
      if (col.length == 1 && !byColor.containsKey(col)) {
        byColor[col] = c.code;
      }
      if (byColor.length >= 3) break;
    }
    final codes = byColor.values.toList();
    // ignore: avoid_print
    debugPrint('挑了三种属性：$byColor');
    expect(codes.length, 3);

    d.cards[codes[0]] = 20;
    d.cards[codes[1]] = 20;
    var errs = errorsOf(s, d);
    expect(errs.any((m) => m.contains('混合属性')), isFalse, reason: '2 种属性应该合法');

    d.cards[codes[2]] = 20;
    errs = errorsOf(s, d);
    // ignore: avoid_print
    debugPrint('三种属性：${errs.where((m) => m.contains('混合属性')).join()}');
    expect(errs.any((m) => m.contains('混合属性')), isTrue);

    // 去掉一种 → 只剩 40 张（张数会报），但没有属性错误了
    d.cards.remove(codes[2]);
    errs = errorsOf(s, d);
    expect(errs.any((m) => m.contains('混合属性')), isFalse);
  });

  test('规则模式跟着存档/备份走', () async {
    final s = await fresh();
    final d = s.createDeck('格式测试');
    s.setDeckFormat(d, DeckFormat.sealed);
    expect(Deck.fromJson(d.toJson()).format, DeckFormat.sealed);

    final data = s.exportData();
    final s2 = await fresh();
    s2.importData(data);
    expect(s2.decks.first.format, DeckFormat.sealed);
    // ignore: avoid_print
    debugPrint('备份恢复后规则模式：${kFormatName[s2.decks.first.format]}');
  });

  testWidgets('统计图能渲染出属性/费用/卡种', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'deckSeeded': true});
      await CardRepository.instance.load();
      state = await AppState.create();
      final d = state.createDeck('统计测试');
      state.addCard(d, CardRepository.instance.byCode('LO-0575')!, 4);
      state.addCard(d, CardRepository.instance.byCode('LO-6281')!, 2);
    });
    final deck = state.decks.first;

    await tester.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(home: Scaffold(body: DeckStats(deck: deck))),
    ));
    await tester.pump();

    expect(find.textContaining('统计（主卡区 6 张）'), findsOneWidget);
    expect(find.text('属性'), findsOneWidget);
    expect(find.text('费用'), findsOneWidget);
    expect(find.text('卡种'), findsOneWidget);

    // 卡种必须显示中文：以前这里直接用日文的 kind 字段，
    // 统计图里会出现「キャラクター」这种没翻译的东西。
    expect(find.text('角色'), findsWidgets, reason: '卡种应当翻译成中文');
    expect(find.text('キャラクター'), findsNothing,
        reason: '不该出现日文卡种');
  });
}
