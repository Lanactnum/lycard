import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/widgets/bg_crop_page.dart';

/// 背景裁剪的坐标换算（要求 L117 的「裁剪」）。
///
/// 这块是纯数学，**算错了用户一眼就能看出来**（裁出来的位置偏了），
/// 但偏偏最容易写错 —— 所以把反推逻辑提成顶层纯函数单独测，
/// 不依赖真实渲染。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('cropFrameOf：裁剪框尺寸', () {
    test('跟随屏幕比例时，框不会超出可用区域', () {
      const view = Size(400, 800);
      final f = cropFrameOf(view, 0);
      expect(f.width, lessThanOrEqualTo(view.width));
      expect(f.height, lessThanOrEqualTo(view.height - 180 + 0.01));
      // 居中
      expect(f.center.dx, closeTo(200, 0.01));
      expect(f.center.dy, closeTo(400, 0.01));
      // 跟随屏幕 → 比例等于屏幕比例
      expect(f.width / f.height, closeTo(400 / 800, 0.01));
    });

    test('指定比例时宽高比正确', () {
      const view = Size(400, 800);
      for (final r in [1.0, 3 / 4, 4 / 3, 9 / 16, 16 / 9]) {
        final f = cropFrameOf(view, r);
        expect(f.width / f.height, closeTo(r, 0.01), reason: '比例 $r 不对');
      }
    });

    test('竖图屏幕 + 横比例：宽度成为约束', () {
      const view = Size(400, 800);
      final f = cropFrameOf(view, 16 / 9);
      expect(f.width, closeTo(372, 0.01)); // 顶到最大宽
      expect(f.height, closeTo(372 / (16 / 9), 0.01));
    });
  });

  group('cropRectOf：反推要裁原图的哪一块', () {
    // 1000×2000 的原图，铺在 400×800 的屏幕上
    const img = Size(1000, 2000);
    const view = Size(400, 800);

    test('图片正好盖住框时 → 裁出整张图', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img);
      // 居中摆放
      final off = Offset(
        frame.center.dx - img.width * s / 2,
        frame.center.dy - img.height * s / 2,
      );
      final rect = cropRectOf(frame, off, s, img);
      expect(rect.left, closeTo(0, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      expect(rect.width, closeTo(img.width, 0.01));
      expect(rect.height, closeTo(img.height, 0.01));
    });

    test('放大 2 倍、图片贴左上 → 裁左上那一块', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img) * 2;
      // 贴左上：offset = 框的左上角
      final off = clampImageOffset(
          Offset(frame.left, frame.top), s, frame, img);
      final rect = cropRectOf(frame, off, s, img);
      expect(rect.left, closeTo(0, 0.01));
      expect(rect.top, closeTo(0, 0.01));
      // 放大 2 倍 → 看到的范围是原来的一半
      expect(rect.width, closeTo(img.width / 2, 0.01));
      expect(rect.height, closeTo(img.height / 2, 0.01));
    });

    test('放大 2 倍、图片贴右下 → 裁右下那一块', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img) * 2;
      // 贴右下：offset = 框的右下角减去图片尺寸
      final off = clampImageOffset(
        Offset(frame.right - img.width * s, frame.bottom - img.height * s),
        s,
        frame,
        img,
      );
      final rect = cropRectOf(frame, off, s, img);
      expect(rect.right, closeTo(img.width, 0.01));
      expect(rect.bottom, closeTo(img.height, 0.01));
      expect(rect.width, closeTo(img.width / 2, 0.01));
      expect(rect.height, closeTo(img.height / 2, 0.01));
    });

    test('结果永远不越出图片边界', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img) * 3;
      // 故意给一个越界的 offset
      final rect = cropRectOf(frame, const Offset(-9999, -9999), s, img);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(img.width));
      expect(rect.bottom, lessThanOrEqualTo(img.height));
    });
  });

  group('clampImageOffset：不许把图片拖到框内露白', () {
    const img = Size(1000, 2000);
    const view = Size(400, 800);

    test('往左上拖过头 → 停在刚好盖住框的位置', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img);
      final off = clampImageOffset(
          const Offset(-9999, -9999), s, frame, img);
      // 图片右下角不能越过框的右下角
      expect(off.dx + img.width * s, greaterThanOrEqualTo(frame.right - 0.01));
      expect(off.dy + img.height * s, greaterThanOrEqualTo(frame.bottom - 0.01));
    });

    test('往右下拖过头 → 停在框的左上角', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img);
      final off = clampImageOffset(const Offset(9999, 9999), s, frame, img);
      expect(off.dx, closeTo(frame.left, 0.01));
      expect(off.dy, closeTo(frame.top, 0.01));
    });

    test('框内的范围内可以自由拖动', () {
      final frame = cropFrameOf(view, 0);
      final s = coverScaleOf(frame, img) * 2;
      // 一个合法范围内的位置应保持不变
      final want = Offset(frame.left - 10, frame.top - 20);
      final off = clampImageOffset(want, s, frame, img);
      expect(off.dx, closeTo(want.dx, 0.01));
      expect(off.dy, closeTo(want.dy, 0.01));
    });
  });

  group('cropImageToPng：真的裁到了那一块', () {
    /// 造一张四象限纯色图：左上红、右上绿、左下蓝、右下白
    Future<ui.Image> quadImage() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const r = Rect.fromLTWH(0, 0, 100, 100);
      canvas.drawRect(r, Paint()..color = const Color(0xFFFF0000));
      canvas.drawRect(r.shift(const Offset(100, 0)),
          Paint()..color = const Color(0xFF00FF00));
      canvas.drawRect(r.shift(const Offset(0, 100)),
          Paint()..color = const Color(0xFF0000FF));
      canvas.drawRect(r.shift(const Offset(100, 100)),
          Paint()..color = const Color(0xFFFFFFFF));
      return recorder.endRecording().toImage(200, 200);
    }

    /// 解 PNG 并取某点的 RGB
    Future<List<int>> pixelAt(Uint8List png, int x, int y) async {
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data =
          await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final i = (y * img.width + x) * 4;
      return [
        data!.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      ];
    }

    test('裁左上象限 → 得到红色', () async {
      final img = await quadImage();
      final png =
          await cropImageToPng(img, const Rect.fromLTWH(0, 0, 100, 100));
      expect(png, isNotNull);
      expect(await pixelAt(png!, 50, 50), [255, 0, 0]);
    });

    test('裁右下象限 → 得到白色', () async {
      final img = await quadImage();
      final png = await cropImageToPng(
          img, const Rect.fromLTWH(100, 100, 100, 100));
      expect(png, isNotNull);
      expect(await pixelAt(png!, 50, 50), [255, 255, 255]);
    });

    test('裁中间一条 → 左右各半（验证不是整张照搬）', () async {
      final img = await quadImage();
      // 横跨左红右绿的中间横条
      final png = await cropImageToPng(
          img, const Rect.fromLTWH(50, 40, 100, 20));
      expect(png, isNotNull);
      final codec = await ui.instantiateImageCodec(png!);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 100);
      expect(frame.image.height, 20);
      // 左端红、右端绿
      expect(await pixelAt(png, 10, 10), [255, 0, 0]);
      expect(await pixelAt(png, 90, 10), [0, 255, 0]);
    });

    test('区域太小时返回 null（不生成垃圾图）', () async {
      final img = await quadImage();
      expect(await cropImageToPng(img, const Rect.fromLTWH(0, 0, 4, 4)),
          isNull);
    });
  });

  group('页面能渲染', () {
    testWidgets('裁剪页加载图片并画出裁剪框', (tester) async {
      // 造一张真 PNG 写到临时文件
      late String path;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(const Rect.fromLTWH(0, 0, 300, 600),
            Paint()..color = const Color(0xFF3366FF));
        final img = await recorder.endRecording().toImage(300, 600);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        final f = File(
            '${Directory.systemTemp.path}/lycard_crop_test_${DateTime.now().microsecondsSinceEpoch}.png');
        await f.writeAsBytes(bytes);
        path = f.path;
      });

      await tester.pumpWidget(
        MaterialApp(home: BgCropPage(imagePath: path)),
      );
      // `_load()` 里有多层 await（读文件 → 解码 → 可能旋转），
      // 每层都要「真实时间推进 + fake zone 推进」各来一次才走得完。
      // 只做一次 runAsync+pump 会停在中间，页面还显示着 loading。
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 150)));
        await tester.pump();
      }

      expect(find.text('裁剪背景'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      expect(find.text('复位'), findsOneWidget);
      // 比例选项都在
      for (final k in ['跟随屏幕', '1:1', '9:16', '16:9']) {
        expect(find.text(k), findsOneWidget, reason: '缺比例选项 $k');
      }
      expect(find.text('这张背景图读不出来'), findsNothing);

      try {
        File(path).deleteSync();
      } catch (_) {}
    });

    testWidgets('图片读不出来时给出提示而不是崩掉', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BgCropPage(imagePath: '/no/such/file.png')),
      );
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 400)));
      await tester.pump();
      expect(find.text('这张背景图读不出来'), findsOneWidget);
    });
  });
}
