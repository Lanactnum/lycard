import 'package:flutter/services.dart';

import 'deck_share.dart';

/// 剪贴板监听（要求 L73）
///
/// Flutter 拿不到系统级的"剪贴板变化"回调（那是后台服务的活），
/// 所以用主流做法：**App 回到前台时检查一次剪贴板**，认出两种情况：
///   · 构筑分享码（LYD1…）→ 问要不要导入
///   · 一堆卡号（`LO-6665 x4, LO-5270 x3`）→ 浮窗列出这些卡
class ClipboardWatch {
  ClipboardWatch._();

  /// 已经提示过的内容：避免每次切回前台都弹同一个
  static String? _handled;

  static void reset() => _handled = null;

  /// 检查剪贴板，返回要处理的内容；没有新东西就返回 null。
  /// [enabled] 为 false 时（设置里关掉了）直接跳过。
  static Future<ClipboardHit?> check({required bool enabled}) async {
    if (!enabled) return null;
    try {
      final d = await Clipboard.getData(Clipboard.kTextPlain);
      final t = (d?.text ?? '').trim();
      if (t.isEmpty || t.length > 20000) return null;
      if (t == _handled) return null;

      if (DeckShare.looksLike(t)) {
        _handled = t;
        return ClipboardHit(text: t, kind: HitKind.deckShare, codes: const []);
      }
      final codes = parseCardCodes(t);
      if (codes.isEmpty) return null;
      _handled = t;
      return ClipboardHit(text: t, kind: HitKind.cardCodes, codes: codes);
    } catch (_) {
      return null;
    }
  }

  /// 从任意文本里抠出卡号：`LO-6665`、`lo6665`、`LO-6665-L` 都认
  static List<String> parseCardCodes(String text) {
    final out = <String>[];
    final re = RegExp(r'LO-?(\d{3,5})(?:-([KSL]))?', caseSensitive: false);
    for (final m in re.allMatches(text.toUpperCase())) {
      final code = 'LO-${m.group(1)}${m.group(2) == null ? '' : '-${m.group(2)}'}';
      if (!out.contains(code)) out.add(code);
    }
    return out;
  }
}

enum HitKind { deckShare, cardCodes }

class ClipboardHit {
  const ClipboardHit({
    required this.text,
    required this.kind,
    required this.codes,
  });

  final String text;
  final HitKind kind;
  final List<String> codes;
}
