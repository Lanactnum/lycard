import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_pack.dart';
import 'package:flutter/foundation.dart';

/// 数据包格式的硬验证：直接拿真实的 lycee_cards.pack 跑一遍
/// （用的就是 App 里那套解析代码，不是另写一份）
///
/// 注意：真实文件 I/O 必须包在 tester.runAsync 里。
void main() {
  testWidgets('真实数据包能被 App 的解析代码读出来', (tester) async {
    await tester.runAsync(() async {
      const p = r'D:\LyceeApp\release\lycee_cards.pack';
      if (!File(p).existsSync()) {
        // ignore: avoid_print
        debugPrint('跳过：$p 不存在');
        return;
      }

      final pack = CardPack.instance;
      final ok = await pack.openFile(p);
      expect(ok, isTrue, reason: '数据包应该能打开');
      // ignore: avoid_print
      debugPrint('挂载成功：${pack.count} 张原图');

      expect(pack.count, 9952, reason: '卡图张数应当与卡片数一致');
      expect(pack.ready, isTrue);

      // 逐字节校验：随便挑几张，确认头部是 PNG、结尾是 IEND
      for (final code in ['LO-0001', 'LO-1234', 'LO-6085-S', 'LO-6281']) {
        final b = await pack.bytes(code);
        expect(b, isNotNull, reason: '$code 应该读得到');
        final head = b!.sublist(0, 4);
        final tail = b.sublist(b.length - 8, b.length - 4);
        // ignore: avoid_print
        debugPrint('$code: ${b.length} 字节 头=$head 尾=$tail');
        expect(head, [0x89, 0x50, 0x4E, 0x47], reason: '$code 应当是 PNG');
        expect(tail, [0x49, 0x45, 0x4E, 0x44], reason: '$code 应当以 IEND 结尾');
      }

      // 缓存命中：第二遍读同一张应当走内存
      final before = pack.hits;
      await pack.bytes('LO-0001');
      expect(pack.hits, greaterThan(before));

      // 真解码一遍：确认这堆字节确实能还原成 372x520 的图（界面就是这么用的）
      final raw = await pack.bytes('LO-0001');
      final codec = await ui.instantiateImageCodec(raw!);
      final frame = await codec.getNextFrame();
      // ignore: avoid_print
      debugPrint('解码成功：${frame.image.width} x ${frame.image.height}');
      expect(frame.image.width, 372);
      expect(frame.image.height, 520);

      await pack.close();
    });
  });
}
