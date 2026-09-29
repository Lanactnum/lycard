import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';

/// 效果文本里的卡名跳转（同名不同编号要挑对的那张）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('短卡名（2 字）也能被认出来', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    // 「言霊」只有两个字，以前索引门槛写 3 就被漏掉了
    final card = repo.byCode('LO-2635')!;
    final effect = card.effectJp ?? '';
    expect(effect.contains('言霊'), isTrue, reason: '这张卡的效果确实提到言霊');

    final hits = repo.scanCardNames(effect, selfSeries: card.series ?? '');
    final mention = hits.where((h) => effect.substring(h.start, h.end) == '言霊');
    expect(mention, isNotEmpty, reason: '「言霊」应当被识别成可跳转的卡名');

    // ignore: avoid_print
    print('LO-2635 效果里识别到: ${hits.map((h) => effect.substring(h.start, h.end)).toList()}');
  });

  test('同名不同编号：同系列的排在最前', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;

    final card = repo.byCode('LO-2635')!; // パープルソフトウェア 1.0(PUR)
    final hits = repo.scanCardNames(card.effectJp ?? '', selfSeries: card.series ?? '');
    final hit = hits.firstWhere(
        (h) => (card.effectJp ?? '').substring(h.start, h.end) == '言霊');

    // ignore: avoid_print
    print('言霊 的候选顺序: ${hit.codes}');
    // ignore: avoid_print
    for (final c in hit.codes) {
      // ignore: avoid_print
      print('   $c  ${repo.byCode(c)?.series}');
    }

    expect(hit.codes.length, greaterThan(1), reason: '言霊确实有多个编号');
    expect(hit.codes.first, 'LO-2707',
        reason: '第一候选应当是同系列(パープルソフトウェア 1.0)的 LO-2707，'
            '而不是别的弹（比如 2.0 的 LO-6651）');
  });
}
