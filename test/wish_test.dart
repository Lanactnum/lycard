import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/wish_card.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 批次 3：想要 / 出卡 / 缺卡统计 / 构筑抢卡冲突
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh({bool wipe = true}) async {
    // 先把 mock 装上（不然会去调真实的插件通道），
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    // 再把上一轮的异步写盘排干，否则 reset 之后旧数据还会追着落进来
    await AppState.create();
    if (wipe) SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await CardRepository.instance.load();
    return AppState.create();
  }

  test('想要 / 出卡分别归类，可以填品相价格和标签', () async {
    final s = await fresh();
    final w = s.addWish('LO-0575', price: 120, currency: 'CNY');
    final e = s.addWish('LO-6281', kind: WishKind.sell, price: 80);

    expect(s.wantList.length, 1);
    expect(s.sellList.length, 1);
    expect(s.isWanted('LO-0575'), isTrue);
    expect(s.isWanted('LO-6281'), isFalse, reason: '出卡不算想要');

    e.condition = 'A';
    e.tags.addAll(['轻微白边', '未打比赛']);
    e.photos.add('p1.jpg');
    e.note = '只出给同城';
    s.updateWish(e);

    final back = s.sellList.first;
    expect(back.condition, 'A');
    expect(back.tags, contains('未打比赛'));
    expect(back.photos, ['p1.jpg']);
    expect(back.note, '只出给同城');

    s.removeWish(w.id);
    expect(s.wantList, isEmpty);
  });

  test('缺卡统计：需要 4 张只有 2 张 → 算缺 2 张', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    s.addCard(d, CardRepository.instance.byCode('LO-0575')!, 4);
    s.addCard(d, CardRepository.instance.byCode('LO-6281')!, 2);

    // 一张都没有 → 两张都缺
    var miss = s.missingOf(d);
    // ignore: avoid_print
    debugPrint('一张都没有 → 缺 ${miss.map((e) => '${e.$1}(需${e.$2}/有${e.$3})').join(', ')}');
    expect(miss.length, 2);

    // 收集 LO-0575 并改成 2 张 → 还缺 2
    s.setOwnedQty('LO-0575', 2);
    s.setOwnedQty('LO-6281', 2);
    miss = s.missingOf(d);
    // ignore: avoid_print
    debugPrint('各持 2 张 → ${miss.map((e) => '${e.$1}(需${e.$2}/有${e.$3})').join(', ')}');
    expect(miss.length, 1);
    expect(miss.first.$1, 'LO-0575');
    expect(miss.first.$2, 4);
    expect(miss.first.$3, 2);

    // 补齐到 4 张 → 不缺了
    s.setOwnedQty('LO-0575', 4);
    expect(s.missingOf(d), isEmpty);
    expect(s.ownedQty('LO-0575'), 4);
    expect(s.ownedQty('LO-9999'), 0);
  });

  test('想要清单预计成本：都填了才算得出来，缺一个就显示 -', () async {
    final s = await fresh();
    s.addWish('LO-0575', price: 100);
    s.addWish('LO-6281', price: 50);
    expect(s.wantTotalCost, 150);

    // 外币按默认汇率折算
    final r = kDefaultRates['JPY'] ?? 0;
    // ignore: avoid_print
    debugPrint('默认汇率 JPY = $r（1000 日元 ≈ ${1000 * r} 元）');
    final jpy = s.addWish('LO-1000', price: 1000, currency: 'JPY');
    expect(s.wantTotalCost, closeTo(150 + 1000 * r, 0.01));

    // 有一张没填价 → null（界面显示 -）
    final noPrice = s.addWish('LO-2000');
    // ignore: avoid_print
    debugPrint('有未填价的卡后 wantTotalCost = ${s.wantTotalCost}');
    expect(s.wantTotalCost, isNull);

    noPrice.price = 30;
    s.updateWish(noPrice);
    expect(s.wantTotalCost, closeTo(180 + 1000 * r, 0.01));

    // 出卡不算进补齐成本
    s.addWish('LO-3000', kind: WishKind.sell, price: 999);
    expect(s.wantTotalCost, closeTo(180 + 1000 * r, 0.01));
    expect(jpy.kind, WishKind.want);
  });

  test('多套卡组抢同一张卡 → 实物不够就标记冲突', () async {
    final s = await fresh();
    final a = s.createDeck('构筑A');
    final b = s.createDeck('构筑B');
    s.addCard(a, CardRepository.instance.byCode('LO-6665')!, 4);
    s.addCard(b, CardRepository.instance.byCode('LO-6665')!, 4);

    // 一张都没有 → 冲突
    var c = s.conflictCodes;
    // ignore: avoid_print
    debugPrint('两张套牌各要 4 张 LO-6665，手里 0 张 → 冲突卡 ${c.length} 张：$c');
    expect(c, contains('LO-6665'));

    // 手里有 4 张，但两套一共要 8 张 → 还是冲突
    s.setOwnedQty('LO-6665', 4);
    expect(s.conflictCodes, contains('LO-6665'));
    expect(s.decksUsing('LO-6665').length, 2);

    // 手里 8 张 → 不冲突了
    s.setOwnedQty('LO-6665', 8);
    expect(s.conflictCodes, isNot(contains('LO-6665')));
  });

  test('想要 / 持有数量能被备份带走并恢复', () async {
    final s = await fresh();
    s.setOwnedQty('LO-0575', 3);
    final w = s.addWish('LO-6281', price: 66);
    w.tags.add('压痕');
    s.updateWish(w);
    final data = s.exportData();
    expect((data['wish'] as List).length, 1);
    expect(data['ownedQty'], {'LO-0575': 3});

    final s2 = await fresh();
    expect(s2.wantList, isEmpty);
    s2.importData(data);
    expect(s2.ownedQty('LO-0575'), 3);
    expect(s2.wantList.length, 1);
    expect(s2.wantList.first.price, 66);
    expect(s2.wantList.first.tags, contains('压痕'));
  });
}
