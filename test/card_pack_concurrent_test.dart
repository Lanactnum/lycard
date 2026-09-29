import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_pack.dart';
import 'package:flutter/foundation.dart';

/// 并发读图的回归测试。
///
/// 症状：收藏页展开一个作品，只有**第一张**卡面显示得出来，其余全变占位符。
/// 原因：CardPack 共用一个 RandomAccessFile，`setPosition` 和 `read` 是两步，
/// 多个图片同时加载时互相插队 → 读到的字节错位 → 解码失败 → 走占位符。
///
/// 注意：真实文件 I/O 必须包在 tester.runAsync 里，
/// 否则 testWidgets 的假异步时钟会让 Future 永远不完成。
void main() {
  const packPath = r'D:\LyceeApp\release\lycee_cards.pack';
  const cardsJson = r'D:\LyceeApp\assets\data\cards_app.json';

  testWidgets('一次并发读一整屏卡图，字节不能串', (tester) async {
    await tester.runAsync(() async {
      if (!File(packPath).existsSync() || !File(cardsJson).existsSync()) {
        // ignore: avoid_print
        debugPrint('跳过：数据包或卡表不存在');
        return;
      }

      // 取同一作品下的 24 张（就是一屏会同时加载的情况）
      final cards =
          jsonDecode(File(cardsJson).readAsStringSync()) as List<dynamic>;
      final target = <String>[];
      String? series;
      for (final c in cards) {
        final m = c as Map<String, dynamic>;
        final s = m['series'] as String?;
        if (s == null || s.isEmpty) continue;
        series ??= s;
        if (s != series) continue;
        if (m['name'] == null && m['name_zh'] == null) continue;
        target.add('${m['code']}');
        if (target.length >= 24) break;
      }
      // ignore: avoid_print
      debugPrint('测试作品: $series  取卡 ${target.length} 张');

      final pack = CardPack.instance;
      expect(await pack.openFile(packPath), isTrue);

      // ① 并发读一整屏（就是界面的行为）
      final concurrent = await Future.wait(target.map(pack.bytes));

      // ② 关掉重开清空缓存，再顺序读一遍当基准
      await pack.close();
      expect(await pack.openFile(packPath), isTrue);
      final sequential = <String, List<int>>{};
      for (final code in target) {
        final b = await pack.bytes(code);
        expect(b, isNotNull, reason: '$code 顺序读就失败了');
        sequential[code] = b!;
      }

      // ③ 逐个比对
      var bad = 0;
      for (var i = 0; i < target.length; i++) {
        final code = target[i];
        final got = concurrent[i];
        final want = sequential[code]!;
        if (got == null) {
          // ignore: avoid_print
          debugPrint('✗ $code 并发读到 null');
          bad++;
          continue;
        }
        final sameLen = got.length == want.length;
        final sameHead = got.length >= 4 &&
            got[0] == 0x89 &&
            got[1] == 0x50 &&
            got[2] == 0x4E &&
            got[3] == 0x47;
        final sameBytes = sameLen && _eq(got, want);
        if (!(sameLen && sameHead && sameBytes)) {
          // ignore: avoid_print
          debugPrint('✗ $code 并发 ${got.length} 字节 / 顺序 ${want.length} 字节 '
              '头对=$sameHead 内容对=$sameBytes');
          bad++;
        }
      }
      // ignore: avoid_print
      debugPrint('并发读 ${target.length} 张，异常 $bad 张');

      expect(bad, 0, reason: '并发读图串数据了（第一张之后全错）');

      // ④ 更进一步：并发把一整屏「读出来 + 真解码」，必须张张成图
      // 注意：官方图里有 34 张尺寸不是整 372x520（274x381 / 373x520 / 372x519 等），
      // 属于原始素材本身如此，所以这里只校验「解出来是一张正常的卡图」。
      await pack.close();
      expect(await pack.openFile(packPath), isTrue);
      final dims = <String, String>{};
      final decoded = await Future.wait(target.map((code) async {
        final b = await pack.bytes(code);
        if (b == null) return false;
        final codec = await ui.instantiateImageCodec(b);
        final frame = await codec.getNextFrame();
        final w = frame.image.width;
        final h = frame.image.height;
        dims[code] = '$w x $h';
        return w >= 250 && w <= 400 && h >= 350 && h <= 550;
      }));
      final goodCount = decoded.where((e) => e).length;
      // ignore: avoid_print
      debugPrint('并发读+解码 ${target.length} 张，成功 $goodCount 张');
      // ignore: avoid_print
      debugPrint('尺寸样例: ${dims.entries.take(4).map((e) => '${e.key}=${e.value}').join(', ')}');
      expect(goodCount, target.length, reason: '有卡图没能解码成正常卡图');

      await pack.close();
    });
  });
}

bool _eq(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
