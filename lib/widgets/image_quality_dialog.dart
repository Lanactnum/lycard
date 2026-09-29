import 'package:flutter/material.dart';

import '../data/card_image_source.dart';

/// 下载/打印前确认图像来源；外挂原图包不存在时必须提示。
Future<bool> confirmCardImageQuality(
  BuildContext context,
  CardImageKind kind,
) async {
  if (kind == CardImageKind.originalPack) return true;
  final text = kind == CardImageKind.bundledCompressed
      ? '当前使用的是 App 内置压缩卡图。外挂原图包后才能下载/打印官方原图，仍要继续吗？'
      : '当前没有可用卡图，无法下载/打印。请先导入原图包。';
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(
            kind == CardImageKind.bundledCompressed ? '当前不是原图' : '没有可用卡图',
          ),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            if (kind == CardImageKind.bundledCompressed)
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('继续'),
              ),
          ],
        ),
      ) ??
      false;
}
