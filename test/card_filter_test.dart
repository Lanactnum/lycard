import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_filter.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/data/keyword_db.dart';
import 'package:flutter/foundation.dart';

/// 检索页的组合筛选 + 分页逻辑
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('组合筛选：属性 → 卡种 → 费用上限 逐层收敛', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    final f = CardFilter();

    expect(f.isEmpty, isTrue, reason: '一开始没有条件');
    expect(repo.query('', f), isEmpty, reason: '没条件没关键词 → 不返回结果');

    f.colors.add('雪');
    expect(f.activeCount, 1);
    final byColor = repo.query('', f);
    // ignore: avoid_print
    debugPrint('属性=雪 → ${byColor.length} 张');
    expect(byColor, isNotEmpty);
    expect(byColor.every((c) => (c.color ?? '').contains('雪')), isTrue);

    f.kinds.add('キャラクター');
    final byKind = repo.query('', f);
    // ignore: avoid_print
    debugPrint('再叠卡种=角色 → ${byKind.length} 张');
    expect(byKind.length, lessThanOrEqualTo(byColor.length));
    expect(byKind.every((c) => c.kind == 'キャラクター'), isTrue);

    f.costMax = 1;
    final byCost = repo.query('', f);
    // ignore: avoid_print
    debugPrint('再叠费用≤1 → ${byCost.length} 张');
    expect(byCost.length, lessThanOrEqualTo(byKind.length));
    expect(byCost.every((c) => (c.cost?.length ?? 99) <= 1), isTrue);

    // 清空后恢复
    f.clear();
    expect(f.isEmpty, isTrue);
    expect(repo.query('', f), isEmpty);
  });

  test('全文 + 筛选叠加', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    final f = CardFilter();

    final all = repo.query('源頼光', null);
    // ignore: avoid_print
    debugPrint('关键词「源頼光」→ ${all.length} 张');
    expect(all, isNotEmpty);

    f.rarities.add('SR');
    final narrowed = repo.query('源頼光', f);
    // ignore: avoid_print
    debugPrint('再叠稀有度=SR → ${narrowed.length} 张');
    expect(narrowed.length, lessThanOrEqualTo(all.length));
    expect(narrowed.every((c) => c.rarity == 'SR'), isTrue);
  });

  test('词条筛选：效果里必须出现该词条', () async {
    await CardRepository.instance.load();
    await KeywordDb.instance.load();
    final repo = CardRepository.instance;
    final kws = KeywordDb.instance.all;
    expect(kws, isNotEmpty);
    final kw = kws.first.zh;

    final f = CardFilter()..keywords.add(kw);
    final r = repo.query('', f);
    // ignore: avoid_print
    debugPrint('词条「$kw」→ ${r.length} 张');
    expect(r, isNotEmpty);
    for (final c in r) {
      expect('${c.effectZh ?? ''} ${c.effectJp ?? ''}'.contains(kw) ||
          KeywordDb.instance
              .scan('${c.effectZh ?? ''} ${c.effectJp ?? ''}')
              .any((e) => e.$3.zh == kw), isTrue);
    }
  });

  test('筛选面板的候选项来自真实数据', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    expect(repo.allColors, contains('雪'));
    expect(repo.allKinds.length, 4);
    expect(repo.allRarities, contains('SR'));
    // ignore: avoid_print
    debugPrint('候选项：属性 ${repo.allColors.length} / 卡种 ${repo.allKinds.length} / '
        '类型 ${repo.allTypes.length} / 稀有度 ${repo.allRarities.length}');
  });
}
