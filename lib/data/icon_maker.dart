import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

/// 图标工坊（要求 L113：应用图标自定义 = 换图标**图片**）
///
/// Android 的应用图标必须是编译进包里的资源，运行时没法直接把任意图片塞进
/// 资源表。所以这里走两条能真正看到效果的路：
///   1. 生成一张做好遮罩的图标图 → 存相册 → 在桌面长按图标「编辑」选它
///      （小米 / HyperOS、大部分国产桌面都支持）
///   2. 用这张图 Pin 一个桌面快捷方式（Android 8+ 原生支持任意 bitmap 图标）
class IconMaker {
  IconMaker._();

  /// 把 [srcPath] 按 [mask] 做遮罩，输出 512×512 PNG 字节
  /// mask: circle 圆形 / round 圆角方形 / square 方形（填满，交给系统再裁）
  static Future<Uint8List?> make(
    String srcPath, {
    String mask = 'round',
  }) async {
    try {
      final raw = await File(srcPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final img = frame.image;

      const size = 512.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, Rect.fromLTWH(0, 0, size, size));

      // 图片按 cover 铺满整个画布
      final scale = size / (img.width < img.height ? img.width : img.height);
      final dw = img.width * scale;
      final dh = img.height * scale;
      final dst = Rect.fromLTWH((size - dw) / 2, (size - dh) / 2, dw, dh);

      if (mask != 'square') {
        final inset = size * 0.06;
        final box = Rect.fromLTWH(inset, inset, size - inset * 2, size - inset * 2);
        final path = Path();
        if (mask == 'circle') {
          path.addOval(box);
        } else {
          path.addRRect(RRect.fromRectAndRadius(box, Radius.circular(size * 0.24)));
        }
        canvas.clipPath(path);
      }

      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );

      final pic = rec.endRecording();
      final out = await pic.toImage(512, 512);
      final bd = await out.toByteData(format: ui.ImageByteFormat.png);
      pic.dispose();
      out.dispose();
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// 把生成的图标图存进相册
  static Future<bool> saveToGallery(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      await Gal.putImageBytes(bytes, name: 'lycard-icon');
      return true;
    } catch (_) {
      return false;
    }
  }
}
