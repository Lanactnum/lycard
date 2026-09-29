import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// 对战教程数据（assets/data/tutorial.json）的结构体检。
///
/// 教程正文是纯数据、渲染器按 block 类型分派，所以 JSON 写坏了
/// 不会编译报错，只会在用户点开教程时白屏或漏内容。这里把结构
/// 钉死：类型必须在白名单里、表格必须带 head 和 rows、正文不能
/// 出现不该出现的东西。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 渲染器 _BlockView 认得的类型
  const known = {'p', 'key', 'note', 'steps', 'bullets', 'table', 'head'};

  late Map<String, dynamic> doc;
  late List<Map<String, dynamic>> chapters;

  setUpAll(() async {
    final s = await rootBundle.loadString('assets/data/tutorial.json');
    doc = jsonDecode(s) as Map<String, dynamic>;
    chapters = ((doc['chapters'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  });

  test('教程有足够章节，且每章标题与内容都不为空', () {
    expect(chapters.length, greaterThanOrEqualTo(8),
        reason: '教程至少要有 8 章（认识游戏 / 开局 / 场地 / 回合 / 费用 / 战斗 / 卡面 / 构筑…）');
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      expect('${c['title']}'.trim(), isNotEmpty, reason: '第 ${i + 1} 章缺标题');
      final blocks = (c['blocks'] as List?) ?? const [];
      expect(blocks, isNotEmpty, reason: '第 ${i + 1} 章「${c['title']}」没有任何内容块');
    }
  });

  test('所有内容块的类型都在渲染器白名单里', () {
    final bad = <String>[];
    for (final c in chapters) {
      for (final b in (c['blocks'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(b as Map);
        final t = '${m['t'] ?? 'p'}';
        if (!known.contains(t)) bad.add('${c['title']} → $t');
        // 除 table 外都必须有 x 字段
        if (t != 'table' && '${m['x'] ?? ''}'.trim().isEmpty) {
          bad.add('${c['title']} → $t 内容为空');
        }
      }
    }
    expect(bad, isEmpty, reason: '这些块渲染不出来：${bad.join('，')}');
  });

  test('表格块必须同时有表头和数据行', () {
    var tables = 0;
    for (final c in chapters) {
      for (final b in (c['blocks'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(b as Map);
        if ('${m['t']}' != 'table') continue;
        tables++;
        final head = (m['head'] as List?) ?? const [];
        final rows = (m['rows'] as List?) ?? const [];
        expect(head.length, greaterThanOrEqualTo(2),
            reason: '${c['title']} 的表格表头不足两列');
        expect(rows, isNotEmpty, reason: '${c['title']} 的表格没有数据行');
        for (final r in rows) {
          final cells = (r as List).length;
          expect(cells, greaterThanOrEqualTo(2),
              reason: '${c['title']} 有一行只有 $cells 格，渲染器会读空');
        }
      }
    }
    expect(tables, greaterThan(0), reason: '教程里应该有表格');
  });

  test('教程正文不含第三方站点原文或品牌字样', () {
    final all = jsonEncode(doc);
    for (final bad in ['moetcg', '萌卡', '萌卡社', 'MOETCG']) {
      expect(all.toLowerCase().contains(bad.toLowerCase()), isFalse,
          reason: '教程里出现了「$bad」');
    }
  });

  test('教程覆盖了词条表里的全部基本能力', () async {
    // 教程第 8 章叫「基本能力一览」，就必须真的是一览。
    // 实测漏过 4 个（援助/领导者/主演/突袭）—— 词条表有、教程没有，
    // 用户翻教程查不到。
    final kwRaw =
        jsonDecode(await rootBundle.loadString('assets/data/keywords.json'));
    final all = jsonEncode(doc);
    final missing = <String>[];
    var checked = 0;
    for (final e in (kwRaw as List)) {
      final m = Map<String, dynamic>.from(e as Map);
      final type = '${m['type'] ?? ''}';
      final zh = '${m['zh'] ?? ''}';
      if (!type.contains('基本能力') || zh.isEmpty) continue;
      checked++;
      if (!all.contains(zh)) missing.add('$zh（${m['jp']}）');
    }
    expect(checked, greaterThanOrEqualTo(19),
        reason: '词条表里的基本能力条数不对，检查 keywords.json');
    expect(missing, isEmpty,
        reason: '这些基本能力在词条表里有、教程里没有：${missing.join('、')}');
  });

  test('教程里领导者的起手规则正确（6 张，不是 7 张）', () {
    final all = jsonEncode(doc);
    // 带领导者的卡组：开局把领导者单独拿出，起手 6 张。
    // 妙妙小解 PDF 与萌卡社都这么写。
    expect(all.contains('领导者'), isTrue, reason: '教程应提到领导者');
    expect(all.contains('6 张'), isTrue,
        reason: '教程应说明带领导者时起手是 6 张');
  });

  test('EX 的说明是正确的（不是稀有度）', () {
    // 官方定义：EX = 这张卡被当作费用支付时产生的费用点数。
    // 之前规则页把它写成「稀有度等级」，是硬错误，这里钉住。
    final all = jsonEncode(doc);
    expect(all.contains('EX'), isTrue);
    expect(all.contains('费用点数'), isTrue,
        reason: 'EX 必须按官方定义说明为「费用点数」');
    expect(all.contains('稀有度等级'), isFalse,
        reason: 'EX 不是稀有度等级');
  });
}
