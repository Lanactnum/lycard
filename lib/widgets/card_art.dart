import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/card_pack.dart';
import '../data/card_repository.dart';
import '../data/storage_manager.dart';
import '../models/lycee_card.dart';
import '../l10n/l10n.dart';

/// 从数据包里读图的 ImageProvider（能被 Flutter 的图片缓存管理）
class PackImage extends ImageProvider<PackImage> {
  const PackImage(this.code, {this.scale = 1.0});

  final String code;
  final double scale;

  @override
  Future<PackImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<PackImage>(this);

  @override
  ImageStreamCompleter loadImage(PackImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _codec(key, decode),
      scale: key.scale,
    );
  }

  Future<ui.Codec> _codec(PackImage key, ImageDecoderCallback decode) async {
    final bytes = await CardPack.instance.bytes(key.code);
    if (bytes == null) {
      debugPrint('数据包里读不到 ${key.code}（会回落）');
      throw StateError(tr('数据包里没有 {0}', [key.code]));
    }
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      return await decode(buffer);
    } catch (e) {
      debugPrint('解码失败 ${key.code}（${bytes.length} 字节）: $e');
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PackImage && other.code == code && other.scale == scale;

  @override
  int get hashCode => Object.hash(code, scale);

  @override
  String toString() => 'PackImage("$code")';
}

/// 卡面：2:3 比例。
///
/// 取图顺序：
///   1. 卡图数据包（离线，官方 PNG 原图）
///   2. App 内置 WebP 压缩图（离线展示）
///   3. 占位

class CardArt extends StatelessWidget {
  const CardArt({super.key, required this.card, this.showName = true});

  final LyceeCard card;
  final bool showName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pack = CardPack.instance;
    return AspectRatio(
      aspectRatio: 372 / 520,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: (CardRepository.instance.editOf(card.code)?.imageFile) != null
              ? _CustomArt(
                  name: CardRepository.instance.editOf(card.code)!.imageFile!,
                )
              : pack.ready && pack.has(card.code)
              ? Image(
                  image: ResizeImage(
                    PackImage(card.code),
                    width: 300,
                    allowUpscaling: false,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (c, e, s) => _asset(context),
                )
              : _asset(context),
        ),
      ),
    );
  }

  Widget _asset(BuildContext context) => Image.asset(
    'assets/cards/${card.code}.webp',
    fit: BoxFit.cover,
    filterQuality: FilterQuality.medium,
    cacheWidth: 300,
    gaplessPlayback: true,
    errorBuilder: (c, e, s) {
      debugPrint('卡图回落(asset失败) ${card.code}: $e');
      return _placeholder(context);
    },
  );

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: scheme.onSurfaceVariant,
          ),
          if (showName) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                card.displayName,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ),
            Text(
              card.code,
              style: TextStyle(
                fontSize: 10,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 用户换过的卡面（存在 App 目录里的图片）
class _CustomArt extends StatelessWidget {
  const _CustomArt({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: StorageManager.instance.cardImagePath(name),
      builder: (c, s) {
        final p = s.data;
        if (p == null) {
          return Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Theme.of(context).colorScheme.outline,
            ),
          );
        }
        return Image.file(File(p), fit: BoxFit.cover);
      },
    );
  }
}

/// 给别处用：拿到一张卡图的原始字节（数据包优先）
Future<Uint8List?> cardBytes(String code) async {
  final pack = CardPack.instance;
  if (pack.ready) {
    final b = await pack.bytes(code);
    if (b != null) return b;
  }
  return null;
}
