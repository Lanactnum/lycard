import 'dart:io';

import 'package:flutter/services.dart';

/// 换应用图标（要求 L113）
///
/// Android 侧用 activity-alias 实现，同一时间只有一个 alias 启用。
/// 切换后系统可能需要几秒才刷新桌面图标，有时会把 App 关掉——正常现象。
class AppIcon {
  AppIcon._();

  static const MethodChannel _ch = MethodChannel('lycard/icon');

  /// 可选图标：key 与 manifest 里的 alias 对应
  static const Map<String, String> labels = {
    'blue': '蓝',
    'red': '红',
    'green': '绿',
    'purple': '紫',
    'orange': '橙',
    'dark': '暗',
  };

  static const Map<String, int> colors = {
    'blue': 0xFF3F7FBF,
    'red': 0xFFC62828,
    'green': 0xFF2E7D32,
    'purple': 0xFF7E57C2,
    'orange': 0xFFEF6C00,
    'dark': 0xFF37474F,
  };

  static Future<String> current() async {
    try {
      return await _ch.invokeMethod<String>('current') ?? 'blue';
    } catch (_) {
      return 'blue';
    }
  }

  /// 换应用图标图片（要求 L113）
  ///
  /// Android 的启动图标是编译期资源，运行时改不了，所以这里用「桌面快捷方式」
  /// 的方式：把用户选的图片 Pin 到桌面，图标就是那张图。
  static Future<bool> pinShortcut(String imagePath, String label) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _ch.invokeMethod<bool>('pinShortcut', {
            'path': imagePath,
            'label': label,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> set(String name) async {
    try {
      return await _ch.invokeMethod<bool>('set', {'name': name}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
