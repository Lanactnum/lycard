import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/lycee_card.dart';
import 'package:lycee_app/state/calc_effect.dart';
import 'package:lycee_app/state/calc_field.dart';

/// 效果解析器的正确性测试。
///
/// 这些断言全部对着**真实卡面文本**写 —— 自动算数值这件事，认错一条
/// 比漏掉十条更糟：玩家会照着错的数打牌。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LyceeCard card(String code, String effect) =>
      LyceeCard(code: code, nameJp: 'テスト', effectJp: effect);

  group('全角归一化', () {
    test('全角字母数字符号都要转半角', () {
      expect(EffectParser.normalize('ＡＰ＋２'), 'AP+2');
      expect(EffectParser.normalize('ＤＭＧ－１'), 'DMG-1');
      expect(EffectParser.normalize('１体'), '1体');
      expect(EffectParser.normalize('あ　い'), 'あ い');
    });
  });

  group('基本数值解析', () {
    test('「このキャラにＡＰ＋１」→ 自身 AP+1', () {
      final c = card('T1', '[誘発] このキャラにＡＰ＋１する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.length, 1);
      expect(b.first.target, EffectTarget.self);
      expect(b.first.values, const CalcValues(1, 0, 0, 0));
    });

    test('「{相手キャラ1体}にＳＰ－２」→ 对方 1 体 SP-2', () {
      final c = card('T2', '[誘発] このキャラで攻撃宣言をしたとき、相手キャラ１体にＳＰ－２する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.length, 1);
      expect(b.first.target, EffectTarget.enemyOne);
      expect(b.first.values, const CalcValues(0, 0, -2, 0));
    });

    test('「味方ＤＦキャラ全てにＤＰ＋１」→ 我方 DF 全体 DP+1', () {
      final c = card('T3', '[宣言] [0]:味方ＤＦキャラ全てにＤＰ＋１する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.length, 1);
      expect(b.first.target, EffectTarget.allyDfAll);
      expect(b.first.values, const CalcValues(0, 1, 0, 0));
    });

    test('连写多项要归成一条：ＡＰ＋１・ＤＰ＋１', () {
      final c = card('T4', '[常時] このキャラにＡＰ＋１・ＤＰ＋１する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.length, 1, reason: '・连起来的应当算一条，不该拆成两条');
      expect(b.first.values, const CalcValues(1, 1, 0, 0));
    });

    test('一条效果里的多句要分别解析', () {
      final c = card('T5',
          '[宣言] [0]:{相手キャラ1体}にＡＰ－１する。 [誘発] このキャラにＤＰ＋２する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.length, 2);
      expect(b[0].target, EffectTarget.enemyOne);
      expect(b[1].target, EffectTarget.self);
    });
  });

  group('条件与变量要标出来（不能盲自动套用）', () {
    test('含「場合」的条件要标 conditional', () {
      final c = card('T6',
          '[宣言] [0]:コストが3点以上の味方キャラ1体が登場している場合、このキャラにＡＰ＋１する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.any((EffectBonus x) => x.conditional), isTrue);
      expect(b.firstWhere((EffectBonus x) => x.conditional).isAutoApplicable,
          isFalse);
    });

    test('含 [变量] 的数值要标 hasVariable 且数值为 0', () {
      final c = card('T7',
          '[宣言] [0]:このキャラのＡＰとＤＰに+[コストが2点以下の味方[宙]キャラの数]する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      final EffectBonus v = b.firstWhere((EffectBonus x) => x.hasVariable);
      expect(v.values, CalcValues.zero, reason: '变量算不出来，必须是 0 让玩家填');
      expect(v.variableNote.isNotEmpty, isTrue);
      expect(v.isAutoApplicable, isFalse);
    });
  });

  group('时机判定', () {
    test('常時 → always', () {
      final c = card('T8', '[常時] このキャラにＡＰ＋１する。');
      expect(EffectParser.parse(c).first.phase, CalcPhase.always);
    });

    test('宣言 → thisTurn', () {
      final c = card('T9', '[宣言] [0]:このキャラにＡＰ＋１する。');
      expect(EffectParser.parse(c).first.phase, CalcPhase.thisTurn);
    });
  });

  group('充能上限', () {
    test('卡面 [チャージ:1] → 上限 1', () {
      expect(EffectParser.chargeMaxOf(card('C1', '[チャージ:１] [ジャンプ:[0]]')), 1);
    });
    test('卡面 [チャージ:２] → 上限 2', () {
      expect(EffectParser.chargeMaxOf(card('C2', '[チャージ:２] なにか')), 2);
    });
    test('没有チャージ → null', () {
      expect(EffectParser.chargeMaxOf(card('C3', '[宣言] なにか')), isNull);
    });
  });

  group('「要用才生效」的效果不许自动算', () {
    test('[宣言] + 代价括号 → activated', () {
      final c = card('T10', '[宣言] [自分の手札を全て破棄する。]:このキャラにＡＰ＋３する。');
      final List<EffectBonus> b = EffectParser.parse(c);
      expect(b.first.activated, isTrue);
      expect(b.first.isAutoApplicable, isFalse);
    });

    test('[誘発] 触发类 → activated', () {
      final c = card('T11', '[誘発] このキャラにＡＰ＋１する。');
      expect(EffectParser.parse(c).first.isAutoApplicable, isFalse);
    });

    test('[常時] → 可以自动算', () {
      final c = card('T12', '[常時] このキャラにＤＰ＋１する。');
      expect(EffectParser.parse(c).first.isAutoApplicable, isTrue);
    });

    test('没有标签的（事件/道具）→ 可以自动算', () {
      final c = card('T13', '味方ＡＦキャラ全てにＡＰ＋１する。');
      expect(EffectParser.parse(c).first.isAutoApplicable, isTrue);
    });
  });

  group('置き場名字建议', () {
    test('从卡面取「〜置き場」的名字', () {
      final c = card('T14', '[常時] 「迷宮」置き場にカードを置く。「経験値」置き場にも置く。');
      expect(EffectParser.storageNamesOf(c), <String>['迷宮', '経験値']);
    });

    test('卡面没写置き場 → 空（让玩家自己命名）', () {
      expect(EffectParser.storageNamesOf(card('T15', 'このキャラにＡＰ＋１する。')),
          isEmpty);
    });
  });

  group('自动算值（上卡即算 / 全场扩散 / 玩家意见优先）', () {
    LyceeCard c(String code, String effect) =>
        LyceeCard(code: code, nameJp: 'テスト', effectJp: effect);

    test('常時自身加成会自动落到格子上', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'T20';
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'T20': c('T20', '[常時] このキャラにＤＰ＋１する。'),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(mine.af[0].autoMods.length, 1);
      expect(mine.af[0].autoMods.first.dp, 1);
    });

    test('后上场的卡也能吃到先前的全场效果', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'T21';
      mine.af[1].code = 'T22';
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'T21': c('T21', '[常時] 味方キャラ全てにＡＰ＋１する。'),
        'T22': c('T22', ''),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(mine.af[0].autoMods.first.ap, 1);
      expect(mine.af[1].autoMods.first.ap, 1, reason: '后上的卡也要吃到');
    });

    test('拿掉来源卡后，重算会把它的效果从别人身上收回', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'T21';
      mine.af[1].code = 'T22';
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'T21': c('T21', '[常時] 味方キャラ全てにＡＰ＋１する。'),
        'T22': c('T22', ''),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      mine.af[0].clear();
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(mine.af[1].autoMods, isEmpty);
    });

    test('玩家删掉的自动条目不会被重算补回来', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'T20';
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'T20': c('T20', '[常時] このキャラにＤＰ＋１する。'),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      final String key = mine.af[0].autoMods.first.key;
      mine.af[0].autoSuppressed.add(key);
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(mine.af[0].autoMods, isEmpty, reason: '重算不能盖掉玩家的删除');
    });

    test('带条件的全场效果不自动算', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'T23';
      mine.af[1].code = 'T24';
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'T23': c('T23', '[常時] 味方キャラ全てにＡＰ＋１する。'),
        'T24': c('T24', '[常時] 場合によって味方キャラ全てにＤＰ＋２する。'),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(mine.af[1].autoMods.length, 1, reason: '只吃 T23 那条，T24 的带条件不算');
      expect(mine.af[1].autoMods.first.ap, 1);
    });
  });

  group('对真实卡面跑全量，不许崩也不许乱认', () {
    test('9952 张卡全解析一遍', () async {
      await CardRepository.instance.load();
      final List<LyceeCard> all = CardRepository.instance.all;

      int parsedCards = 0;
      int bonusTotal = 0;
      int autoApplicable = 0;
      int withVariable = 0;
      int conditional = 0;
      int unknownTarget = 0;
      final List<String> badValue = <String>[];

      for (final LyceeCard c in all) {
        final List<EffectBonus> bs = EffectParser.parse(c);
        if (bs.isNotEmpty) parsedCards++;
        for (final EffectBonus b in bs) {
          bonusTotal++;
          if (b.isAutoApplicable) autoApplicable++;
          if (b.hasVariable) withVariable++;
          if (b.conditional) conditional++;
          if (b.target == EffectTarget.unknown) unknownTarget++;
          // 数值绝对值不该超过 30（卡牌游戏里没有这么离谱的单项加成）
          for (final int v in <int>[
            b.values.ap,
            b.values.dp,
            b.values.sp,
            b.values.dmg,
          ]) {
            if (v.abs() > 30) badValue.add('${c.code}: ${b.raw}');
          }
        }
      }

      // ignore: avoid_print
      debugPrint('===== 效果解析全量体检 =====');
      // ignore: avoid_print
      debugPrint('解析出加成的卡数     : $parsedCards / ${all.length}');
      // ignore: avoid_print
      debugPrint('加成条目总数         : $bonusTotal');
      // ignore: avoid_print
      debugPrint('  可直接自动套用     : $autoApplicable');
      // ignore: avoid_print
      debugPrint('  含变量（要手填）   : $withVariable');
      // ignore: avoid_print
      debugPrint('  含条件（要确认）   : $conditional');
      // ignore: avoid_print
      debugPrint('  目标解析不出       : $unknownTarget');
      // ignore: avoid_print
      debugPrint('数值离谱的条目       : ${badValue.length}');
      for (final String s in badValue.take(5)) {
        // ignore: avoid_print
        debugPrint('   $s');
      }

      expect(parsedCards, greaterThan(1000), reason: '至少要能认出一部分卡');
      expect(badValue, isEmpty, reason: '不许解析出离谱数值');
    });
  });

  group('解析口径（都对着真实卡面写）', () {
    test('[常時] 写在属性括号前面 → 仍然是常駐，能自动算', () {
      // 「[常時] 味方[花]キャラ全てに…」里数值串前最近的括号是属性筛选，
      // 不是行动标签 —— 拿它当标签会把常駐效果误判成「要用才生效」。
      final c = card('P1', '[常時] 味方[花]キャラ全てにＳＰ＋１する。');
      final EffectBonus b = EffectParser.parse(c).first;
      expect(b.phase, CalcPhase.always);
      expect(b.activated, isFalse, reason: '[常時] 就是常駐，不该算「要用才生效」');
      expect(b.isAutoApplicable, isTrue);
      expect(b.target, EffectTarget.allyAll);
    });

    test('[常時] + 条件句 → 仍不自动（宁可不猜）', () {
      final c = card('P2', '[常時] このキャラのチャージが１枚以上の場合、このキャラにＡＰ＋２する。');
      final EffectBonus b = EffectParser.parse(c).first;
      expect(b.activated, isFalse);
      expect(b.conditional, isTrue);
      expect(b.isAutoApplicable, isFalse, reason: '有条件就得玩家确认');
    });

    test('[宣言] + 代价括号 → 还是要用才生效（保守没被改松）', () {
      final c = card('P3', '[宣言] [花]:このキャラにＡＰ＋１する。');
      final EffectBonus b = EffectParser.parse(c).first;
      expect(b.activated, isTrue);
      expect(b.isAutoApplicable, isFalse);
    });

    test('この[属性]キャラに → 自身', () {
      final EffectBonus b =
          EffectParser.parse(card('P4', '[常時] この[雪]キャラにＡＰ－１する。')).first;
      expect(b.target, EffectTarget.self);
      expect(b.values, const CalcValues(-1, 0, 0, 0));
    });

    test('この＜タイプ＞キャラに → 自身', () {
      final EffectBonus b =
          EffectParser.parse(card('P5', '[常時] この＜魔剣＞キャラにＡＰ＋１する。')).first;
      expect(b.target, EffectTarget.self);
    });

    test('ＡＰ＋[变量]（没写「に」）也要解析出来', () {
      final c = card('P6', '[誘発] このキャラにＤＭＧ＋[破棄したカードのＥＸ]する。');
      final List<EffectBonus> bs = EffectParser.parse(c);
      final EffectBonus v = bs.firstWhere((EffectBonus x) => x.hasVariable);
      expect(v.variableNote, contains('破棄したカードのEX'));
      expect(v.values, CalcValues.zero, reason: '变量算不出来，数值必须是 0');
      expect(v.isAutoApplicable, isFalse);
    });

    test('变量里套着括号（味方[宙]キャラの数）也要读全', () {
      final c = card('P7', '[宣言] [0]:このキャラにＡＰ＋[味方[宙]キャラの数]する。');
      final EffectBonus v = EffectParser
          .parse(c)
          .firstWhere((EffectBonus x) => x.hasVariable);
      expect(v.variableNote, '味方[宙]キャラの数');
    });

    test('充能上限：「N枚チャージできる」也认', () {
      expect(EffectParser.chargeMaxOf(card('C4', 'このキャラに1枚チャージできる。')), 1);
      expect(EffectParser.chargeMaxOf(card('C5', 'このキャラに２枚チャージできる。')), 2);
    });

    test('充能上限：往卡下塞一张的「チャージとして置く」不算上限', () {
      expect(
        EffectParser.chargeMaxOf(
            card('C6', '自分のゴミ箱のカード1枚をこのキャラにチャージとして置く。')),
        isNull,
      );
    });

    test('充能上限：括号和「N枚」同时写着时，以括号为准', () {
      expect(
        EffectParser.chargeMaxOf(
            card('C7', '[チャージ:２] このキャラに5枚チャージできる。')),
        2,
      );
    });

    test('自动算值：吃了属性筛选的全场效果会落到别人身上', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'P8';
      mine.af[1].code = 'P9';
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'P8': card('P8', '[常時] 味方[花]キャラ全てにＳＰ＋１する。'),
        'P9': card('P9', ''),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(mine.af[0].autoMods.first.sp, 1);
      expect(mine.af[1].autoMods.first.sp, 1, reason: '后上的卡也要吃到');
    });

    test('自动条目记着自己是从哪一格来的（同编号两张也分得清）', () {
      final CalcSide mine = CalcSide();
      final CalcSide theirs = CalcSide();
      mine.af[0].code = 'P10';
      mine.af[1].code = 'P10'; // 同编号第二张
      final Map<String, LyceeCard> cards = <String, LyceeCard>{
        'P10': card('P10', '[常時] このキャラにＤＰ＋１する。'),
      };
      recomputeAuto(mine, theirs, (String k) => cards[k]);
      expect(identical(mine.af[0].autoMods.first.sourceSlot, mine.af[0]), isTrue);
      expect(identical(mine.af[1].autoMods.first.sourceSlot, mine.af[1]), isTrue);
    });
  });
}
