import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 批次 4：备卡区 / 拖拽互换 / 胜负记录 / MVP 心得 / 版本快照 / 简介
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh() async {
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await AppState.create();
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await CardRepository.instance.load();
    return AppState.create();
  }

  test('备卡区：主卡↔备卡互换，最多 10 张', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    final a = CardRepository.instance.byCode('LO-0575')!;
    s.addCard(d, a, 4);
    expect(d.total, 4);
    expect(d.sideTotal, 0);

    // 挪 2 张进备卡区
    s.moveToSideboard(d, 'LO-0575', 2);
    expect(d.cards['LO-0575'], 2);
    expect(d.sideboard['LO-0575'], 2);
    expect(d.total, 2);
    expect(d.sideTotal, 2);

    // 再挪回来
    s.moveToMain(d, 'LO-0575', 1);
    expect(d.sideboard['LO-0575'], 1);
    expect(d.cards['LO-0575'], 3);
    // ignore: avoid_print
    debugPrint('互换后 主卡 ${d.total} 张 / 备卡 ${d.sideTotal} 张');

    // 备卡区上限 10：主卡有 12 张，但只剩 9 个位置 → 只挪进去 9 张
    d.cards['LO-6281'] = 12;
    s.moveToSideboard(d, 'LO-6281', 12);
    // ignore: avoid_print
    debugPrint('想挪 12 张进备卡 → 备卡 ${d.sideTotal} 张（上限 ${Deck.maxSideboard}），'
        '主卡还剩 ${d.cards['LO-6281']} 张');
    expect(d.sideTotal, Deck.maxSideboard);
    expect(d.cards['LO-6281'], 3, reason: '12 张里只挪走 9 张');
  });

  test('校验联动：主卡 4 张 + 备卡 1 张 = 5 张 → 报错', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    // 主卡 4 张 + 备卡 1 张（直接摆，光靠 addCard 挪不出这个组合）
    d.cards['LO-0575'] = 4;
    d.sideboard['LO-0575'] = 1;

    final issues = s.checkDeck(d);
    final errs = issues
        .where((i) => i.level == IssueLevel.error)
        .map((i) => i.message)
        .toList();
    // ignore: avoid_print
    debugPrint('主4+备1 的报错：${errs.join(' | ')}');
    expect(errs.any((m) => m.contains('备卡') && m.contains('5 张')), isTrue);
  });

  test('胜负记录：胜率 + 可删除', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    expect(d.winRateText, '-');

    s.addBattle(d, win: true, memo: '对手卡手');
    s.addBattle(d, win: true, opponent: '朋友');
    s.addBattle(d, win: false, memo: '被快攻');
    expect(d.wins, 2);
    expect(d.losses, 1);
    expect(d.winRateText, '66.7%');
    // ignore: avoid_print
    debugPrint('战绩 ${d.wins}胜${d.losses}负 → 胜率 ${d.winRateText}');

    s.removeBattle(d, d.battles.first.id);
    expect(d.battles.length, 2);
  });

  test('MVP 标记与单卡心得', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    s.addCard(d, CardRepository.instance.byCode('LO-0575')!, 4);

    s.toggleMvp(d, 'LO-0575');
    expect(d.mvpCodes, contains('LO-0575'));
    s.toggleMvp(d, 'LO-0575');
    expect(d.mvpCodes, isEmpty);

    s.toggleMvp(d, 'LO-0575');
    s.setCardNote(d, 'LO-0575', '这套牌靠它第 2 回合出场');
    expect(d.cardNotes['LO-0575'], '这套牌靠它第 2 回合出场');
    s.setCardNote(d, 'LO-0575', '   ');
    expect(d.cardNotes.containsKey('LO-0575'), isFalse, reason: '清空就删掉');
  });

  test('版本快照：回滚连该版本的胜负记录一起回来', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    s.addCard(d, CardRepository.instance.byCode('LO-0575')!, 4);
    s.addBattle(d, win: true);
    s.addBattle(d, win: true);

    // v1.0 比赛版：4 张 LO-0575 + 2 胜
    final snap = s.saveSnapshot(d, 'v1.0 比赛版');
    expect(snap.wins, 2);
    expect(snap.cards['LO-0575'], 4);
    expect(d.snapshots.length, 1);

    // 改版：加卡、加战绩
    s.addCard(d, CardRepository.instance.byCode('LO-6281')!, 3);
    s.addBattle(d, win: false);
    s.setIntro(d, '针对版，换了 3 张');
    expect(d.total, 7);
    expect(d.losses, 1);

    // 回滚
    s.rollbackSnapshot(d, snap.id);
    // ignore: avoid_print
    debugPrint('回滚后：主卡 ${d.cards} / 战绩 ${d.wins}胜${d.losses}负');
    expect(d.cards['LO-0575'], 4);
    expect(d.cards.containsKey('LO-6281'), isFalse);
    expect(d.wins, 2, reason: '该版本的胜负记录一起带回来');
    expect(d.losses, 0);
  });

  test('简介可编辑，跟着备份走', () async {
    final s = await fresh();
    final d = s.createDeck('雪之铁槌');
    s.setIntro(d, '单作品雪属性，主打前排压制');
    expect(d.intro, '单作品雪属性，主打前排压制');

    // 序列化往返
    final back = Deck.fromJson(d.toJson());
    expect(back.intro, '雪之铁槌'.isEmpty ? '' : back.intro);
    expect(back.intro, d.intro);

    // 备份往返
    final data = s.exportData();
    final s2 = await fresh();
    s2.importData(data);
    expect(s2.decks.first.intro, d.intro);
  });

  test('构筑的新字段能完整序列化（备卡/战绩/快照/MVP/心得）', () async {
    final s = await fresh();
    final d = s.createDeck('全套测试');
    s.addCard(d, CardRepository.instance.byCode('LO-0575')!, 4);
    s.moveToSideboard(d, 'LO-0575', 1);
    s.addBattle(d, win: true, memo: 'm', opponent: 'o');
    s.toggleMvp(d, 'LO-0575');
    s.setCardNote(d, 'LO-0575', '核心');
    s.setIntro(d, '简介文字');
    s.saveSnapshot(d, 'v1.0');

    final back = Deck.fromJson(d.toJson());
    expect(back.sideboard['LO-0575'], 1);
    expect(back.battles.length, 1);
    expect(back.battles.first.memo, 'm');
    expect(back.snapshots.length, 1);
    expect(back.snapshots.first.label, 'v1.0');
    expect(back.mvpCodes, contains('LO-0575'));
    expect(back.cardNotes['LO-0575'], '核心');
    expect(back.intro, '简介文字');
    // ignore: avoid_print
    debugPrint('序列化往返 OK：备卡 ${back.sideTotal} / 战绩 ${back.battles.length} / '
        '快照 ${back.snapshots.length}');
  });
}
