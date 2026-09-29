import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/clipboard_watch.dart';
import 'package:lycee_app/data/deck_share.dart';

void main() {
  test('分享码：往返一致，且 500 字以内', () {
    final d = DeckData(
      name: '测试构筑',
      mainCardCode: 'LO-4850',
      formatIndex: 1,
      intro: '简介里故意放上 | 竖线 和 , 逗号 和 : 冒号',
      cards: const {'LO-6665': 4, 'LO-5270': 3, 'LO-4850': 1, 'LO-0001': 2},
      sideboard: const {'LO-0002': 2},
    );
    final code = DeckShare.encode(d);
    expect(code.startsWith(DeckShare.prefix), isTrue);
    expect(code.length, lessThanOrEqualTo(DeckShare.maxLen),
        reason: '要求 500 字以内，实际 ${code.length}');

    final back = DeckShare.decode(code);
    expect(back, isNotNull);
    expect(back!.name, d.name);
    expect(back.mainCardCode, d.mainCardCode);
    expect(back.formatIndex, d.formatIndex);
    expect(back.cards, d.cards);
    expect(back.sideboard, d.sideboard);
  });

  test('分享码：满编 60 张 + 10 张备卡也够短', () {
    final cards = <String, int>{};
    for (var i = 0; i < 15; i++) {
      cards['LO-${6665 + i}'] = 4; // 60 张
    }
    final side = <String, int>{};
    for (var i = 0; i < 5; i++) {
      side['LO-${1000 + i}'] = 2; // 10 张
    }
    final code = DeckShare.encode(DeckData(
      name: '满编卡组',
      mainCardCode: 'LO-4850',
      formatIndex: 0,
      intro: '',
      cards: cards,
      sideboard: side,
    ));
    expect(code.length, lessThanOrEqualTo(DeckShare.maxLen),
        reason: '满编时 ${code.length} 字');
    final back = DeckShare.decode(code)!;
    expect(back.total, 60);
    expect(back.sideboard.values.fold(0, (a, b) => a + b), 10);
  });

  test('分享码：非法输入返回 null', () {
    expect(DeckShare.decode(''), isNull);
    expect(DeckShare.decode('随便一段话'), isNull);
    expect(DeckShare.decode('LYD1这不是base64'), isNull);
    expect(DeckShare.looksLike('LO-6665 x4'), isFalse);
    expect(DeckShare.looksLike('LYD1abcdefghijklmn'), isTrue);
  });

  test('剪贴板：从文本里抠卡号', () {
    final codes =
        ClipboardWatch.parseCardCodes('想要：LO-6665 x4, LO-5270 x3、lo4850、LO-3102-L');
    expect(codes, contains('LO-6665'));
    expect(codes, contains('LO-5270'));
    expect(codes, contains('LO-4850'));
    expect(codes, contains('LO-3102-L'));
    expect(codes.length, 4);

    expect(ClipboardWatch.parseCardCodes('没有卡号的一句话'), isEmpty);
    expect(ClipboardWatch.parseCardCodes('lyd1ABCDEFG'), isEmpty);
  });
}
