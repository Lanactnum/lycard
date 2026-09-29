import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_related.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/data/keyword_db.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 要求 45：卡详情「关联卡牌」推荐栏
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh() async {
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await AppState.create();
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await CardRepository.instance.load();
    await KeywordDb.instance.load();
    return AppState.create();
  }

  test('同词条的卡 → 归到「相似-词条」', () async {
    final s = await fresh();
    final repo = CardRepository.instance;

    // 找两张效果里都带「[跳]」这个基本能力的卡
    final two = repo.all
        .where((c) => (c.effectZh ?? '').contains('[跳'))
        .take(2)
        .toList();
    expect(two.length, 2, reason: '卡池里应该有多张带[跳]的卡');

    final d = s.createDeck('跳套牌');
    s.addCard(d, two[0], 4);
    s.addCard(d, two[1], 4);

    final groups = relatedGroups(code: two[0].code, decks: s.decks);
    // ignore: avoid_print
    debugPrint('${two[0].code} 在「跳套牌」里的关联：'
        '${groups.map((g) => '${g.deckName}[${g.items.map((i) => '${i.label}×${i.cards.length}').join('、')}]').join(' / ')}');

    expect(groups.length, 1);
    expect(groups.first.deckName, '跳套牌');
    expect(
        groups.first.items.any((i) => i.label.contains('跳') &&
            i.cards.any((c) => c.code == two[1].code)),
        isTrue);
    // 自己不会出现在推荐里
    expect(
        groups.first.items.every((i) => i.cards.every((c) => c.code != two[0].code)),
        isTrue);
  });

  test('效果里互相提到名字 → 归到「关联」，且排在相似前面', () async {
    final s = await fresh();
    final repo = CardRepository.instance;

    // 在卡池前 900 张里找一对「A 的效果里写了 B 的名字」
    final sample = repo.all.take(900).toList();
    final names = <String, String>{
      for (final c in sample)
        if ((c.nameZh ?? '').length >= 3) c.nameZh!: c.code,
    };
    String? aCode;
    String? bCode;
    for (final c in sample) {
      final t = c.effectZh ?? '';
      for (final e in names.entries) {
        if (e.value != c.code && t.contains(e.key)) {
          aCode = c.code;
          bCode = e.value;
          break;
        }
      }
      if (aCode != null) break;
    }
    // ignore: avoid_print
    debugPrint('找到一对：$aCode 的效果里提到了 ${repo.byCode(bCode ?? '')?.nameZh}（$bCode）');
    expect(aCode, isNotNull, reason: '卡池里应该有互相引用的卡');

    final d = s.createDeck('引用套牌');
    s.addCard(d, repo.byCode(aCode!)!, 1);
    s.addCard(d, repo.byCode(bCode!)!, 1);

    final groups = relatedGroups(code: aCode, decks: s.decks);
    expect(groups, isNotEmpty);
    final items = groups.first.items;
    expect(items.first.label, contains('关联'));
    expect(items.first.cards.any((c) => c.code == bCode), isTrue);
  });

  test('按构筑分组：两套牌各出一组，顺序是构筑1 → 构筑2', () async {
    final s = await fresh();
    final repo = CardRepository.instance;
    final two = repo.all
        .where((c) => (c.effectZh ?? '').contains('[跳'))
        .take(3)
        .toList();

    final d1 = s.createDeck('第一套');
    s.addCard(d1, two[0], 4);
    s.addCard(d1, two[1], 4);
    final d2 = s.createDeck('第二套');
    s.addCard(d2, two[0], 4);
    s.addCard(d2, two[2], 4);

    final groups = relatedGroups(code: two[0].code, decks: s.decks);
    // ignore: avoid_print
    debugPrint('分组顺序：${groups.map((g) => g.deckName).toList()}');
    expect(groups.length, 2);
    expect(groups[0].deckName, '第一套');
    expect(groups[1].deckName, '第二套');
  });

  test('这张卡不在任何构筑里 → 没有推荐', () async {
    final s = await fresh();
    expect(relatedGroups(code: 'LO-0575', decks: s.decks), isEmpty);
  });
}
