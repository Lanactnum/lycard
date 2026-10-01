import 'package:flutter/services.dart';

/// 拉起**系统安装器**装我们下好的 APK（Android 侧在 MainActivity 里实现）。
///
/// 全程留在应用内：不跳浏览器、不引导去「文件管理」找安装包。
class ApkInstaller {
  ApkInstaller._();

  static const MethodChannel _channel = MethodChannel('lycard/update');

  /// 有没有「安装未知应用」的权限。
  /// Android 8 起每个应用单独开关；之前版本恒为 true。
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到「安装未知应用」的系统设置页，开完就能装。
  static Future<bool> openInstallSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 本机**已安装的**那个 APK 在哪。
  ///
  /// 差分更新要拿它当输入（补丁只说「从它哪里复制哪一段」）。拿不到就返回 null，
  /// 调用方会退回整包下载 —— 差分是优化，不能因为它把更新搞失败。
  static Future<String?> apkPath() async {
    try {
      return await _channel.invokeMethod<String>('apkPath');
    } catch (_) {
      return null;
    }
  }

  /// 拉起系统安装器。false = 没拉起来（文件没了 / 没权限 / ROM 拦了）。
  static Future<bool> install(String path) async {
    try {
      return await _channel
              .invokeMethod<bool>('install', <String, dynamic>{'path': path}) ??
          false;
    } catch (_) {
      return false;
    }
  }
}
