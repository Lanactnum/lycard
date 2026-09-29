import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/models/lycee_card.dart';
import 'package:lycee_app/state/app_state.dart';

void main() {
  test('卡号解析：变体归到同一张卡', () {
    const c = LyceeCard(
      code: 'LO-6665-A',
      nameJp: '織部 こころ',
    );
    expect(c.baseCode, 'LO-6665');
    expect(c.setPrefix, 'LO');
    expect(c.displayName, '織部 こころ');
  });

  test('系列/会社解析：构筑限制靠这两层', () {
    const a = LyceeCard(
      code: 'LO-0001',
      nameJp: 'x',
      series: 'ニトロオリジン 1.0(NIT)',
    );
    expect(a.brandTag, 'NIT');
    expect(a.seriesName, 'ニトロオリジン 1.0');

    const b = LyceeCard(
      code: 'LO-0002',
      nameJp: 'y',
      series: 'Fate/Grand Order 1.0',
    );
    expect(b.brandTag, LyceeCard.brandOther);
    expect(b.seriesName, 'Fate/Grand Order 1.0');
  });

  testWidgets('主题能构建', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: Text(DeckRules.mainDeckSize.toString())),
        ),
      ),
    );
    expect(find.text('60'), findsOneWidget);
  });
}
