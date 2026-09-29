import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/backup.dart';
import 'package:lycee_app/data/storage_manager.dart';

/// 备份（要求 L15）：数据 + 用户自己的图片资源都要能带走、能恢复回来。
/// 这里用真实的临时目录跑完整往返，不用 mock。
void main() {
  late Directory root;
  late Directory photos;
  late Directory cards;
  late Directory bgs;
  late Directory fonts;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lycard_bak_');
    photos = Directory('${root.path}/photos')..createSync(recursive: true);
    cards = Directory('${root.path}/cards')..createSync(recursive: true);
    bgs = Directory('${root.path}/backgrounds')..createSync(recursive: true);
    fonts = Directory('${root.path}/fonts')..createSync(recursive: true);
    StorageManager.instance.useDirs(files: root);
  });

  tearDown(() {
    StorageManager.instance.useDirs();
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('打包 → 解包：数据字段一致', () async {
    final data = <String, dynamic>{
      'app': 'lycard',
      'decks': [
        {'id': 'd1', 'name': '测试构筑'}
      ],
      'owned': ['LO-0001', 'LO-0002'],
      'wish': [
        {'id': 'w1', 'code': 'LO-0003'}
      ],
      'settings': {'useZh': true},
    };

    final bytes = await Backup.pack(data);
    expect(bytes.length, greaterThan(0));
    // zip 魔数
    expect(bytes[0], 0x50);
    expect(bytes[1], 0x4B);

    final back = Backup.unpack(bytes);
    expect(back.isLegacyJson, isFalse);
    expect(back.data['app'], 'lycard');
    expect((back.data['decks'] as List).length, 1);
    expect((back.data['decks'] as List).first['name'], '测试构筑');
    expect((back.data['owned'] as List).length, 2);
    expect(back.data['settings']['useZh'], isTrue);
  });

  test('用户图片资源：实拍图 / 卡面 / 背景 / 字体都进备份', () async {
    final photo = Uint8List.fromList(List.generate(64, (i) => i));
    final art = Uint8List.fromList(List.generate(32, (i) => 255 - i));
    final bg = Uint8List.fromList(List.generate(16, (i) => i * 3));
    final font = Uint8List.fromList(List.generate(48, (i) => 7));

    File('${photos.path}/p1.jpg').writeAsBytesSync(photo);
    File('${cards.path}/c1.png').writeAsBytesSync(art);
    File('${bgs.path}/bg1.jpg').writeAsBytesSync(bg);
    File('${fonts.path}/font.ttf').writeAsBytesSync(font);

    final bytes = await Backup.pack({'app': 'lycard'});
    final back = Backup.unpack(bytes);

    expect(back.assetCount, 4, reason: '四个目录各一个文件');
    expect(back.assets.keys.any((k) => k.endsWith('photos/p1.jpg')), isTrue);
    expect(back.assets.keys.any((k) => k.endsWith('cards/c1.png')), isTrue);
    expect(back.assets.keys.any((k) => k.endsWith('backgrounds/bg1.jpg')), isTrue);
    expect(back.assets.keys.any((k) => k.endsWith('fonts/font.ttf')), isTrue);

    // 内容必须逐字节一致 —— 图片坏了等于没备份
    final gotPhoto = back.assets.entries
        .firstWhere((e) => e.key.endsWith('photos/p1.jpg'))
        .value;
    expect(gotPhoto, equals(photo));

    // 数据里会列出资源清单，方便以后排查
    expect((back.data['assets'] as List).length, 4);
  });

  test('恢复：资源写回目录，内容一致', () async {
    File('${photos.path}/p1.jpg').writeAsBytesSync([1, 2, 3, 4, 5]);
    File('${bgs.path}/bg1.jpg').writeAsBytesSync([9, 8, 7]);

    final bytes = await Backup.pack({'app': 'lycard'});

    // 清空，模拟"换了一台新手机"
    photos.deleteSync(recursive: true);
    bgs.deleteSync(recursive: true);

    final back = Backup.unpack(bytes);
    final counts = await Backup.restoreAssets(back.assets);

    expect(counts['photos'], 1);
    expect(counts['backgrounds'], 1);
    expect(File('${photos.path}/p1.jpg').readAsBytesSync(), equals([1, 2, 3, 4, 5]));
    expect(File('${bgs.path}/bg1.jpg').readAsBytesSync(), equals([9, 8, 7]));
  });

  test('卡图数据包不该进备份（那是官方卡图，3.9GB）', () async {
    File('${root.path}/lycee_cards.pack')
        .writeAsBytesSync(List.filled(1024, 0));
    final bytes = await Backup.pack({'app': 'lycard'});
    final back = Backup.unpack(bytes);
    expect(back.assets.keys.any((k) => k.contains('lycee_cards')), isFalse);
    // 备份应该很小（就一个 json）
    expect(bytes.length, lessThan(4096));
  });

  test('兼容老格式：单个 JSON 备份还能导入', () async {
    final legacy = utf8.encode(jsonEncode({
      'app': 'lycard',
      'decks': [
        {'id': 'old', 'name': '老备份的构筑'}
      ],
      'bgImageData': base64Encode([1, 2, 3]),
      'bgImageExt': 'jpg',
    }));

    final back = Backup.unpack(legacy);
    expect(back.isLegacyJson, isTrue, reason: '要能认出这是老格式');
    expect(back.assetCount, 0);
    expect((back.data['decks'] as List).first['name'], '老备份的构筑');
    expect(back.data['bgImageData'], isNotNull);
  });

  test('不是备份文件 → 明确报错，而不是静默成功', () async {
    final junk = utf8.encode('{"hello":"world"}');
    final back = Backup.unpack(junk);
    // 是合法 JSON 但没有 lycard 字段 → 交给 AppState.importData 去拒绝
    expect(back.data['app'], isNull);

    // 彻底不是 JSON 的：必须抛错
    expect(() => Backup.unpack(utf8.encode('这不是备份')),
        throwsA(isA<FormatException>()));
  });

  test('文件名带日期', () {
    final name = Backup.suggestedName(DateTime(2026, 9, 15));
    expect(name, 'lycard-backup-2026-09-15.zip');
  });
}
