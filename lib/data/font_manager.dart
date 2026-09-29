import 'dart:io';

import 'package:flutter/services.dart';

/// 自定义字体（要求 L105）
///
/// ttf / otf 直接能加载；ttc 是字体集合，Flutter 只会用到第一个面，
/// 有些 ttc 会加载失败——设置页里会提示。
class FontManager {
  FontManager._();

  /// 自定义字体统一用这个族名挂到主题上
  static const String family = 'lycard-custom';

  /// 已经成功挂上的字体文件（空 = 用系统默认）
  static String loadedFile = '';

  /// 加载一个字体文件；成功返回 true
  static Future<bool> load(String path, {String familyName = family}) async {
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) return false;
      final loader = FontLoader(familyName)
        ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
      await loader.load();
      loadedFile = path;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 是否已经挂上自定义字体
  static bool get ready => loadedFile.isNotEmpty;
}
