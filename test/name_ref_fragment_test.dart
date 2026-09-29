import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';

/// 片假名名字的引用判定回归测试。
///
/// 背景：`name_refs` 是一条「效果文本里提到的名字 → 卡号」的表。
/// 表里有个 2 字条目「ナル」（『屍食部隊』ナル 的短称）。日文片假名没有
/// 空格，于是匹配器一度把规则词「ペナルティ」中间的「ナル」也当成引用 ——
/// 实测 541 张卡的效果里因此凭空多出一处指向别作品的假跳转；
/// 「リト」撞「リトルバスターズ」、「ソル」撞「ソルティレージュ」同理。
///
/// 修法不是加词表，而是用片假名本身的边界：**带片假名的名字必须占满
/// 整个片假名词组才算引用**。汉字没有这种天然边界，所以只对全片假名
/// 名字生效（「言霊」这种可能是复合词的一部分，不动）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CardRepository repo;

  setUpAll(() async {
    await CardRepository.instance.load();
    repo = CardRepository.instance;
  });

  String effectOf(String code) {
    final card = repo.all.firstWhere((c) => c.code == code);
    return card.effectJp ?? '';
  }

  /// 命中片段的原文（用来判断某个名字有没有被认出来）
  List<String> labels(String text) => repo
      .scanCardNames(text)
      .map((h) => text.substring(h.start, h.end))
      .toList();

  test('规则词里的片段不当引用：ペナルティ 里的「ナル」', () {
    final text = effectOf('LO-1155');
    expect(text.contains('ペナルティ'), isTrue, reason: '样本卡应含规则词 ペナルティ');
    expect(labels(text).contains('ナル'), isFalse,
        reason: '「ナル」是 ペナルティ 的中间两个字，不是卡名引用');
  });

  test('别的角色名里的片段不当引用：レオンハルト 里的「レオ」', () {
    final text = effectOf('LO-6400');
    expect(text.contains('レオンハルト'), isTrue);
    expect(labels(text).contains('レオ'), isFalse);
  });

  test('作品名里的片段不当引用：ソルティレージュ 里的「ソル」', () {
    final text = effectOf('LO-4137');
    expect(text.contains('ソルティレージュ'), isTrue);
    expect(labels(text).contains('ソル'), isFalse);
  });

  test('占了整个片假名词组的名字仍要认得出来：味方「ルミ」', () {
    final text = effectOf('LO-0379');
    expect(text.contains('「ルミ」'), isTrue);
    expect(labels(text).contains('ルミ'), isTrue,
        reason: '独立出现的「ルミ」必须依然能跳转');
  });

  test('同一条效果里：完整卡名要认、片段不认（レオンハルト 里的「レオ」）', () {
    // LO-6400 效果里既有完整卡名「平和を望む帝国第一皇女 ミリセント・
    // フリード・レオンハルト」，又有同一个词里的「レオ」
    final text = effectOf('LO-6400');
    final ls = labels(text);
    expect(ls.contains('レオ'), isFalse, reason: '「レオ」只是 レオンハルト 的片段');
    expect(ls.any((l) => l.length > 5 && l.contains('レオンハルト')), isTrue,
        reason: '完整卡名仍然要认出来');
  });

  test('游戏术语里的片段不当引用：チャージ 里的「チャー」', () {
    // 最严重的一例：LO-1239 真的叫「チャー」，但「チャー」在全库出现 1906 次，
    // 其中 1902 次是在规则词「チャージ」里 —— 修之前，任何提到充能的效果里
    // 都凭空多出一处指向 LO-1239 的假跳转；而且「チャー」从来不是真引用，
    // 全库没有任何一条效果独立提到过它。
    final text = effectOf('LO-2865');
    expect(text.contains('チャージ'), isTrue);
    expect(labels(text).contains('チャー'), isFalse,
        reason: '「チャー」是 チャージ 的片段，不是卡名引用');
  });
}
