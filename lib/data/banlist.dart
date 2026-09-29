import 'dart:convert';

import 'package:flutter/services.dart';

import '../services/data_update_service.dart';

/// 官方禁限卡表（要求 L83-84）。
///
/// 数据来自官方「正誤訂正・禁止・制限カード一覧」页，由
/// `tools/fetch_banlist.py` 抓取后写进 `assets/data/banlist.json`，
/// 随 APK 打包 —— 所以**离线也能用**，联网只是为了更新。
///
/// 官方把限制分三类：
///
/// | 类别 | 官方原文 | 含义 |
/// |---|---|---|
/// | 使用禁止 | 全てのデッキに入れることができません | 任何卡组都不能放 |
/// | 構築制限 | 「同バージョン（同ブランド）のカードのみで構築されたデッキ」に限り入れることができる | 只能在**单一会社**构成的卡组里用 |
/// | 枚数制限 | 同名カードは N 枚まで | 张数上限（官方目前是「無し」）|
///
/// 另外用户还能**自己加**限制（[customForbidden] / [customCopyLimited]），
/// 用于店赛规则、群内自定规则等。
class BanList {
  BanList._();

  static final BanList instance = BanList._();

  /// 官方数据随包打包，离线可用
  static const String assetPath = 'assets/data/banlist.json';

  /// 官方页面上三个区块的标题。
  ///
  /// **放在这里而不是 banlist_page.dart** —— 这几个日文字符串是用来在
  /// 官方 HTML 里定位区块的锚点，一旦被界面多语言（L103）当成普通文案
  /// 翻译掉，就再也找不到区块了。本文件在 i18n 扫描的黑名单里，
  /// 放在这儿才安全。
  static const String anchorForbidden = '使用禁止カード';
  static const String anchorConstruction = '構築制限カード';
  static const String anchorCopyLimit = '枚数制限カード';

  /// 官方表：任何卡组都不能放
  final Set<String> forbidden = {};

  /// 官方表：只能在单一会社的卡组里用
  final Set<String> constructionLimited = {};

  /// 官方表：张数上限（卡号 → 最多几张）
  final Map<String, int> copyLimited = {};

  /// 用户自定义：禁止使用
  final Set<String> customForbidden = {};

  /// 用户自定义：张数上限
  final Map<String, int> customCopyLimited = {};

  /// 官方页面上的更新日期，例如 `2026/06/22`
  String updatedAt = '';

  /// 官方更新履历
  List<Map<String, String>> history = const [];

  /// 本地抓取时间
  String fetchedAt = '';

  bool _loaded = false;
  bool get loaded => _loaded;

  /// 生效的禁止集合 = 官方 + 自定义
  Set<String> get allForbidden => {...forbidden, ...customForbidden};

  /// 生效的张数上限 = 官方 + 自定义（自定义优先）
  Map<String, int> get allCopyLimited => {...copyLimited, ...customCopyLimited};

  bool get isEmpty =>
      forbidden.isEmpty &&
      constructionLimited.isEmpty &&
      copyLimited.isEmpty &&
      customForbidden.isEmpty &&
      customCopyLimited.isEmpty;

  /// 载入官方表 + 用户自定义表
  Future<void> load({Map<String, dynamic>? custom}) async {
    if (!_loaded) {
      try {
        // 热更优先：App 目录里的 banlist.json 覆盖内置
        final s = await DataUpdateService.instance.readString(
            'banlist.json', () => rootBundle.loadString(assetPath));
        if (s != null) _apply(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {
        // 打包时漏了或文件坏了：不阻塞 App，只是没有官方限制
      }
      _loaded = true;
    }
    if (custom != null) applyCustom(custom);
  }

  void _apply(Map<String, dynamic> j) {
    forbidden
      ..clear()
      ..addAll((j['forbidden'] as List? ?? const []).map((e) => '$e'));
    constructionLimited
      ..clear()
      ..addAll(
          (j['constructionLimited'] as List? ?? const []).map((e) => '$e'));
    copyLimited
      ..clear()
      ..addAll(((j['copyLimited'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', (v as num).toInt())));
    updatedAt = '${j['updatedAt'] ?? ''}';
    fetchedAt = '${j['fetchedAt'] ?? ''}';
    history = ((j['history'] as List?) ?? const [])
        .map((e) => Map<String, String>.from(e as Map))
        .toList();
  }

  /// 用**联网抓到的新表**覆盖官方部分（要求 L84：应用内更新）。
  /// 用户自定义的 [customForbidden] 不动。
  void applyOfficial(Map<String, dynamic> j) {
    forbidden
      ..clear()
      ..addAll((j['forbidden'] as List? ?? const []).map((e) => '$e'));
    constructionLimited
      ..clear()
      ..addAll(
          (j['constructionLimited'] as List? ?? const []).map((e) => '$e'));
    copyLimited
      ..clear()
      ..addAll(((j['copyLimited'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', (v as num).toInt())));
    if ('${j['updatedAt'] ?? ''}'.isNotEmpty) updatedAt = '${j['updatedAt']}';
    if ('${j['fetchedAt'] ?? ''}'.isNotEmpty) fetchedAt = '${j['fetchedAt']}';
    _loaded = true;
  }

  /// 套用用户自定义（来自 prefs / 备份）
  void applyCustom(Map<String, dynamic> j) {
    customForbidden
      ..clear()
      ..addAll((j['forbidden'] as List? ?? const []).map((e) => '$e'));
    customCopyLimited
      ..clear()
      ..addAll(((j['copyLimited'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', (v as num).toInt())));
  }

  /// 导出用户自定义（写进备份）
  Map<String, dynamic> exportCustom() => {
        'forbidden': customForbidden.toList()..sort(),
        'copyLimited': customCopyLimited,
      };

  // ---------------------------------------------------------------- 查询

  bool isForbidden(String code) => allForbidden.contains(code);

  bool isConstructionLimited(String code) => constructionLimited.contains(code);

  /// 该卡最多能放几张；没限制返回 null
  int? copyLimitOf(String code) => allCopyLimited[code];

  /// 卡组里有没有"只能在单一会社用"的卡；有就返回这些卡号
  List<String> limitedCardsIn(Iterable<String> codes) =>
      codes.where(isConstructionLimited).toList();

  /// 自定义：加/删禁止
  void toggleCustomForbidden(String code) {
    customForbidden.contains(code)
        ? customForbidden.remove(code)
        : customForbidden.add(code);
  }

  /// 自定义：设/清张数上限
  void setCustomCopyLimit(String code, int? n) {
    if (n == null || n <= 0) {
      customCopyLimited.remove(code);
    } else {
      customCopyLimited[code] = n;
    }
  }

  /// 给界面显示的一句话摘要
  String get summary {
    if (isEmpty) return '没有限制数据';
    final parts = <String>[];
    if (forbidden.isNotEmpty) parts.add('禁止 ${forbidden.length}');
    if (constructionLimited.isNotEmpty) {
      parts.add('构筑限制 ${constructionLimited.length}');
    }
    if (allCopyLimited.isNotEmpty) parts.add('张数限制 ${allCopyLimited.length}');
    if (customForbidden.isNotEmpty) {
      parts.add('自定义禁止 ${customForbidden.length}');
    }
    if (updatedAt.isNotEmpty) parts.add('官方 $updatedAt');
    return parts.join(' · ');
  }
}
