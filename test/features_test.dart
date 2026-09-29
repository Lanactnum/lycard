import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/data/keyword_db.dart';
import 'package:flutter/foundation.dart';

/// 三个新功能的硬验证：
///   ① 词条能认出来（带括号 / 不带括号都行）
///   ② 效果里提到的别的卡名能认出来（点了能跳转）
///   ③ 复制文本内容完整
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('词条库能加载，并且能认出跳/充能等词条', () async {
    await KeywordDb.instance.load();
    expect(KeywordDb.instance.isLoaded, isTrue);
    expect(KeywordDb.instance.all.length, greaterThanOrEqualTo(20));
    // ignore: avoid_print
    debugPrint('词条数: ${KeywordDb.instance.all.length}');

    // 日文：方括号 + 带参数
    final jp = KeywordDb.instance.find('ジャンプ');
    expect(jp, isNotNull);
    expect(jp!.zh, '跳');
    // ignore: avoid_print
    debugPrint('ジャンプ -> ${jp.zh} / ${jp.type}');

    // 中文：不带括号也应当认出来
    final hits = KeywordDb.instance.scan('使用跳移动到另一个友方区域');
    expect(hits, isNotEmpty, reason: '中文词条应当被识别');
    expect(hits.first.$3.zh, '跳');

    // 方括号形式
    final h2 = KeywordDb.instance.scan('[チャージ:2] このキャラが登場したとき');
    expect(h2, isNotEmpty);
    expect(h2.first.$3.zh, '充能');

    // 带参数的中文形式（术语统一后用「切札」）
    final h3 = KeywordDb.instance.scan('【切札：丢弃1张手牌】');
    expect(h3, isNotEmpty);
    expect(h3.first.$3.zh, '切札');
  });

  test('效果里提到的卡名能认出来', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    final target = repo.byCode('LO-0575');
    expect(target, isNotNull);
    final name = target!.nameJp;
    // ignore: avoid_print
    debugPrint('拿 ${target.code} 当靶子: $name');

    final text = '把$name破坏，然后抽一张牌。';
    final hits = repo.scanCardNames(text);
    // ignore: avoid_print
    debugPrint('命中: ${hits.map((h) => '${h.start}-${h.end}->${h.code}').toList()}');
    expect(hits, isNotEmpty, reason: '应当认出提到的卡名');
    expect(hits.first.code, 'LO-0575');

    // 中文译名也要能认
    final zhName = target.nameZh ?? '';
    if (zhName.length >= 3) {
      final hits2 = repo.scanCardNames('这张卡是 $zhName 的支援。');
      // ignore: avoid_print
      debugPrint('中文名命中: ${hits2.map((h) => h.code).toList()}');
      expect(hits2, isNotEmpty, reason: '中文译名也应该能跳转');
    }
  });

  test('费用 / 卡种 / 区域限制都能读出来（之前是空的）', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    // LO-6407-X 就是用户截图里那张：费用 花花、卡种 角色
    final c = repo.byCode('LO-6407-X');
    expect(c, isNotNull);
    // ignore: avoid_print
    debugPrint('${c!.code}: 属性=${c.color} 费用=${c.cost} 卡种=${c.kindZh} '
        '类型=${c.cardType ?? "（官方无）"} 制限=${c.limit} '
        'AP${c.ap}/DP${c.dp}/SP${c.sp}/DMG${c.dmg}');
    expect(c.cost, isNotNull, reason: '费用不该是空的');
    expect(c.cost, '花花');
    expect(c.kindZh, '角色');
    expect(c.limit, isNotNull);

    // 全库覆盖率
    final all = repo.all;
    final withCost = all.where((e) => (e.cost ?? '').isNotEmpty).length;
    final withKind = all.where((e) => (e.kind ?? '').isNotEmpty).length;
    // ignore: avoid_print
    debugPrint('有费用: $withCost/${all.length}   有卡种: $withKind/${all.length}');
    expect(withCost, greaterThan(all.length * 0.98), reason: '费用覆盖率应当 >98%');
    expect(withKind, all.length, reason: '卡种应当 100% 覆盖');
  });

  test('复制信息内容完整', () async {
    await CardRepository.instance.load();
    final card = CardRepository.instance.byCode('LO-0575')!;
    final text = CardRepository.exportText(card);
    // ignore: avoid_print
    debugPrint('---- 复制内容 ----\n$text\n----------------');
    expect(text.contains('LO-0575'), isTrue);
    expect(text.contains(card.displayName), isTrue);
    expect(text.contains('系列：'), isTrue);
    expect(text.contains('会社：'), isTrue);
    expect(text.contains('lycard'), isTrue);
  });
}
