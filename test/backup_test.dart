import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

/// 批次 2：导出 / 导入备份
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导出 → 导入 往返一致', () async {
    SharedPreferences.setMockInitialValues({});
    await CardRepository.instance.load();

    final s = await AppState.create();
    // 清掉首次安装自动放的「范例构筑」，只留我们自己建的那套
    for (final d in s.decks.toList()) {
      s.deleteDeck(d.id);
    }
    final deck = s.createDeck('雪之铁槌');
    s.addCard(deck, CardRepository.instance.byCode('LO-0575')!, 4);
    s.setDeckMain(deck, 'LO-0575');
    s.toggleOwned('LO-0575');
    s.setOwnedInfo(
      'LO-0575',
      OwnedInfo(
        price: 1000,
        currency: 'JPY',
        acquiredAt: DateTime(2026, 1, 2),
        note: '测试用',
      ),
    );
    s.toggleFavorite('LO-6281');
    s.setValueUnit('JPY');
    s.setValueHidden(false);

    final data = s.exportData();
    expect(data['app'], 'lycard');
    expect((data['decks'] as List).length, 1);
    // 等写入落盘，再把存档清空
    await AppState.create();

    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    final s2 = await AppState.create();
    expect(s2.decks, isEmpty, reason: '新存档应该是空的');
    expect(s2.totalValueCny, 0);

    final msg = s2.importData(data);
    // ignore: avoid_print
    debugPrint('恢复结果：$msg');

    expect(s2.decks.length, 1);
    expect(s2.decks.first.name, '雪之铁槌');
    expect(s2.decks.first.cards['LO-0575'], 4);
    expect(s2.decks.first.mainCardCode, 'LO-0575');
    expect(s2.isOwned('LO-0575'), isTrue);
    expect(s2.isFavorite('LO-6281'), isTrue);
    expect(s2.totalValueCny, closeTo(48, 0.001));
    expect(s2.valueUnit, 'JPY');
    expect(s2.valueHidden, isFalse);
    expect(s2.infoOf('LO-0575')!.acquiredAt, DateTime(2026, 1, 2));
    expect(s2.infoOf('LO-0575')!.note, '测试用');
  });

  test('不是 lycard 的备份会被拒绝', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppState.create();
    expect(
      () => s.importData({'app': 'something-else'}),
      throwsA(isA<FormatException>()),
    );
  });
}
