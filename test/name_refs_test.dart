import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';

/// 效果文本里引用卡名 → 能识别出来（能标蓝、能跳转）。
///
/// 起因：效果里常只写角色名（「御坂美琴」）而卡名是「超电磁炮 御坂美琴」，
/// 或者引用用日文汉字（「大藏遊星」）而卡名是简体（「大藏游星」）。
/// 名字索引原来只按 ／ 拆分卡名，这些都识别不出来。
/// 现在由 tools/build_name_refs.py 在构建时预计算，测试钉住它。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('效果里的角色名能识别（卡名只是「副标题 角色名」的一部分）', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    // 「御坂美琴」：卡名是「超电磁炮 御坂美琴」这种
    final hits = repo.scanCardNames('若我方「御坂美琴」已登场，抽1张牌。');
    expect(hits, isNotEmpty, reason: '「御坂美琴」应该能被识别出来');
    expect(hits.first.codes, isNotEmpty);

    // 「小仓朝日」：卡名是「露娜大人的侍从 小仓 朝日」（角色名自带空格）
    final h2 = repo.scanCardNames('如果我方「小仓朝日」有登场，抽1张牌。');
    expect(h2, isNotEmpty, reason: '「小仓朝日」应该能被识别出来');
  });

  test('引用用日文汉字、卡名是简体时也能识别', () async {
    await CardRepository.instance.load();
    // 「大藏遊星」（遊）vs 卡名「大藏游星」（游）
    final hits = CardRepository.instance.scanCardNames('如果我方「大藏遊星」有登场，抽1张牌。');
    expect(hits, isNotEmpty, reason: '繁简不同的引用名应该能识别');
  });

  test('嵌套引号（卡名自带引号）也能识别', () async {
    await CardRepository.instance.load();
    final hits = CardRepository.instance.scanCardNames(
      '从自己的卡组中寻找「灵式机巧刀「折纸」」1张，无偿装备。',
    );
    expect(hits, isNotEmpty, reason: '卡名自带引号时，效果里的嵌套引用应该能识别');
  });

  test('LO-2690 卡名、异画译名和效果引用均完整汉化', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    const expectedName = '『折纸』的看板娘 织部 心';
    const expectedEffectRef = '「倒毙路旁」';
    for (final code in ['LO-2690', 'LO-2690-K']) {
      final card = repo.byCode(code)!;
      expect(card.nameZh, expectedName);
      expect(card.effectZh, contains(expectedEffectRef));
      expect(card.effectZh, isNot(contains('行き倒れ')));
      expect(card.nameZh, isNot(contains('折り紙')));
      expect(card.nameZh, isNot(contains('織部')));
      expect(card.nameZh, isNot(contains('こころ')));
    }
  });

  test('唯一可映射的日文卡名引用使用中文名', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    expect(repo.byCode('LO-2690')?.effectZh, contains('「倒毙路旁」'));
    expect(repo.byCode('LO-0197')?.effectZh, contains('「实验」'));
    expect(repo.byCode('LO-0641')?.effectZh, contains('「放松」'));
  });
  test('名为「道具」的卡已进入卡名引用索引', () async {
    await CardRepository.instance.load();
    final hits = CardRepository.instance.scanCardNames('从卡组中寻找「道具」1张。');
    expect(hits, isNotEmpty);
    expect(hits.first.codes, contains('LO-1991'));
  });

  test('普通词不会被误标成卡名', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    for (final s in ['在你的回合中使用。抽1张牌。', '破坏对方卡组1张。']) {
      final hits = repo.scanCardNames(s);
      expect(hits, isEmpty, reason: '「$s」里没有卡名，不该有命中：$hits');
    }
  });
}
