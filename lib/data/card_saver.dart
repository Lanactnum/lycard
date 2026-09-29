import 'dart:typed_data';

import 'package:gal/gal.dart';

import 'card_image_source.dart';

/// 卡图保存：把**原图 PNG** 存到系统相册。
///
/// 图片来源优先顺序：卡图数据包 → 打包在 App 里的资源。
/// 原样写出，不重新编码——相册里拿到的就是官方原图，文件名用卡号。
class CardSaver {
  CardSaver._();
  static final CardSaver instance = CardSaver._();

  Future<bool> hasAccess() async {
    try {
      return await Gal.hasAccess();
    } catch (_) {
      return false;
    }
  }

  Future<bool> requestAccess() async {
    try {
      return await Gal.requestAccess();
    } catch (_) {
      return false;
    }
  }

  Future<CardImageData> image(String code) =>
      CardImageSource.instance.load(code);

  /// 保存单张卡图；调用方负责在非原图时先向用户提示。
  Future<bool> save(String code) async {
    try {
      final data = await image(code);
      if (!data.isUsable) return false;
      await Gal.putImageBytes(data.bytes!, name: code);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 保存任意 PNG 字节到相册（导出分享二维码等用）
  Future<bool> savePngBytes(Uint8List bytes, {String name = 'lycard'}) async {
    try {
      await Gal.putImageBytes(bytes, name: name);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 批量保存，返回 (成功数, 失败卡号)
  Future<(int, List<String>)> saveAll(
    List<String> codes, {
    void Function(int done, int total)? onProgress,
  }) async {
    var ok = 0;
    final failed = <String>[];
    for (var i = 0; i < codes.length; i++) {
      if (await save(codes[i])) {
        ok++;
      } else {
        failed.add(codes[i]);
      }
      onProgress?.call(i + 1, codes.length);
    }
    return (ok, failed);
  }
}
