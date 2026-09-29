import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/storage_manager.dart';
import 'package:flutter/foundation.dart';

/// 批次 2：分类清理 + 垃圾桶 15 天撤销
void main() {
  late Directory root;
  late Directory files;
  late Directory cache;
  late StorageManager sm;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lycard_store_');
    files = Directory('${root.path}/files')..createSync(recursive: true);
    cache = Directory('${root.path}/cache')..createSync(recursive: true);
    sm = StorageManager.instance;
    sm.useDirs(files: files, cache: cache);
  });

  tearDown(() {
    sm.useDirs(files: null, cache: null);
    try {
      root.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('扫描分类：数据包 / 备份 / 实拍图 / 临时缓存', () async {
    File('${files.path}/lycee_cards.pack')
        .writeAsBytesSync(List.filled(4096, 1));
    File('${files.path}/lycee_cards.pack.part')
        .writeAsBytesSync(List.filled(1024, 1));
    Directory('${files.path}/backups').createSync();
    File('${files.path}/backups/b.json').writeAsStringSync('{}');
    Directory('${files.path}/photos').createSync();
    File('${files.path}/photos/p.jpg').writeAsBytesSync(List.filled(2048, 1));
    File('${cache.path}/tmp.bin').writeAsBytesSync(List.filled(512, 1));

    final cats = await sm.scan();
    final byId = {for (final c in cats) c.id: c};

    // ignore: avoid_print
    debugPrint('分类：${cats.map((c) => '${c.label}=${c.sizeText}/${c.count}个').join('  ')}');

    expect(byId['pack']!.bytes, 5120);
    expect(byId['pack']!.count, 2);
    expect(byId['backup']!.bytes, greaterThan(0));
    expect(byId['photos']!.count, 1);
    expect(byId['temp']!.count, 1);
  });

  test('清理 → 进垃圾桶 → 撤销后文件回来', () async {
    final pack = File('${files.path}/lycee_cards.pack')
      ..writeAsBytesSync(List.filled(8192, 7));
    expect(pack.existsSync(), isTrue);

    final freed = await sm.clean(['pack']);
    // ignore: avoid_print
    debugPrint('清理释放 ${humanSize(freed)}');
    expect(freed, 8192);
    expect(pack.existsSync(), isFalse, reason: '原文件已被移走');

    final items = await sm.trash();
    expect(items.length, 1);
    expect(items.first.label, '卡图数据包');
    expect(items.first.bytes, 8192);
    expect(items.first.daysLeft, greaterThan(13), reason: '刚删的应剩 15 天左右');
    expect(items.first.expired, isFalse);

    final ok = await sm.restore(items.first.id);
    expect(ok, isTrue);
    expect(pack.existsSync(), isTrue, reason: '撤销后文件回到原位');
    expect(pack.lengthSync(), 8192);
    expect(await sm.trash(), isEmpty, reason: '恢复后垃圾桶记录消失');
  });

  test('保质期：超过 15 天的记录会被自动销毁', () async {
    File('${files.path}/lycee_cards.pack')
        .writeAsBytesSync(List.filled(1024, 1));
    await sm.clean(['pack']);

    // 手动把删除时间改成 16 天前（模拟过期）
    final trashDir = await sm.trashDir();
    final box = trashDir!.listSync().whereType<Directory>().first;
    final m = File('${box.path}/manifest.json');
    final old = DateTime.now().subtract(const Duration(days: 16));
    m.writeAsStringSync(m.readAsStringSync().replaceAll(
        RegExp(r'"deletedAt":"[^"]+"'), '"deletedAt":"${old.toIso8601String()}"'));

    final entries = await sm.trash();
    expect(entries.first.expired, isTrue);
    expect(entries.first.daysLeft, lessThanOrEqualTo(0));

    final n = await sm.purgeExpired();
    expect(n, 1);
    expect(await sm.trash(), isEmpty, reason: '过期条目被销毁');
  });

  test('清空垃圾桶 = 彻底销毁，不能撤销', () async {
    File('${files.path}/lycee_cards.pack')
        .writeAsBytesSync(List.filled(2048, 1));
    await sm.clean(['pack']);
    await sm.emptyTrash();
    expect(await sm.trash(), isEmpty);
    expect(File('${files.path}/lycee_cards.pack').existsSync(), isFalse);
    final freedAfter = (await sm.scan())
        .firstWhere((c) => c.id == 'pack')
        .bytes;
    expect(freedAfter, 0, reason: '彻底删掉后占用归零');
  });

  test('humanSize 显示', () {
    expect(humanSize(512), '512 B');
    expect(humanSize(2048), '2.0 KB');
    expect(humanSize(5 * 1024 * 1024), '5.0 MB');
    expect(humanSize(3 * 1024 * 1024 * 1024), '3.00 GB');
  });
}
