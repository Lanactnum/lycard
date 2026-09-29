import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/card_edit.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 批次 5：自定义卡信息 / 换卡面 / 新建卡牌 / 分类编辑
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh() async {
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await AppState.create();
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await CardRepository.instance.load();
    final s = await AppState.create();
    CardRepository.instance.setEdits(s.cardEdits);
    return s;
  }

  test('改卡信息：改过的字段生效，没改的保持官方', () async {
    final s = await fresh();
    final repo = CardRepository.instance;
    final before = repo.byCode('LO-0575')!;
    // ignore: avoid_print
    debugPrint('官方：${before.nameZh} / AP ${before.ap} / 效果 '
        '${before.effectZh?.substring(0, 10)}…');

    s.setCardEdit(CardOverride(
      code: 'LO-0575',
      nameZh: '狂战士 源赖光（改）',
      ap: 9,
    ));
    final after = repo.byCode('LO-0575')!;
    // ignore: avoid_print
    debugPrint('改后：${after.nameZh} / AP ${after.ap} / 效果 '
        '${after.effectZh?.substring(0, 10)}…');
    expect(after.nameZh, '狂战士 源赖光（改）');
    expect(after.ap, 9);
    expect(after.effectZh, before.effectZh, reason: '没改的字段保持官方');
    expect(before.nameZh, isNot('狂战士 源赖光（改）'), reason: '原始对象没被改坏');
    expect(repo.isEdited('LO-0575'), isTrue);
  });

  test('换卡面字段能存下来', () async {
    final s = await fresh();
    s.setCardEdit(CardOverride(code: 'LO-0575', imageFile: 'c123.png'));
    expect(CardRepository.instance.editOf('LO-0575')!.imageFile, 'c123.png');
    // 只看字段（真图在手机上才有）
    final back = CardOverride.fromJson(
        s.cardEditOf('LO-0575')!.toJson());
    expect(back.imageFile, 'c123.png');
  });

  test('新建卡牌：卡池里能查到，也能被检索到', () async {
    final s = await fresh();
    final n0 = CardRepository.instance.count;

    s.createCustomCard('MY-0001', '我的自制卡');
    final c = CardRepository.instance.byCode('MY-0001');
    expect(c, isNotNull);
    expect(c!.displayName, '我的自制卡');
    expect(CardRepository.instance.count, n0 + 1);

    final hit = CardRepository.instance.query('我的自制卡', null);
    // ignore: avoid_print
    debugPrint('检索「我的自制卡」→ ${hit.length} 张：${hit.map((e) => e.code).toList()}');
    expect(hit.any((e) => e.code == 'MY-0001'), isTrue);

    s.setCardEdit(CardOverride(
        code: 'MY-0001', isNew: true, nameZh: '我的自制卡', ap: 5, color: '雪'));
    expect(CardRepository.instance.byCode('MY-0001')!.ap, 5);

    // 删掉
    s.clearCardEdit('MY-0001');
    expect(CardRepository.instance.byCode('MY-0001'), isNull);
    expect(CardRepository.instance.count, n0);
  });

  test('分类：加卡 / 改名 / 删分类', () async {
    final s = await fresh();
    s.setCardCategory('LO-0575', '我的主力', true);
    s.setCardCategory('LO-6281', '我的主力', true);
    s.setCardCategory('LO-0575', '待出', true);

    // ignore: avoid_print
    debugPrint('分类：${s.categories}（主力里 '
        '${s.cardEdits.values.where((e) => e.categories.contains('我的主力')).length} 张）');
    expect(s.categories, containsAll(['我的主力', '待出']));
    expect(
        s.cardEdits.values
            .where((e) => e.categories.contains('我的主力'))
            .length,
        2);

    // 改名 → 卡上的引用一起改
    s.renameCategory('我的主力', '主力套牌');
    expect(s.categories, contains('主力套牌'));
    expect(s.cardEditOf('LO-0575')!.categories, contains('主力套牌'));

    // 删分类 → 卡上的引用也去掉
    s.deleteCategory('待出');
    expect(s.categories, isNot(contains('待出')));
    expect(s.cardEditOf('LO-0575')!.categories, isNot(contains('待出')));

    // 移出最后一个分类 → 这条自定义已经没有任何内容了，直接丢掉
    s.setCardCategory('LO-0575', '主力套牌', false);
    expect(s.cardEditOf('LO-0575'), isNull,
        reason: '只剩分类的编辑，分类清空后就等于没改过');
  });

  test('清掉自定义 → 完全回到官方数据', () async {
    final s = await fresh();
    final official = CardRepository.instance.byCode('LO-0575')!.nameZh;
    s.setCardEdit(CardOverride(code: 'LO-0575', nameZh: '临时改的'));
    expect(CardRepository.instance.byCode('LO-0575')!.nameZh, '临时改的');
    s.clearCardEdit('LO-0575');
    expect(CardRepository.instance.byCode('LO-0575')!.nameZh, official);
    expect(CardRepository.instance.isEdited('LO-0575'), isFalse);
  });

  test('自定义能跟着备份一起走', () async {
    final s = await fresh();
    s.setCardEdit(CardOverride(
        code: 'LO-0575', nameZh: '改过的名字', ap: 7, categories: ['A分类']));
    s.createCustomCard('MY-9', '自建卡');
    final data = s.exportData();
    expect((data['cardEdits'] as Map).length, 2);

    final s2 = await fresh();
    expect(CardRepository.instance.byCode('MY-9'), isNull);
    s2.importData(data);
    expect(CardRepository.instance.byCode('LO-0575')!.nameZh, '改过的名字');
    expect(CardRepository.instance.byCode('MY-9')!.displayName, '自建卡');
    expect(s2.categories, contains('A分类'));
    // ignore: avoid_print
    debugPrint('备份往返后：改过的 ${s2.cardEditOf('LO-0575')!.nameZh} / '
        '自建 ${s2.cardEditOf('MY-9')!.isNew} / 分类 ${s2.categories}');
  });
}
