import 'package:http/http.dart' as http;

import 'deck_share.dart';
import '../l10n/l10n.dart';

/// 官方卡组链接的识别与解析。
///
/// 官方有两种链接形态，短链会 301 跳到长链：
///
/// | 形态 | 例子 |
/// |---|---|
/// | 短链 | `https://lyc.ee/d200009005189` |
/// | 长链 | `https://lycee-tcg.com/d/?d=200009005189` |
///
/// 卡组页是服务端渲染的 HTML，里面有两处可用数据：
///
/// 1. 卡表 `<td>1枚</td><td>LO-0691</td>` —— 卡号是**完整**卡号
///    （异画 `LO-2690-K` 这种后缀也在），优先用它。
/// 2. 「このデッキから新しいデッキを作る」链接里的 `deckline=1691:1,0701:4,`
///    —— 只有 4 位数字，异画后缀会丢，所以只作兜底。
///
/// 官方页不暴露「主战卡」，所以导入后的 [DeckData.mainCardCode] 为空，
/// 需要玩家自己补。
class OfficialDeck {
  OfficialDeck._();

  /// 官方短链域名
  static const String shortHost = 'lyc.ee';

  /// 官方正式域名
  static const String longHost = 'lycee-tcg.com';

  /// 抓取用的地址（统一走长链；短链会 301，直接请求长链少一跳）
  static Uri fetchUrl(String id) =>
      Uri.parse('https://$longHost/d/?d=$id');

  /// 是不是官方卡组链接
  static bool looksLike(String text) => deckId(text) != null;

  /// 从链接里取出卡组 ID（12 位左右的数字）；不是官方链接返回 null
  static String? deckId(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    // 短链：https://lyc.ee/d200009005189
    final short = RegExp(r'lyc\.ee/d(\d{6,20})').firstMatch(t);
    if (short != null) return short.group(1);
    // 长链：https://lycee-tcg.com/d/?d=200009005189（?d= 也可能写成 ?d=）
    final long = RegExp(r'lycee-tcg\.com/d/?\?(?:[^#\s]*&)?d=(\d{6,20})')
        .firstMatch(t);
    if (long != null) return long.group(1);
    // 用户可能只粘了一串数字 ID
    if (RegExp(r'^\d{6,20}$').hasMatch(t)) return t;
    return null;
  }

  /// 抓取并解析官方卡组；失败返回 null 并给出 [error]
  static Future<({DeckData? deck, String? error})> fetch(
    String linkOrId, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final id = deckId(linkOrId);
    if (id == null) {
      return (deck: null, error: tr('这不像是官方卡组链接'));
    }
    try {
      final res = await http
          .get(fetchUrl(id), headers: const {'Accept': 'text/html'})
          .timeout(timeout);
      if (res.statusCode != 200) {
        return (deck: null, error: tr('官方页面返回 HTTP {0}', ['${res.statusCode}']));
      }
      // 官方页面用 UTF-8 之外的编码时按 latin1 兜底，避免解析直接抛异常
      String html;
      try {
        html = res.body;
      } catch (_) {
        html = String.fromCharCodes(res.bodyBytes);
      }
      final deck = parse(html);
      if (deck == null) {
        return (deck: null, error: tr('没能从官方页面里读出卡表'));
      }
      return (deck: deck, error: null);
    } catch (e) {
      return (deck: null, error: tr('抓取失败：{0}', ['$e']));
    }
  }

  /// 解析官方卡组页 HTML；没有卡表返回 null
  static DeckData? parse(String html) {
    if (html.isEmpty) return null;
    final name = _deckName(html);
    final cards = _cardsFromTable(html);
    if (cards.isEmpty) {
      cards.addAll(_cardsFromDeckLine(html));
    }
    if (cards.isEmpty) return null;
    return DeckData(
      name: name,
      mainCardCode: '',
      formatIndex: 0,
      intro: '',
      cards: cards,
      sideboard: const {},
    );
  }

  static String _deckName(String html) {
    // 「デッキ名」那一行最准
    final row = RegExp(r'<th[^>]*>\s*デッキ名\s*</th>\s*<td>(.*?)</td>',
            dotAll: true)
        .firstMatch(html);
    if (row != null) {
      final v = _plain(row.group(1)!);
      if (v.isNotEmpty) return v;
    }
    final h2 = RegExp(r'<h2>(.*?)</h2>', dotAll: true).firstMatch(html);
    if (h2 != null) return _plain(h2.group(1)!);
    return '';
  }

  /// `<td>1枚</td><td>LO-0691</td>` —— 唯一可靠拿到异画后缀的方式
  static Map<String, int> _cardsFromTable(String html) {
    final out = <String, int>{};
    final re = RegExp(
      r'<td>\s*(\d+)\s*枚\s*</td>\s*<td>\s*([A-Za-z]{1,4}-\d{3,6}[A-Za-z0-9\-]*)\s*</td>',
    );
    for (final m in re.allMatches(html)) {
      final n = int.tryParse(m.group(1)!);
      final code = m.group(2)!;
      if (n == null || n <= 0) continue;
      out[code] = (out[code] ?? 0) + n;
    }
    return out;
  }

  /// 兜底：`deckline=1691:1,0701:4,` → LO-1691 / LO-0701
  static Map<String, int> _cardsFromDeckLine(String html) {
    final out = <String, int>{};
    final m = RegExp(r'deckline=([^"&\x27]+)').firstMatch(html);
    if (m == null) return out;
    for (final part in m.group(1)!.split(',')) {
      final i = part.indexOf(':');
      if (i <= 0) continue;
      final numPart = part.substring(0, i).trim();
      final qtyPart = part.substring(i + 1).trim();
      if (!RegExp(r'^\d+$').hasMatch(numPart)) continue;
      final qty = int.tryParse(qtyPart);
      if (qty == null || qty <= 0) continue;
      // deckline 里的编号是纯数字，补成 4 位再拼 LO-
      final code = 'LO-${numPart.padLeft(4, '0')}';
      out[code] = (out[code] ?? 0) + qty;
    }
    return out;
  }

  /// 去掉标签、压掉空白
  static String _plain(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
