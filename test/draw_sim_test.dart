import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/draw_sim.dart';

void main() {
  group('起手概率（超几何分布）', () {
    test('60 张卡组 / 4 张目标 / 抽 8 张 ≈ 44.5%', () {
      final p = DrawSim.probAtLeastOne(deckSize: 60, targets: 4, drawCount: 8);
      // 1 - C(56,8)/C(60,8) = 1 - (52*51*50*49)/(60*59*58*57)
      final expect0 = 1 - (52 * 51 * 50 * 49) / (60 * 59 * 58 * 57);
      expect(p, closeTo(expect0, 1e-9));
      expect(p, closeTo(0.4448, 0.001));
    });

    test('抽 9 张（后手）比抽 8 张更高', () {
      final a = DrawSim.probAtLeastOne(deckSize: 60, targets: 4, drawCount: 8);
      final b = DrawSim.probAtLeastOne(deckSize: 60, targets: 4, drawCount: 9);
      expect(b, greaterThan(a));
      // 约分后：C(56,9)/C(60,9) = (51*50*49*48)/(60*59*58*57)
      final expect9 = 1 - (51 * 50 * 49 * 48) / (60 * 59 * 58 * 57);
      expect(b, closeTo(expect9, 1e-9));
      expect(b, closeTo(0.4875, 0.001));
    });

    test('目标越多、概率越高；目标=卡组时必中', () {
      final p1 = DrawSim.probAtLeastOne(deckSize: 60, targets: 1, drawCount: 8);
      final p4 = DrawSim.probAtLeastOne(deckSize: 60, targets: 4, drawCount: 8);
      expect(p4, greaterThan(p1));
      expect(DrawSim.probAtLeastOne(deckSize: 60, targets: 60, drawCount: 8), 1);
      expect(DrawSim.probAtLeastOne(deckSize: 60, targets: 0, drawCount: 8), 0);
    });

    test('允许换一次牌时概率更高', () {
      final a = DrawSim.probAtLeastOne(
          deckSize: 60, targets: 4, drawCount: 8, mulliganAllowed: true);
      final b = DrawSim.probAtLeastOne(deckSize: 60, targets: 4, drawCount: 8);
      expect(a, greaterThan(b));
    });
  });

  group('洗牌 / 抽牌 / 换牌', () {
    final deck = <String, int>{
      'LO-0001': 4,
      'LO-0002': 4,
      'LO-0003': 4,
      'LO-0004': 48,
    };

    test('发牌：总张数正确、手上不超牌库', () {
      final sim = DrawSim(deck, seed: 42);
      expect(sim.deckSize, 60);
      sim.deal(8);
      expect(sim.hand.length, 8);
      expect(sim.remaining, 52);
      expect(sim.mulligans, 0);
      // 手牌张数加起来就是 8
      expect(sim.handCount().values.fold(0, (a, b) => a + b), 8);
    });

    test('换牌：换几张补几张、总张数守恒、次数 +1', () {
      final sim = DrawSim(deck, seed: 7);
      sim.deal(8);
      final before = List<String>.from(sim.hand);
      final changed = sim.mulligan([before.first, before[1]]);
      expect(changed, 2);
      expect(sim.hand.length, 8, reason: '换掉的必须补回来');
      expect(sim.remaining, 52);
      expect(sim.mulligans, 1);
    });

    test('换牌：手上没有的卡不会被算进去', () {
      final sim = DrawSim(deck, seed: 3);
      sim.deal(8);
      expect(sim.mulligan(['不存在的卡号']), 0);
      expect(sim.mulligans, 0);
    });

    test('再摸一张：手牌 +1、牌库 -1，摸干为止', () {
      final sim = DrawSim({'LO-0001': 3}, seed: 1);
      sim.deal(2);
      expect(sim.hand.length, 2);
      expect(sim.drawOne(), isNotNull);
      expect(sim.hand.length, 3);
      expect(sim.drawOne(), isNull);
      expect(sim.hand.length, 3);
    });

    test('同一种子结果可复现', () {
      final a = DrawSim(deck, seed: 99)..deal(8);
      final b = DrawSim(deck, seed: 99)..deal(8);
      expect(a.hand, b.hand);
    });
  });
}
