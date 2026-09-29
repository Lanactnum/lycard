import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../services/data_update_service.dart';

/// 一条词条（基本能力 / 行动时机 / 使用限制）
class Keyword {
  const Keyword({
    required this.jp,
    required this.zh,
    required this.type,
    required this.cond,
    required this.desc,
  });

  final String jp;
  final String zh;
  final String type; // 使用型 / 诱发型 / 常时型 / 费用型 / 特殊型 / 时机 …
  final String cond; // 条件
  final String desc; // 效果说明

  /// 显示用的标题：中文（日文）。两者相同时不重复显示 ——
  /// 「切札」这类按用户要求保留原词的条目，zh 和 jp 会一样。
  String get label {
    if (zh.isEmpty) return jp;
    if (jp.isEmpty || zh == jp) return zh;
    return '$zh（$jp）';
  }

  factory Keyword.fromJson(Map<String, dynamic> j) => Keyword(
        jp: '${j['jp'] ?? ''}',
        zh: '${j['zh'] ?? ''}',
        type: '${j['type'] ?? ''}',
        cond: '${j['cond'] ?? ''}',
        desc: '${j['desc'] ?? ''}',
      );
}

/// 词条表：卡片效果里出现的「跳跃」「充能」这类词，点一下就能看含义。
///
/// 内容取自 LYCEE OVERTURE 官方规则页（基本能力 / 使用代偿与限制），
/// 中文为本项目自译。
class KeywordDb {
  KeywordDb._();
  static final KeywordDb instance = KeywordDb._();

  final Map<String, Keyword> _byToken = {};
  List<Keyword> _all = const [];
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<Keyword> get all => _all;

  Future<void> load() async {
    if (_loaded) return;
    try {
      // 热更优先
      final s = await DataUpdateService.instance.readString(
          'keywords.json', () => rootBundle.loadString('assets/data/keywords.json'));
      final raw = jsonDecode(s ?? '[]') as List<dynamic>;
      _all = raw
          .map((e) => Keyword.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      for (final k in _all) {
        _put(k.jp, k);
        _put(k.zh, k);
      }
    } catch (_) {
      _all = const [];
    }
    _loaded = true;
  }

  void _put(String token, Keyword k) {
    final t = normalize(token);
    if (t.isNotEmpty) _byToken[t] = k;
  }

  /// 去掉方括号里的参数部分与空白，方便比对
  static String normalize(String token) => token
      .split(':')
      .first
      .split('：')
      .first
      .replaceAll(RegExp(r'[\s\[\]［］]'), '')
      .trim();

  /// 按词条名查（日文或中文都行）
  Keyword? find(String token) => _byToken[normalize(token)];

  /// 在文本里找所有能识别的词条，返回 (起始, 结束, 词条)
  List<(int, int, Keyword)> scan(String text) {
    final out = <(int, int, Keyword)>[];
    // 方括号里的词条
    for (final m in RegExp(r'[\[［]([^\]］]+)[\]］]').allMatches(text)) {
      final k = find(m.group(1)!);
      if (k != null) out.add((m.start, m.end, k));
    }
    // 中文效果文本里经常不带方括号，就直接找词名
    for (final k in _all) {
      if (k.zh.isEmpty) continue;
      var from = 0;
      while (true) {
        final i = text.indexOf(k.zh, from);
        if (i < 0) break;
        final overlaps = out.any((e) => i < e.$2 && i + k.zh.length > e.$1);
        if (!overlaps) out.add((i, i + k.zh.length, k));
        from = i + k.zh.length;
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }
}
