import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/pages/calc_page.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:lycee_app/state/calc_effect.dart';
import 'package:lycee_app/state/calc_field.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 底栏「计算器」栏的交互验证。
///
/// 单元测试只证明算术对；这里要证明**真的能放牌、真的能加修正、
/// 数值真的会实时变** —— 否则「算得对」只是纸上对。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpCalc(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: CalcPage()),
      ),
    );
    await tester.pump();
  }

  /// 放一张卡到第一个空格
  Future<void> placeCard(WidgetTester tester, String query) async {
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, query);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .descendant(
            of: find.byType(GridView),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('双方各 6 个空格，开局没有任何修正', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);

    expect(find.text('我方场地'), findsOneWidget);
    expect(find.text('对方场地'), findsOneWidget);
    // AF 3 + DF 3，双方共 12 个空格。
    // ⚠ 不能用 find.byIcon(Icons.add) 数空格之外的东西 —— 格子里的「+」
    // 就是最稳的定位（储存区的「新建 +」现在只出现在卡的面板里）。
    expect(find.byKey(const ValueKey<String>('calc_slot_')), findsNothing);
    expect(find.textContaining('还没有修正'), findsWidgets);
  });

  testWidgets('放牌 → 加修正 → 格子上的数值实时变化', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    await placeCard(tester, 'LO-0001');

    // 场上出现这张卡的基础值（LO-0001 = AP3 DP3 SP1 DMG3）
    expect(find.text('AP3 DP3 SP1 DMG3'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('calc_slot_LO-0001')),
        findsOneWidget);

    // 点这张卡 → 面板里加一条「此回合 AP+2」
    await tester.tap(find.byKey(const ValueKey<String>('calc_slot_LO-0001')));
    await tester.pumpAndSettle();
    expect(find.text('加一条修正'), findsOneWidget);

    // TextField 顺序：0 说明、1 AP、2 DP、3 SP、4 DMG
    await tester.enterText(find.byType(TextField).at(1), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '加'));
    await tester.pumpAndSettle();

    // 关掉面板 → 格子上应当变成 AP5（3+2），其余不变
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('AP5 DP3 SP1 DMG3'), findsOneWidget);
    expect(find.text('AP3 DP3 SP1 DMG3'), findsNothing, reason: '基础值已被覆盖显示');
    // 顶部合计也要跟着动
    expect(find.textContaining('AP+2'), findsWidgets);
  });

  testWidgets('充能张数可以加减，并显示在格子上', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    await placeCard(tester, 'LO-0001');
    await tester.tap(find.byKey(const ValueKey<String>('calc_slot_LO-0001')));
    await tester.pumpAndSettle();

    // 充能区在面板里
    expect(find.text('充能'), findsOneWidget);
    // 加两张充能
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline).first);
    await tester.pumpAndSettle();
    // 关面板 → 格子上出现「充能2」
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.textContaining('充能2'), findsOneWidget);
  });

  testWidgets('储存区挂在每一张场上卡下面，并显示张数', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    // 储存区不在页面上平铺 —— 它属于某一张卡
    expect(find.text('储存区'), findsNothing, reason: '储存区不再并成一块放在场地下面');

    await placeCard(tester, 'LO-0001');
    await tester.tap(find.byKey(const ValueKey<String>('calc_slot_LO-0001')));
    await tester.pumpAndSettle();

    // 在这张卡的面板里新建
    await tester.tap(find.widgetWithText(TextButton, '新建'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('zone_name_field')),
      '迷宮',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '建'));
    await tester.pumpAndSettle();

    // 张数加减
    await tester.tap(find.byTooltip('储存加一'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('储存加一'));
    await tester.pumpAndSettle();

    // 关面板 → 这张卡的格子上显示「迷宮 2」
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.textContaining('迷宮 2'), findsOneWidget);
  });

  testWidgets('上卡即自动算：[常時] 的自身效果不用点就直接算上', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    // LO-0100「宝具解放」：[常時] このキャラにＤＰ＋１・ＳＰ＋１する。
    // 卡本身没有 AP/DP 基础值 → 自动算上后应当是 AP0 DP1 SP1 DMG0
    await placeCard(tester, 'LO-0100');
    expect(find.text('AP0 DP1 SP1 DMG0'), findsOneWidget,
        reason: '放上卡就该自动算，不需要手动点「套用」');
  });

  testWidgets('全场效果会扩散到后上场的卡，拿掉又收回', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    await placeCard(tester, 'LO-0001'); // AP3 DP3 SP1 DMG3
    expect(find.text('AP3 DP3 SP1 DMG3'), findsOneWidget);

    // LO-0560「女神の加護」：[常時] 味方キャラ全てにAP+1・DP+1する。
    await placeCard(tester, 'LO-0560');
    expect(find.text('AP4 DP4 SP1 DMG3'), findsOneWidget,
        reason: '先上场的卡也要被全场效果补上（所以要整体重算）');

    // 拿掉「女神の加護」→ 加成收回去
    await tester.tap(find.byKey(const ValueKey<String>('calc_slot_LO-0560')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '拿掉这张卡'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('AP4 DP4 SP1 DMG3'), findsNothing);
    expect(find.text('AP3 DP3 SP1 DMG3'), findsOneWidget);
  });

  testWidgets('拿掉卡后回到空格', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    await placeCard(tester, 'LO-0001');
    expect(find.byKey(const ValueKey<String>('calc_slot_LO-0001')),
        findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('calc_slot_LO-0001')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '拿掉这张卡'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('calc_slot_LO-0001')),
        findsNothing, reason: '拿掉后卡就不在场上了');
  });

  testWidgets('效果面板：套用「このキャラにＡＰ＋３・ＤＰ＋３」把数值算上去', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await CardRepository.instance.load();
      state = await AppState.create();
    });

    await pumpCalc(tester, state);
    // LO-0009：「[宣言] [自分の手札を全て破棄する]:このキャラにＡＰ＋３・ＤＰ＋３する。」
    // 是**要用才生效**的（宣言 + 代价），所以不许自动算，得玩家自己点。
    // 基础 AP3 DP2 SP1 DMG3 → 套用后 AP6 DP5 SP1 DMG3
    await placeCard(tester, 'LO-0009');
    expect(find.text('AP3 DP2 SP1 DMG3'), findsOneWidget,
        reason: '要用才生效的效果不能偷偷替你算上');

    await tester.tap(find.byKey(const ValueKey<String>('calc_slot_LO-0009')));
    await tester.pumpAndSettle();

    expect(find.text('这张卡的数值效果'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '套用').first);
    await tester.pumpAndSettle();

    // 关面板看结果
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text('AP6 DP5 SP1 DMG3'), findsOneWidget);
  });

  group('底栏顺序迁移', () {
    test('旧「构筑(1)」要变成新「构筑(2)」，不能变成计算器', () {
      expect(AppState.migrateStartTab(1), 2);
      expect(AppState.migrateStartTab(2), 3);
      expect(AppState.migrateStartTab(0), 0);
    });
  });

  group('充能与效果套用的落点', () {
    test('充能张数可以直接记', () {
      final slot = CalcSlot(code: 'X');
      slot.charge = 3;
      expect(slot.charge, 3);
      slot.clear();
      expect(slot.charge, 0, reason: '清空要连充能一起清');
    });

    test('resolveTargets：全体目标会命中那一方所有非空格', () {
      final src = CalcSlot(code: 'S');
      final a1 = CalcSlot(code: 'A1');
      final a2 = CalcSlot(code: 'A2');
      final e1 = CalcSlot(code: 'E1');
      final empty = CalcSlot();
      final targets = EffectParser.resolveTargets(
        EffectTarget.enemyAll,
        source: src,
        allyAf: <CalcSlot>[a1, empty, a2],
        allyDf: <CalcSlot>[CalcSlot()],
        enemyAf: <CalcSlot>[e1],
        enemyDf: <CalcSlot>[empty],
      );
      expect(targets.length, 1, reason: '只命中对方场上的 E1');
      expect(targets.first.code, 'E1');
    });

    test('resolveTargets：自身目标只命中来源那一格', () {
      final src = CalcSlot(code: 'S');
      final targets = EffectParser.resolveTargets(
        EffectTarget.self,
        source: src,
        allyAf: <CalcSlot>[CalcSlot(code: 'A')],
        allyDf: <CalcSlot>[CalcSlot()],
        enemyAf: <CalcSlot>[CalcSlot()],
        enemyDf: <CalcSlot>[CalcSlot()],
      );
      expect(targets.single.code, 'S');
    });

    test('resolveTargets：单体目标要玩家点，返回空', () {
      final targets = EffectParser.resolveTargets(
        EffectTarget.enemyOne,
        source: CalcSlot(code: 'S'),
        allyAf: <CalcSlot>[CalcSlot(code: 'A')],
        allyDf: <CalcSlot>[CalcSlot()],
        enemyAf: <CalcSlot>[CalcSlot(code: 'E')],
        enemyDf: <CalcSlot>[CalcSlot()],
      );
      expect(targets, isEmpty, reason: '单体目标不能替玩家猜');
    });

    test('applyBonus 把效果落到格子上，并带上来源与原文', () {
      final slot = CalcSlot(code: 'X');
      const bonus = EffectBonus(
        sourceCode: 'X',
        raw: 'AP+3・DP+3',
        values: CalcValues(3, 3, 0, 0),
        target: EffectTarget.self,
        phase: CalcPhase.thisTurn,
      );
      EffectParser.applyBonus(slot, bonus, '测试卡');
      expect(slot.mods.length, 1);
      expect(slot.mods.first.source, CalcModSource.auto);
      expect(slot.mods.first.effectRaw, 'AP+3・DP+3');
      expect(currentOf(slot, null), const CalcValues(3, 3, 0, 0));
    });
  });
}