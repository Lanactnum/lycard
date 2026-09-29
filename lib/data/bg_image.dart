import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'storage_manager.dart';

/// 从自定义背景图里算一个代表色（要求 L109「从应用内自定义背景取色」）
Future<Color?> averageColorOfBg(String name) async {
  final p = await StorageManager.instance.bgPath(name);
  if (p == null) return null;
  try {
    final bytes = await File(p).readAsBytes();
    // 只解码成 32 像素宽，够算平均色了
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final frame = await codec.getNextFrame();
    final data =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return null;
    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final a = data.getUint8(i + 3);
      if (a < 16) continue;
      r += data.getUint8(i);
      g += data.getUint8(i + 1);
      b += data.getUint8(i + 2);
      n++;
    }
    if (n == 0) return null;
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  } catch (_) {
    return null;
  }
}
