import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/keyword_db.dart';

/// 术语一致性回归。
///
/// 口径演进：
///  1. 教程正文最初从官方日文规则页自译，把「行动済み」「ダウン」直接照抄了
///     日文 → 修成「已行动」「被击倒」。
///  2. 之后对照中文社区三个来源（魔都群规则 PDF / 萌卡社 Flagalac
///     《基本能力及字段说明》/《LO 规则妙妙小解》），按用户决定**采用萌卡社
///     的用词**统一。
///
/// 对照表：`D:\Big Fat Fish\笔记\lycee术语对照\术语对照表.md`
/// 执行脚本：`tools/align_terms.py`（幂等）
///
/// ⚠ 这个文件里的黑名单只能拿去查**能力名所在的语境**：
///   - 卡数据里 `主角` 出现在卡名「谜之女主角X」里，`恢复` 出现在普通用语
///     「恢复为未行动」里，`跳跃` 出现在卡名「时间跳跃」里 —— 都不能动。
///     所以卡数据只查**方括号形态** `[主角`。
///   - `keywords.json` 的 `jp` 字段本来就该是日文，不能整份查假名。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 萌卡社口径：旧译法 → 新译法
  const renamed = {
    '激进': '进取心',
    '步进': '移动',
    '侧步': '横移',
    '指令步': '竖移',
    '指令切换': '列交换',
    '跳跃': '跳',
    '辅助': '援助',
    '交战': '迎战',
    '恢复': '重振',
    '毅力': '再起',
    '主角': '主演',
    '回合恢复': '回合补正',
  };

  final kana = RegExp(r'[\u3040-\u309f\u30a0-\u30ff]');

  test('教程正文：没有旧术语，也没有日语残留', () async {
    final s = await rootBundle.loadString('assets/data/tutorial.json');
    final problems = <String>[];
    for (final bad in renamed.keys) {
      if (s.contains(bad)) {
        problems.add('教程里还有「$bad」（应作「${renamed[bad]}」）');
      }
    }
    if (s.contains('杀手锏')) problems.add('教程里还有「杀手锏」（用户要求用「切札」）');
    for (final m in kana.allMatches(s)) {
      problems.add('教程里有日文假名：…${s.substring(
        (m.start - 12).clamp(0, s.length),
        (m.end + 12).clamp(0, s.length),
      )}…');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('词条表：中文侧没有旧术语', () async {
    final raw = jsonDecode(await rootBundle.loadString('assets/data/keywords.json'));
    final problems = <String>[];
    for (final e in (raw as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final jp = '${m['jp'] ?? ''}';
      // 中文侧 = zh / cond / desc（jp 字段不查，它本来就该是日文）
      final zhSide = [
        '${m['zh'] ?? ''}',
        '${m['cond'] ?? ''}',
        '${m['desc'] ?? ''}',
      ].join(' ');
      for (final bad in renamed.keys) {
        if (zhSide.contains(bad)) {
          problems.add('词条「$jp」的中文侧还有「$bad」（应作「${renamed[bad]}」）');
        }
      }
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('卡数据：旧的能力标记已清空，新标记都在', () async {
    final s = await rootBundle.loadString('assets/data/translations_zh.json');

    // 方括号形态的旧标记必须为 0
    for (final bad in renamed.keys) {
      expect(s.contains('[$bad'), isFalse,
          reason: '卡数据里还有旧标记「[$bad」（应作「[${renamed[bad]}」）');
    }

    // 新标记必须在
    for (final good in [
      '[进取心', '[移动', '[横移', '[竖移', '[列交换', '[跳', '[援助',
      '[迎战', '[重振', '[再起', '[主演', '[回合补正',
      '[切札', '[充能', '[支援者', '[奖励', '[领导者', '[惩罚', '[突袭',
    ]) {
      expect(s.contains(good), isTrue, reason: '卡数据里缺标记「$good」');
    }
  });

  test('卡数据：卡名与普通用语没被误伤', () async {
    final s = await rootBundle.loadString('assets/data/translations_zh.json');
    // 卡名里含旧术语字样的，必须原样保留
    expect(s.contains('谜之女主角X'), isTrue,
        reason: '「谜之女主角X」是卡名，不该被改成「谜之女主演X」');
    expect(s.contains('时间跳跃'), isTrue,
        reason: '「时间跳跃」是卡名，不该被改成「时间跳」');
    // 普通用语「恢复」不是能力名，必须保留
    expect(s.contains('恢复为未行动'), isTrue,
        reason: '「恢复为未行动」是普通用语，不该被改成「重振为未行动」');
    // 用户指定保留原词
    expect(s.contains('[切札'), isTrue, reason: '「切札」按用户要求保留原词');
  });

  test('搜索索引已按新术语重建', () async {
    final gz = await rootBundle.load('assets/data/search_keys.json.gz');
    expect(gz.lengthInBytes, greaterThan(100000));
  });

  test('卡数据：效果里的 無 已统一成 无，卡名里的日文人名保留', () async {
    // 实测：效果文本里 496 处写成日文「無」（费用/属性标记），而同一批
    // 数据里另有 1080 处写作「无」，19 张卡里两种写法同时出现 ——
    // 用户看到的就是「同一张卡里不一致」。
    final s = await rootBundle.loadString('assets/data/translations_zh.json');
    final doc = jsonDecode(s) as Map<String, dynamic>;
    final bad = <String>[];
    for (final e in doc.entries) {
      final v = e.value;
      if (v is Map && '${v['effect']}'.contains('無')) bad.add(e.key);
    }
    expect(bad, isEmpty,
        reason: '这些卡的效果里还有日文「無」：${bad.take(5).join('、')}');

    // 卡名里的「水無月」是日本姓氏，必须原样保留
    expect(s.contains('水無月'), isTrue,
        reason: '卡名「水無月」是日本人名，不该被改成「水无月」');
  });

  test('词条标题：中日文相同时不重复显示', () {
    const same = Keyword(
        jp: '切札', zh: '切札', type: '使用限制', cond: '', desc: '');
    expect(same.label, '切札', reason: '不该显示成「切札（切札）」');

    const diff = Keyword(
        jp: 'ステップ', zh: '移动', type: '使用型基本能力', cond: '', desc: '');
    expect(diff.label, '移动（ステップ）');

    const onlyJp = Keyword(jp: 'ジャンプ', zh: '', type: '', cond: '', desc: '');
    expect(onlyJp.label, 'ジャンプ');
  });
}
