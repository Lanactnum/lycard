import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'card_pack.dart';

enum CardImageKind { originalPack, bundledCompressed, unavailable }

class CardImageData {
  const CardImageData(this.kind, this.bytes);

  final CardImageKind kind;
  final Uint8List? bytes;

  bool get isOriginal => kind == CardImageKind.originalPack;
  bool get isUsable => bytes != null;
}

/// 统一解析卡图来源：外挂 PNG 原图优先，内置 WebP 仅用于展示/普通预览。
class CardImageSource {
  CardImageSource._();
  static final instance = CardImageSource._();

  Future<CardImageData> load(String code) async {
    final pack = CardPack.instance;
    if (pack.ready) {
      final original = await pack.bytes(code);
      if (original != null) {
        return CardImageData(CardImageKind.originalPack, original);
      }
    }
    try {
      final data = await rootBundle.load('assets/cards/$code.webp');
      return CardImageData(
        CardImageKind.bundledCompressed,
        data.buffer.asUint8List(),
      );
    } catch (_) {
      return const CardImageData(CardImageKind.unavailable, null);
    }
  }
}

/// 保存卡图时使用的结果。原图包不存在时，调用方必须先向用户告知内置图并非原图。
class CardImageLoader {
  CardImageLoader._();
  static final instance = CardImageLoader._();

  Future<CardImageData> load(String code) =>
      CardImageSource.instance.load(code);
}
