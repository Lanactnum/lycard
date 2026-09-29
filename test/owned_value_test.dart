import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 批次 2：入库价值 / 汇率 / 单位切换
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('入库价值：按汇率折算、按单位显示、默认隐藏', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppState.create();

    expect(s.totalValueCny, 0);
    expect(s.valueHidden, isTrue, reason: '默认必须是隐藏');
    expect(s.valueText, '••••••');

    s.toggleOwned('LO-0575');
    s.setOwnedInfo('LO-0575', OwnedInfo(price: 1000, currency: 'JPY'));
    // 日元默认汇率 0.048
    expect(s.totalValueCny, closeTo(48, 0.001));
    expect(s.pricedCount, 1);

    s.setValueHidden(false);
    expect(s.valueText, '¥48.00');

    s.setValueUnit('JPY');
    expect(s.totalValueInUnit, closeTo(1000, 0.01));
    expect(s.valueText, '¥1000.00');
    s.setValueUnit('CNY');

    // 单独改汇率 → 用独立汇率算
    s.setOwnedInfo('LO-0575', OwnedInfo(price: 1000, currency: 'JPY', rate: 0.05));
    expect(s.totalValueCny, closeTo(50, 0.001));

    // 没收集的卡不计数
    s.setOwnedInfo('LO-6281', OwnedInfo(price: 99999, currency: 'CNY'));
    expect(s.totalValueCny, closeTo(50, 0.001));

    // 收集第二张 → 计入
    s.toggleOwned('LO-6281');
    expect(s.totalValueCny, closeTo(50 + 99999, 0.001));
    expect(s.pricedCount, 2);

    // 清除
    s.setOwnedInfo('LO-6281', null);
    expect(s.totalValueCny, closeTo(50, 0.001));
    expect(s.infoOf('LO-6281'), isNull);

    // 持久化：重开一个 AppState 还在
    final s2 = await AppState.create();
    expect(s2.totalValueCny, closeTo(50, 0.001));
    expect(s2.valueHidden, isFalse);
    expect(s2.infoOf('LO-0575')!.currency, 'JPY');
    expect(s2.infoOf('LO-0575')!.rate, closeTo(0.05, 1e-9));
  });

  test('入库时间与备注能存下来', () async {
    SharedPreferences.setMockInitialValues({});
    final s = await AppState.create();
    s.toggleOwned('LO-0575');
    s.setOwnedInfo(
      'LO-0575',
      OwnedInfo(
        price: 320,
        currency: 'CNY',
        acquiredAt: DateTime(2026, 3, 15),
        note: '秋叶原购入',
      ),
    );
    final s2 = await AppState.create();
    final info = s2.infoOf('LO-0575')!;
    expect(info.acquiredAt, DateTime(2026, 3, 15));
    expect(info.note, '秋叶原购入');
    expect(s2.totalValueCny, closeTo(320, 0.001));
  });
}
