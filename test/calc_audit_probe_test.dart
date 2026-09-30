import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/lycee_card.dart';
import 'package:lycee_app/state/calc_effect.dart';

/// 计算器解析体检 —— 跑真实卡池，打印统计 + 原文抽查 + **逐条验修**。
///
/// **这是体检脚本，不是断言测试**：只报数，不改东西。改完解析器重跑一遍，
/// 就能看出每个口子修没修干净、代价是什么。
///
/// 定位一律用 [EffectBonus.start]（解析时的真实下标）——
/// 别用 `text.indexOf(b.raw)`：同一段数值在卡面里出现两次时会指到前一处，
/// 量出来的上下文是错的（实测差点把「修好了」当成「没修干净」）。
///
/// 验的四件事：
///  ① `[常時] 味方[花]キャラ全てに…` —— 属性括号顶掉行动标签，误判成「要用才生效」；
///  ② `この[雪]キャラに…` / `この＜魔剣＞キャラに…` —— 自身效果被判成「目标待定」；
///  ③ `ＡＰ＋[变量]`（不带「に」）—— 整条看不到；
///  ④ 充能上限：`[チャージ:N]` 与 `N枚チャージできる` 两种写法。
///
/// ⚠ 写体检正则的坑：属性筛选在原文里是**带括号的**（`この[雪]キャラ`），
/// 写成 `この[日月花雪星宙]キャラ`（漏了 `\[` `\]` 字面量）一条都匹配不到 ——
/// 实测量出 0 条，差点当成「这里没问题」。体检脚本自己错了最难发现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('计算器解析体检（真实卡池）', () async {
    await CardRepository.instance.load();
    final List<LyceeCard> cards = CardRepository.instance.all.toList();
    debugPrint('==== 卡池 ${cards.length} 张 ====');

    final RegExp anyTag = RegExp(r'\[([^\]]{1,12})\]');
    final RegExp actionRe =
        RegExp(r'\[(常時|誘発|宣言|手札宣言|起動|自動|永続)[^\]]{0,6}\]');
    final RegExp selfBracket = RegExp(r'この[\[<][^\]>\n]{1,8}[\]>]キャラに');
    final RegExp varAny =
        RegExp(r'(AP|DP|SP|DMG)[+-]\[(?:[^\[\]\n]|\[[^\[\]\n]*\]){1,60}\]');
    final RegExp chargeVerb = RegExp(r'(\d+)\s*枚チャージできる');
    final RegExp chargeBracket = RegExp(r'チャージ[:：]\s*(\d+)');

    int total = 0, activated = 0, autoApplicable = 0;
    int fixedGain = 0, ctxAlwaysBlocked = 0;
    int staleAlways = 0, staleSelf = 0, varMissed = 0;
    int oneAlly = 0, oneEnemy = 0, unknown = 0;
    int chargeCards = 0, chargeParsed = 0, chargeVerbOnly = 0;
    int bothAllUnknown = 0, bothAllCount = 0;
    final List<String> bothAllSamples = <String>[];
    final Map<String, int> bothAllHeads = <String, int>{};
    int cardsWithBonus = 0;
    final List<String> staleAlwaysSamples = <String>[];
    final List<String> staleSelfSamples = <String>[];
    final List<String> varMissSamples = <String>[];
    final List<String> blockedSamples = <String>[];

    for (final LyceeCard c in cards) {
      final String raw = c.effectJp ?? '';
      final String text = EffectParser.normalize(raw);
      final List<EffectBonus> bs = EffectParser.parse(c);
      if (bs.isNotEmpty) cardsWithBonus++;

      for (final EffectBonus b in bs) {
        total++;
        if (b.activated) activated++;
        if (b.isAutoApplicable) autoApplicable++;
        if (b.target == EffectTarget.bothAll) bothAllCount++;
        if (b.target == EffectTarget.allyOne) oneAlly++;
        if (b.target == EffectTarget.enemyOne) oneEnemy++;
        if (b.target == EffectTarget.unknown) unknown++;

        final String pre = text.substring(0, b.start.clamp(0, text.length));

        // ① 修复前 vs 修复后：修复前的判定 = 「最近的括号不是常時 就算要用才生效」
        final Iterable<RegExpMatch> tags = anyTag.allMatches(pre);
        final String? nearTag = tags.isEmpty ? null : tags.last.group(1);
        final bool oldActivated = nearTag != null && !nearTag.startsWith('常時');
        final bool autoOld = !b.hasVariable && !b.conditional && !oldActivated;
        if (!autoOld && b.isAutoApplicable) fixedGain++;

        final Iterable<RegExpMatch> am = actionRe.allMatches(pre);
        final bool ctxAlways = am.isNotEmpty && am.last.group(1) == '常時';
        if (ctxAlways && !b.isAutoApplicable) {
          ctxAlwaysBlocked++;
          if (blockedSamples.length < 4) {
            blockedSamples.add('${c.code} ← ${b.summary}'
                '  [变量=${b.hasVariable} 条件=${b.conditional}'
                ' 要用才生效=${b.activated}]');
          }
        }
        if (ctxAlways && b.activated) {
          staleAlways++;
          if (staleAlwaysSamples.length < 3) {
            staleAlwaysSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}\n'
                '      ← ${b.summary}');
          }
        }
        // ⑤ 「キャラ全てに」= 双方全体，却落进「目标待定」→ 玩家只能选一格
        final int kAll = pre.lastIndexOf('キャラ全てに');
        if (b.target == EffectTarget.unknown && kAll > 0) {
          final String head = pre.substring(kAll - 8 < 0 ? 0 : kAll - 8, kAll);
          if (!head.contains('味方') && !head.contains('相手')) {
            bothAllUnknown++;
            final String h =
                pre.substring(kAll - 6 < 0 ? 0 : kAll - 6, kAll);
            bothAllHeads[h] = (bothAllHeads[h] ?? 0) + 1;
            if (bothAllSamples.length < 5) {
              bothAllSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}');
            }
          }
        }
        if (selfBracket.hasMatch(pre) && b.target != EffectTarget.self) {
          staleSelf++;
          if (staleSelfSamples.length < 5) {
            staleSelfSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}\n'
                '      ← ${kEffectTargetNames[b.target]}');
          }
        }
      }

      if (varAny.hasMatch(text) && !bs.any((EffectBonus b) => b.hasVariable)) {
        varMissed++;
        if (varMissSamples.length < 5) {
          varMissSamples.add('${c.code}  ${raw.replaceAll('\n', ' ')}');
        }
      }

      if (text.contains('チャージ')) {
        chargeCards++;
        if (EffectParser.chargeMaxOf(c) != null) {
          chargeParsed++;
        } else if (chargeVerb.hasMatch(text) && !chargeBracket.hasMatch(text)) {
          chargeVerbOnly++;
        }
      }
    }

    debugPrint('---- 总量 ----');
    debugPrint('有加成的卡：$cardsWithBonus / ${cards.length}');
    debugPrint('加成条目：$total');
    debugPrint('  可直接自动套用：$autoApplicable');
    debugPrint('  「要用才生效」：$activated');
    debugPrint('  我方 1 体：$oneAlly   对方 1 体：$oneEnemy   目标待定：$unknown');

    debugPrint('---- ① [常時] 被属性括号顶掉 ----');
    debugPrint('这一改**多**套用上的条目：$fixedGain');
    debugPrint('仍判成「要用才生效」的（应为 0）：$staleAlways');
    for (final String s in staleAlwaysSamples) {
      debugPrint('  · $s');
    }
    debugPrint('上下文是 [常時] 但按设计仍不自动的（条件/变量）：$ctxAlwaysBlocked');
    for (final String s in blockedSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ② この[属性]キャラに = 自身（应为 0）----');
    debugPrint('目标还不是「自身」的：$staleSelf');
    for (final String s in staleSelfSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ③ ＡＰ＋[变量] 整条看不到（应为 0）----');
    debugPrint('有变量写法却一条变量条目都没解析出的卡：$varMissed');
    for (final String s in varMissSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ⑤ 「キャラ全てに」= 双方全体 ----');
    debugPrint('解析成「双方全体」的：$bothAllCount 条');
    debugPrint('还留在「目标待定」的：$bothAllUnknown 条'
        '（应当只剩带「除く」的，那些是有意保守）');
    final List<MapEntry<String, int>> heads = bothAllHeads.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    debugPrint('「キャラ全てに」前面 6 个字的分布（看有没有「自分の」这种自我限定）：');
    for (final MapEntry<String, int> e in heads) {
      debugPrint('  「${e.key}」  ${e.value}');
    }
    for (final String s in bothAllSamples) {
      debugPrint('  · $s');
    }

    debugPrint('---- ④ 充能上限 ----');
    final String pct =
        chargeCards == 0 ? '-' : (chargeParsed * 100 / chargeCards).toStringAsFixed(0);
    debugPrint('提到 チャージ：$chargeCards 张；解析出上限：$chargeParsed 张（$pct%）');
    debugPrint('  仍认不出的「N枚チャージ」写法：$chargeVerbOnly 张');

    expect(cards.length, greaterThan(9000));
    expect(total, greaterThan(9000));
  });
}
