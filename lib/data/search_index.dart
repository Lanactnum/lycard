import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/data_update_service.dart';

/// 模糊搜索索引。
///
/// 归一化的工作全在数据侧做过（`tools/build_search_keys.py` → `search_keys.json.gz`），
/// 这里只负责：加载 + 把用户输入做同样的归一化 + 纯字符串匹配。
/// 所以 Dart 端不需要拼音/繁简转换之类的依赖，也不会拖慢启动。
///
/// 支持：简体 / 繁体 / 日文原文 / 日文罗马字 / 汉字拼音（全拼与首字母），
/// 并且忽略空格与各种符号。
class SearchIndex {
  SearchIndex._();

  static final SearchIndex instance = SearchIndex._();

  Map<String, String>? _keys;
  String? _cachedQuery;
  Set<String>? _cachedHits;

  bool get ready => _keys != null;
  int get count => _keys?.length ?? 0;

  Future<void> load() async {
    if (_keys != null) return;
    try {
      // 热更优先：App 目录里的 search_keys.json.gz 覆盖内置
      final data = await DataUpdateService.instance.readBytes(
          'search_keys.json.gz',
          () async =>
              (await rootBundle.load('assets/data/search_keys.json.gz'))
                  .buffer
                  .asUint8List());
      if (data == null) return;
      final raw = GZipCodec().decode(data);
      final m = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      _keys = m.map((k, v) => MapEntry(k, '$v'));
      debugPrint('lycard-搜索索引就绪：${_keys!.length} 张');
    } catch (e) {
      debugPrint('lycard-搜索索引载入失败：$e');
    }
  }

  /// 模糊匹配：返回命中的卡号集合。
  /// 返回 null 表示索引还没准备好（调用方退回原来的精确匹配）。
  Set<String>? match(String query) {
    final keys = _keys;
    if (keys == null) return null;
    final n = normalize(query);
    if (n.isEmpty) return null;
    if (_cachedQuery == n) return _cachedHits;
    final out = <String>{};
    for (final e in keys.entries) {
      if (e.value.contains(n)) out.add(e.key);
    }
    _cachedQuery = n;
    _cachedHits = out;
    return out;
  }
}

// ── 归一化（要和 tools/build_search_keys.py 保持一致）──

const Map<String, String> _yoon = {
  'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
  'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
  'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
  'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
  'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
  'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
  'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
  'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
  'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
  'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
  'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
};

const Map<String, String> _kana = {
  'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
  'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
  'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
  'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
  'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
  'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
  'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
  'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
  'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
  'わ': 'wa', 'を': 'o', 'ん': 'n',
  'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
  'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
  'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
  'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
  'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
  'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o',
  'っ': '', 'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo', 'ー': '',
  'ゔ': 'bu',
};

final RegExp _symbols = RegExp(
  r'''[\s\u3000・･·、。，,.\-—–_/／|｜:：;；!！?？'"“”‘’()（）''' 
  r'''\[\]【】{}｛｝~～^+=*#@$%&\\<>《》〈〉「」『』]''',
);

String _kataToHira(String s) {
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0x30A1 && r <= 0x30F6) {
      b.writeCharCode(r - 0x60);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

String kanaToRomaji(String s) {
  var t = _kataToHira(s);
  _yoon.forEach((k, v) => t = t.replaceAll(k, v));
  final b = StringBuffer();
  for (final ch in t.split('')) {
    b.write(_kana[ch] ?? ch);
  }
  return b.toString();
}

/// 把用户输入归一化：全角转半角、小写、假名转罗马字、去掉空格与符号
String normalize(String s) {
  if (s.isEmpty) return '';
  final b = StringBuffer();
  for (final r in s.runes) {
    if (r >= 0xFF01 && r <= 0xFF5E) {
      b.writeCharCode(r - 0xFEE0); // 全角 ASCII → 半角
    } else if (r == 0x3000) {
      b.write(' ');
    } else {
      b.writeCharCode(r);
    }
  }
  var t = b.toString().toLowerCase();
  t = kanaToRomaji(t);
  return t.replaceAll(_symbols, '');
}
