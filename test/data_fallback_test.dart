import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';

/// 数据兜底：译文表与卡表两份数据合并时的取值规则。
///
/// 背景：卡详情里「效果」栏曾经出现"汉化神奇消失"——数据其实都在，
/// 但代码写的是 `t['effect'] as String? ?? c.effectZh`，而 `??` **只对
/// null 兜底**；译文表里存的是空串 `''` 时它会被原样采用，界面就白了。
/// 现在改成取第一个非空值，这里把规则钉住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('有中文译文的卡：卡名和效果都不为空', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    final c = repo.byCode('LO-0001');
    expect(c, isNotNull);
    expect(c!.nameZh, isNotNull);
    expect(c.nameZh!.trim(), isNotEmpty, reason: '卡名不该是空的');
    expect(c.effectZh, isNotNull);
    expect(c.effectZh!.trim(), isNotEmpty, reason: '效果不该是空的');
    // ignore: avoid_print
    print('LO-0001: ${c.nameZh} / 效果 ${c.effectZh!.length} 字');
  });

  test('取不到译文时返回 null，而不是空串', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    // 全量扫一遍：effectZh / nameZh 要么是有内容的字符串，要么是 null。
    // 空串会让 UI 显示一片空白（而不是"暂未收录效果文本"的兜底文案）。
    final badName = <String>[];
    final badEff = <String>[];
    for (final c in repo.all) {
      if (c.nameZh != null && c.nameZh!.trim().isEmpty) badName.add(c.code);
      if (c.effectZh != null && c.effectZh!.trim().isEmpty) badEff.add(c.code);
    }
    expect(badName, isEmpty, reason: '这些卡的卡名是空串：${badName.take(8)}');
    expect(badEff, isEmpty, reason: '这些卡的效果是空串：${badEff.take(8)}');
  });

  test('没中文效果的卡，日文原文仍在（不互相覆盖）', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    var withJp = 0;
    var withZh = 0;
    for (final c in repo.all) {
      if ((c.effectJp ?? '').trim().isNotEmpty) withJp++;
      if ((c.effectZh ?? '').trim().isNotEmpty) withZh++;
    }
    // ignore: avoid_print
    print('有日文效果 $withJp 张 / 有中文效果 $withZh 张');
    expect(withJp, greaterThan(9000), reason: '日文原文是数据主体，不该丢');
    expect(withZh, greaterThan(9000), reason: '中文效果覆盖率应当很高');
  });
}
