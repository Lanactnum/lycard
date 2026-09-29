import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/card_edit.dart';

/// 性能相关的缓存行为回归测试。
///
/// 这些缓存是 0.71.0 加的：以前 `groupByBrandThenSeries()` 每次
/// build 都重建（遍历 9952 张卡 + 每组排序），搜索时每张卡还要
/// 现算 5 次 `toLowerCase()`。缓存本身不难，难的是**失效**——
/// 缓存不失效就会显示旧数据，所以这里把两条都钉死。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('分组缓存：同一个对象返回两次，改卡后作废', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    final a = repo.groupByBrandThenSeries();
    final b = repo.groupByBrandThenSeries();
    expect(identical(a, b), isTrue, reason: '第二次应该直接拿缓存，不是重算');

    // 改一张卡 → 缓存必须作废（否则列表还显示旧名字）
    final first = repo.all.first;
    repo.setEdits({
      first.code: CardOverride(code: first.code, nameZh: '缓存失效测试名'),
    });
    final c = repo.groupByBrandThenSeries();
    expect(identical(a, c), isFalse, reason: '改卡后必须重建');

    // 还原，别污染后面的测试
    repo.setEdits({});
  });

  test('搜索小写缓存：改卡后能搜到新名字', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    final first = repo.all.first;

    repo.setEdits({
      first.code: CardOverride(code: first.code, nameZh: 'ZZZ缓存测试'),
    });

    final hit = repo.query('zzz缓存测试', null);
    expect(hit.map((c) => c.code), contains(first.code),
        reason: '小写缓存必须跟着 setEdits 一起重建，否则搜不到新改的名字');

    repo.setEdits({});
  });

  test('搜索小写缓存：大小写不敏感仍然成立', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    // 用卡号搜，故意大写/小写各来一次，结果应该一致
    final code = repo.all.first.code;
    final upper = repo.query(code.toUpperCase(), null).map((c) => c.code).toSet();
    final lower = repo.query(code.toLowerCase(), null).map((c) => c.code).toSet();
    expect(upper, lower, reason: '大小写不该影响命中集合');
    expect(upper, contains(code));
  });
}
