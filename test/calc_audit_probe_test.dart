import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/lycee_card.dart';
import 'package:lycee_app/state/calc_effect.dart';

/// 计算器解析体检 —— 跑真实卡池（9952 张），打印统计 + 原文抽查。
///
/// **这是体检脚本，不是断言测试**：它只把数报出来，不改任何东西，
/// 用来回答「计算器的自动算值到底漏在哪」。修完解析器重跑一遍就能看涨跌。
///
/// 量的四件事：
///  ① `[常時] 味方[花]キャラ全てに…` —— 属性括号把 [常時] 顶掉，
///     本该自动算的退化成「要用才生效」；
///  ② `この[属性]キャラに…` —— 自身效果被漏判成「目标待定」；
///  ③ `ＡＰ＋[变量]`（不带「に」）—— 整条看不到（面板里什么都不显示）；
///  ④ 充能上限：只有 `[チャージ:N]` 能认，`N枚チャージできる` 认不出。
///
/// ⚠ 写体检正则时注意：属性过滤器在原文里是**带括号的**（`この[雪]キャラ`、
/// `この＜魔剣＞キャラ`），`この[日月花雪星宙]キャラ` 这种漏掉 `\[` `\]`
/// 字面量的写法会一条都匹配不到 —— 实测踩过，量出 0 条差点当成「没问题」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('计算器体检 v4', () async {
    await CardRepository.instance.load();
    final List<LyceeCard> cards = CardRepository.instance.all.toList();
    debugPrint('==== 卡池 ${cards.length} 张 ====');

    // 自身：この[属性]キャラに / この＜タイプ＞キャラに
    final RegExp selfBracket = RegExp(r'この[\[<][^\]>]{1,8}[\]>]キャラに');
    final RegExp actionRe =
        RegExp(r'\[(常時|誘発|宣言|手札宣言|起動|自動|永続)[^\]]{0,6}\]');
    final RegExp varPlus = RegExp(r'(AP|DP|SP|DMG)\+\[([^\]]+)\]');
    final RegExp chargeVerb = RegExp(r'(\d+)\s*枚チャージ');
    final RegExp chargeBracket = RegExp(r'チャージ[:：]\s*(\d+)');

    int total = 0, autoNow = 0;
    int alwaysTagged = 0, alwaysButActivated = 0;
    int selfBracketOccur = 0, selfBracketCards = 0, selfBracketMissed = 0;
    int varMiss = 0, varMissCards = 0;
    int oneAlly = 0, oneEnemy = 0, unknown = 0;
    int chargeCards = 0, parsedNow = 0, parsedIfFixed = 0;
    final List<String> selfMissSamples = <String>[];
    final List<String> alwaysSamples = <String>[];
    final List<String> varSamples = <String>[];
    final Set<String> varCards = <String>{};

    for (final LyceeCard c in cards) {
      final String raw = c.effectJp ?? '';
      final String text = EffectParser.normalize(raw);
      final List<EffectBonus> bs = EffectParser.parse(c);

      // 卡级：自身括号出现次数
      final int occ = selfBracket.allMatches(text).length;
      if (occ > 0) {
        selfBracketCards++;
        selfBracketOccur += occ;
      }

      for (final EffectBonus b in bs) {
        total++;
        if (b.target == EffectTarget.allyOne) oneAlly++;
        if (b.target == EffectTarget.enemyOne) oneEnemy++;
        if (b.target == EffectTarget.unknown) unknown++;
        final bool resolvable = b.target != EffectTarget.allyOne &&
            b.target != EffectTarget.enemyOne &&
            b.target != EffectTarget.unknown;
        if (b.isAutoApplicable && resolvable) autoNow++;

        final int idx = text.indexOf(b.raw);
        if (idx <= 0) continue;
        final String pre = text.substring(0, idx);
        if (selfBracket.hasMatch(pre)) {
          selfBracketMissed++;
          if (selfMissSamples.length < 5) {
            selfMissSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}\n'
                '      ← 判成：${b.summary}');
          }
        }
        final Iterable<RegExpMatch> am =
            actionRe.allMatches(text.substring(0, idx));
        if (am.isNotEmpty && am.last.group(1) == '常時') {
          alwaysTagged++;
          if (b.activated) {
            alwaysButActivated++;
            if (alwaysSamples.length < 4) {
              alwaysSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}\n'
                  '      ← 判成：${b.summary}');
            }
          }
        }
      }

      final int vHit = varPlus.allMatches(text).length;
      if (vHit > 0) {
        varMiss += vHit;
        varCards.add(c.code);
        if (varSamples.length < 4) {
          varSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}');
        }
      }

      if (text.contains('チャージ')) {
        chargeCards++;
        final bool now = EffectParser.chargeMaxOf(c) != null;
        final bool verb = chargeVerb.hasMatch(text);
        final bool bracket = chargeBracket.hasMatch(text);
        if (now) parsedNow++;
        if (now || verb || bracket) parsedIfFixed++;
      }
    }
    varMissCards = varCards.length;

    debugPrint('---- 总量 ----');
    debugPrint('条目 $total，现在真正会自动算的：$autoNow');

    debugPrint('---- ① [常時] 被属性括号顶掉（明确误伤）----');
    debugPrint('本句最近行动标签=[常時]：$alwaysTagged 条，判成 activated：$alwaysButActivated');
    for (final String s in alwaysSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ② 「この[属性]キャラに」= 自身，漏判 ----');
    debugPrint('原文里出现：$selfBracketOccur 处 / $selfBracketCards 张卡');
    debugPrint('  其中解析成「非自身」的：$selfBracketMissed 条   ← 本该是「自身」');
    for (final String s in selfMissSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ③ ＡＰ＋[变量]（不带「に」）完全看不到 ----');
    debugPrint('$varMiss 处 / $varMissCards 张卡');
    for (final String s in varSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ④ 需要玩家手点 ----');
    debugPrint('我方 1 体：$oneAlly   对方 1 体（含对戦キャラ）：$oneEnemy   目标待定：$unknown');

    debugPrint('---- ⑤ 充能上限 ----');
    debugPrint('提到 チャージ：$chargeCards 张');
    debugPrint('  现在能解析出上限：$parsedNow');
    debugPrint('  补上「N枚チャージ」写法后能解析出：$parsedIfFixed');

    expect(cards.length, greaterThan(9000));
    expect(total, greaterThan(9000));
  });
}
