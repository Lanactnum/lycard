import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';

import 'package:lycee_app/state/app_state.dart';
import 'package:flutter/foundation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('卡池与中文翻译能正确加载', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    expect(repo.count, greaterThan(9000), reason: '卡池应有 9000+ 张');

    // 抽几张验证：中文名、效果、数值都要对
    final c1 = repo.byCode('LO-0575');
    expect(c1, isNotNull, reason: 'LO-0575 应存在');
    expect(c1!.color, '雪');
    expect(c1.ap, 4);
    expect(c1.dp, 2);
    expect(c1.displayName, contains('源赖光'));
    expect(c1.effectZh, isNotNull);
    expect(c1.effectZh!, contains('[诱发]'));

    // 翻译覆盖率：有日文名的卡基本都该有中文名
    final named = repo.all.where((c) => c.nameJp.trim().isNotEmpty).toList();
    final translated = named.where((c) => (c.nameZh ?? '').trim().isNotEmpty);
    final ratio = translated.length / named.length;
    expect(ratio, greaterThan(0.95),
        reason: '中文名覆盖率应 >95%，实际 ${(ratio * 100).toStringAsFixed(1)}%');

    // 检索功能
    final hits = repo.search('LO-0575');
    expect(hits, isNotEmpty);
    expect(hits.first.code, 'LO-0575');

    debugPrint('卡池 ${repo.count} 张，有日文名 ${named.length} 张，'
        '已译 ${translated.length} 张（${(ratio * 100).toStringAsFixed(1)}%）');
    debugPrint('示例 LO-0575 -> ${c1.displayName} | ${c1.effectZh}');
  });

  test('构筑规则检测', () {
    final deck = Deck(id: 't', name: '测试', mainCardCode: '');
    expect(DeckRules.mainDeckSize, 60);
    expect(DeckRules.maxCopiesPerCode, 4);
    expect(DeckRules.maxLeader, 1);
    expect(deck.total, 0);
  });

  test('卡组收集按「会社 → 作品」分组（不是按 LO 卡号）', () {
    final repo = CardRepository.instance;
    final g = repo.groupByBrandThenSeries();
    // 会社数量应当远多于卡号前缀（卡号前缀只有 LO 一个）
    // ignore: avoid_print
    debugPrint('会社/分组数: ${g.length}');
    var seriesCount = 0;
    var cardCount = 0;
    g.forEach((brand, list) {
      seriesCount += list.length;
      for (final s in list) {
        cardCount += s.cards.length;
      }
    });
    // ignore: avoid_print
    debugPrint('作品数: $seriesCount  卡片总数: $cardCount');
    expect(g.length, greaterThan(10), reason: '会社应当有几十个');
    expect(seriesCount, greaterThan(50), reason: '作品应当有一百多个');
    expect(cardCount, repo.count, reason: '所有卡都要有归属，不能漏');
    expect(g.containsKey('NIT'), isTrue, reason: '应当能认出 NIT 会社');
  });
}
