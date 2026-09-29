import 'dart:convert';
import 'dart:io';
import '../l10n/l10n.dart';

/// 构筑分享码。
///
/// 格式：`LYD1` + base64url(gzip(文本)) —— 头部有 4 字符特征码，
/// 便于剪贴板监听/导入时一眼认出来。
///
/// 文本内容（分隔符 `|` 与 `,` 和 `:`，卡号里不会出现这三种）：
///   v1 | 名称 | 主战卡号 | 规则模式序号 | 简介 | 主卡组 code:qty,... | 备卡区 code:qty,...
///
/// 只带"构筑本身"（不含胜负记录/快照/心得），保证码足够短。
class DeckShare {
  DeckShare._();

  /// 特征码：导入/剪贴板识别用
  static const String prefix = 'LYD1';

  /// 要求：500 字以内（部分输入法剪贴板有字数限制）
  static const int maxLen = 500;

  /// 是不是一段构筑分享码
  static bool looksLike(String text) =>
      text.trimLeft().startsWith(prefix) && text.trim().length > 12;

  static String _esc(String s) =>
      s.replaceAll('|', ' ').replaceAll(',', ' ').replaceAll(':', ' ');

  /// 打包成分享码
  static String encode(DeckData d) {
    final sb = StringBuffer()
      ..write('v1|')
      ..write(_esc(d.name))
      ..write('|')
      ..write(d.mainCardCode)
      ..write('|')
      ..write(d.formatIndex)
      ..write('|')
      ..write(_esc(d.intro))
      ..write('|')
      ..write(d.cards.entries.map((e) => '${e.key}:${e.value}').join(','))
      ..write('|')
      ..write(d.sideboard.entries.map((e) => '${e.key}:${e.value}').join(','));
    final gz = GZipCodec(level: 9).encode(utf8.encode(sb.toString()));
    return prefix + base64Url.encode(gz).replaceAll('=', '');
  }

  /// 解析分享码；不是合法分享码返回 null
  static DeckData? decode(String text) {
    var t = text.trim();
    if (!t.startsWith(prefix)) return null;
    t = t.substring(prefix.length).replaceAll(RegExp(r'\s'), '');
    while (t.length % 4 != 0) {
      t += '=';
    }
    try {
      final raw = utf8.decode(GZipCodec().decode(base64Url.decode(t)));
      final parts = raw.split('|');
      if (parts.length < 7 || parts[0] != 'v1') return null;
      return DeckData(
        name: parts[1],
        mainCardCode: parts[2],
        formatIndex: int.tryParse(parts[3]) ?? 0,
        intro: parts[4],
        cards: _parseMap(parts[5]),
        sideboard: _parseMap(parts[6]),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<String, int> _parseMap(String s) {
    final out = <String, int>{};
    if (s.trim().isEmpty) return out;
    for (final part in s.split(',')) {
      final i = part.lastIndexOf(':');
      if (i <= 0) continue;
      final code = part.substring(0, i).trim();
      final n = int.tryParse(part.substring(i + 1).trim()) ?? 0;
      if (code.isNotEmpty && n > 0) out[code] = n;
    }
    return out;
  }
}

/// 分享码里承载的构筑数据（与 Deck 解耦，导入时由 AppState 生成新 id）
class DeckData {
  DeckData({
    required this.name,
    required this.mainCardCode,
    required this.formatIndex,
    required this.intro,
    required this.cards,
    required this.sideboard,
  });

  final String name;
  final String mainCardCode;
  final int formatIndex;
  final String intro;
  final Map<String, int> cards;
  final Map<String, int> sideboard;

  int get total => cards.values.fold(0, (a, b) => a + b);
}


/// 分享码的摘要（给"要不要导入"这种确认提示用）。
/// 解析失败时返回空名字 + 一句"识别不了"，让调用方自己决定怎么提示。
class DeckShareSummary {
  const DeckShareSummary(this.name, this.line);
  final String name;
  final String line;
}

DeckShareSummary deckSummaryFromShareCode(String raw) {
  final d = DeckShare.decode(raw);
  if (d == null) {
    return DeckShareSummary('', tr('分享码读取失败，可能是复制不完整'));
  }
  final side = d.sideboard.values.fold(0, (a, b) => a + b);
  final buf = StringBuffer(tr('主卡组 {0} 张', [d.total]));
  if (side > 0) buf.write(tr(' · 备卡区 {0} 张', [side]));
  if (d.mainCardCode.isNotEmpty) buf.write(tr(' · 主战卡 {0}', [d.mainCardCode]));
  return DeckShareSummary(d.name, buf.toString());
}
