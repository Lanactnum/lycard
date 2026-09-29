import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/models/lycee_card.dart';
import 'package:lycee_app/state/calc_field.dart';

/// 局内计算器的数值口径测试。
///
/// 这些算术是这一栏的**全部**正确性所在：玩家在局内看着这几个数字做判断，
/// 算错一位都会直接影响打法。所以不靠眼睛看，直接钉在这里。
LyceeCard card(String code, {int? ap, int? dp, int? sp, int? dmg}) => LyceeCard(
      code: code,
      nameJp: 'テスト',
      ap: ap,
      dp: dp,
      sp: sp,
      dmg: dmg,
    );

void main() {
  test('空格子不计入合计', () {
    final side = CalcSide();
    expect(side.occupied, 0);
    expect(side.isEmpty, isTrue);
    expect(sideTotal(side, (_) => null), CalcValues.zero);
  });

  test('当前值 = 卡面基础值 + 全部修正（含负数）', () {
    final slot = CalcSlot(code: 'LO-0001');
    final c = card('LO-0001', ap: 3, dp: 3, sp: 1, dmg: 3);
    expect(currentOf(slot, c), const CalcValues(3, 3, 1, 3));

    slot.mods.add(CalcMod(phase: CalcPhase.thisTurn, ap: 2, dp: -1));
    expect(currentOf(slot, c), const CalcValues(5, 2, 1, 3));

    slot.mods.add(CalcMod(phase: CalcPhase.response, ap: -3, dmg: 1));
    expect(currentOf(slot, c), const CalcValues(2, 2, 1, 4));
  });

  test('修正按时机分开统计，互不串台', () {
    final slot = CalcSlot(code: 'X');
    slot.mods.addAll([
      CalcMod(phase: CalcPhase.lastTurn, ap: 1),
      CalcMod(phase: CalcPhase.lastTurn, dp: 2),
      CalcMod(phase: CalcPhase.thisTurn, ap: 3),
      CalcMod(phase: CalcPhase.response, sp: 4),
      CalcMod(phase: CalcPhase.always, dmg: 5),
    ]);
    expect(modsOfPhase(slot, CalcPhase.lastTurn), const CalcValues(1, 2, 0, 0));
    expect(modsOfPhase(slot, CalcPhase.thisTurn), const CalcValues(3, 0, 0, 0));
    expect(modsOfPhase(slot, CalcPhase.response), const CalcValues(0, 0, 4, 0));
    expect(modsOfPhase(slot, CalcPhase.always), const CalcValues(0, 0, 0, 5));
    expect(modsTotal(slot), const CalcValues(4, 2, 4, 5));
  });

  test('场上合计：6 个格子只算放了牌的', () {
    final side = CalcSide();
    final Map<String, LyceeCard> pool = <String, LyceeCard>{
      'A': card('A', ap: 3, dp: 2, sp: 1, dmg: 3),
      'B': card('B', ap: 1, dp: 5, sp: 0, dmg: 2),
    };
    side.af[0].code = 'A';
    side.df[2].code = 'B';
    side.af[0].mods.add(CalcMod(phase: CalcPhase.thisTurn, ap: 2));

    expect(side.occupied, 2);
    expect(sideTotal(side, (String c) => pool[c]), const CalcValues(6, 7, 1, 5));
  });

  test('侧向的时机合计 = 各格子同一时机之和', () {
    final side = CalcSide();
    side.af[1].code = 'A';
    side.df[0].code = 'B';
    side.af[1].mods.add(CalcMod(phase: CalcPhase.response, ap: 2));
    side.df[0].mods.add(CalcMod(phase: CalcPhase.response, ap: 1, dmg: 1));
    side.df[0].mods.add(CalcMod(phase: CalcPhase.lastTurn, dp: -2));
    expect(sideModsOfPhase(side, CalcPhase.response), const CalcValues(3, 0, 0, 1));
    expect(sideModsOfPhase(side, CalcPhase.lastTurn), const CalcValues(0, -2, 0, 0));
    expect(sideModsOfPhase(side, CalcPhase.thisTurn), CalcValues.zero);
  });

  test('卡面缺数值字段时按 0 算，不会崩', () {
    final slot = CalcSlot(code: 'N');
    final c = card('N'); // ap/dp/sp/dmg 全是 null
    expect(currentOf(slot, c), CalcValues.zero);
    slot.mods.add(CalcMod(phase: CalcPhase.always, ap: 4));
    expect(currentOf(slot, c), const CalcValues(4, 0, 0, 0));
  });

  test('清空：卡和修正一起清掉', () {
    final side = CalcSide();
    side.af[0].code = 'A';
    side.af[0].mods.add(CalcMod(phase: CalcPhase.thisTurn, ap: 9));
    side.clear();
    expect(side.isEmpty, isTrue);
    expect(side.af[0].mods, isEmpty);
  });

  test('场地就是 AF 3 格 + DF 3 格（和规则页口径一致）', () {
    final side = CalcSide();
    expect(side.af.length, 3);
    expect(side.df.length, 3);
    expect(side.all.length, 6);
  });
}
