import 'dart:convert';
import '../l10n/l10n.dart';

/// Lycee Overture 一张卡的完整数据。
///
/// 卡种（kind）的中文名。唯一来源 —— 统计图、筛选面板、卡详情
/// 都从这里取，免得各写一份、有的地方漏翻变成日文。
///
/// 返回的是**中文常量**（不随界面语言变）：它同时被用作统计图的分组
/// key，跟着语言变会让分组错乱。界面要显示时在显示处套 tr()。
String? kKindZh(String? kind) => switch (kind) {
      'キャラクター' => tr('角色'),
      'イベント' => tr('事件'),
      'アイテム' => tr('道具'),
      'エリア' => tr('区域'),
      _ => kind,
    };

/// 中文名与中文效果是本 App 自译（术语表统一校订）。
class LyceeCard {
  const LyceeCard({
    required this.code,
    required this.nameJp,
    this.nameZh,
    this.effectZh,
    this.effectJp,
    this.color,
    this.cost,
    this.ex,
    this.ap,
    this.dp,
    this.sp,
    this.dmg,
    this.cardType,
    this.kind,
    this.limit,
    this.series,
    this.illustrator,
    this.rarity,
    this.releaseInfo,
    this.titleJp,
    this.isLeader = false,
    this.deckRestriction,
  });

  /// 复制一份并改掉部分字段（用户自定义覆盖 / 新建卡用）
  LyceeCard copyWith({
    String? code,
    String? nameJp,
    String? nameZh,
    String? effectZh,
    String? effectJp,
    String? color,
    String? cost,
    int? ex,
    int? ap,
    int? dp,
    int? sp,
    int? dmg,
    String? cardType,
    String? kind,
    String? limit,
    String? series,
    String? illustrator,
    String? rarity,
    String? releaseInfo,
    String? titleJp,
    bool? isLeader,
    String? deckRestriction,
  }) =>
      LyceeCard(
        code: code ?? this.code,
        nameJp: nameJp ?? this.nameJp,
        nameZh: nameZh ?? this.nameZh,
        effectZh: effectZh ?? this.effectZh,
        effectJp: effectJp ?? this.effectJp,
        color: color ?? this.color,
        cost: cost ?? this.cost,
        ex: ex ?? this.ex,
        ap: ap ?? this.ap,
        dp: dp ?? this.dp,
        sp: sp ?? this.sp,
        dmg: dmg ?? this.dmg,
        cardType: cardType ?? this.cardType,
        kind: kind ?? this.kind,
        limit: limit ?? this.limit,
        series: series ?? this.series,
        illustrator: illustrator ?? this.illustrator,
        rarity: rarity ?? this.rarity,
        releaseInfo: releaseInfo ?? this.releaseInfo,
        titleJp: titleJp ?? this.titleJp,
        isLeader: isLeader ?? this.isLeader,
        deckRestriction: deckRestriction ?? this.deckRestriction,
      );

  final String code; // 卡号，如 LO-6665 / LO-6665-A
  final String nameJp; // 日文原名
  final String? nameZh; // 自译中文名
  final String? effectZh; // 自译中文效果
  final String? effectJp; // 效果原文

  final String? color; // 属性：日/月/花/雪/星/宙/…
  final String? cost; // 使用费用：花/花花/宙宙宙…（属性符号串）
  final int? ex;
  final int? ap;
  final int? dp;
  final int? sp;
  final int? dmg;

  /// タイプ（类型）——官方只有部分作品才有，比如 Fate 的「サーヴァント」
  final String? cardType;

  /// 卡牌种类：キャラクター / イベント / アイテム / エリア
  final String? kind;

  /// 制限（区域限制）：如 －－－●●●
  final String? limit;

  /// 所属系列：官方「作品 / ブランド」那一条，例如
  /// `ニトロオリジン 1.0(NIT)`、`Fate/Grand Order 1.0`
  final String? series;

  final String? illustrator;
  final String? rarity;
  final String? releaseInfo; // 初出
  final String? titleJp; // 称号（日文小标题）

  /// 基本能力是否含 leader（リーダー）——一套卡组最多带 1 张
  final bool isLeader;

  /// 卡片自带的构筑限制（例如只能使用某个作品/会社的卡）
  final String? deckRestriction;

  /// 展示优先用中文
  String get displayName =>
      (nameZh != null && nameZh!.isNotEmpty) ? nameZh! : nameJp;

  /// 卡号里去掉后缀的「本体」部分，用于把 -A / -P 变体归到同一张卡
  String get baseCode {
    final i = code.indexOf('-', 4);
    return i > 0 ? code.substring(0, i) : code;
  }

  /// 卡号前缀（LO / LO-A 等），仅用于诊断展示
  String get setPrefix {
    final i = code.indexOf('-');
    return i > 0 ? code.substring(0, i) : code;
  }

  static final RegExp _brandRe = RegExp(r'\(([A-Z0-9]+)\)\s*$');

  /// 会社 / 品牌标记：`ニトロオリジン 1.0(NIT)` → `NIT`
  ///
  /// 没有标记的（例如 `Fate/Grand Order 1.0`）归到 [brandOther]，表示「作品系」。
  // ⚠ 必须是**常量**：它被用作分组 key、排序键，还有 `brand == brandOther`
// 这种比较。一旦随界面语言变，切语言后分组和比较全乱。
// 界面要显示中文时，在显示处用 tr() 包（见 mine_page）。
  // ⚠ 必须是**常量**：它被用作分组 key、排序键，还有 `brand == brandOther`
  // 这种比较。一旦随界面语言变，切语言后分组和比较全乱。
  // 界面要显示中文时，在显示处套 tr()。
  // ⚠ 必须是**常量**：它被用作分组 key、排序键，还有 `brand == brandOther`
  // 这种比较。一旦随界面语言变，切语言后分组和比较全乱。
  // 界面要显示中文时，在显示处套 tr()。
  static const String brandOther = '作品系列';

  String get brandTag {
    final s = series;
    if (s == null || s.isEmpty) return brandOther;
    final m = _brandRe.firstMatch(s);
    return m == null ? brandOther : m.group(1)!;
  }

  /// 系列名去掉尾巴上的会社标记：`ニトロオリジン 1.0(NIT)` → `ニトロオリジン 1.0`
  String get seriesName {
    final s = series;
    if (s == null || s.isEmpty) return '未归类';
    return s.replaceFirst(_brandRe, '').trim();
  }

  /// 排序用键
  String get sortKey => '$brandTag\u0000$seriesName\u0000$code';

  factory LyceeCard.fromJson(Map<String, dynamic> j) => LyceeCard(
        code: '${j['code'] ?? ''}',
        nameJp: '${j['name'] ?? ''}',
        nameZh: j['name_zh'] as String?,
        effectZh: j['effect_zh'] as String?,
        effectJp: j['effect_jp'] as String?,
        color: j['color'] as String?,
        cost: (j['cost'] as String?)?.trim().isEmpty ?? true
            ? null
            : '${j['cost']}'.trim(),
        ex: _int(j['ex']),
        ap: _int(j['ap']),
        dp: _int(j['dp']),
        sp: _int(j['sp']),
        dmg: _int(j['dmg']),
        cardType: _blankToNull(j['type']),
        kind: _blankToNull(j['kind']),
        limit: _blankToNull(j['limit']),
        series: j['series'] as String?,
        illustrator: j['illustrator'] as String?,
        rarity: j['rarity'] as String?,
        releaseInfo: j['release'] as String?,
        titleJp: j['title_jp'] as String?,
        isLeader:
            j['leader'] == true || j['leader'] == 1 || j['leader'] == '1',
        deckRestriction: j['restriction'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': nameJp,
        'name_zh': nameZh,
        'effect_zh': effectZh,
        'effect_jp': effectJp,
        'color': color,
        'cost': cost,
        'ex': ex,
        'ap': ap,
        'dp': dp,
        'sp': sp,
        'dmg': dmg,
        'type': cardType,
        'kind': kind,
        'limit': limit,
        'series': series,
        'illustrator': illustrator,
        'rarity': rarity,
        'release': releaseInfo,
        'title_jp': titleJp,
        'leader': isLeader,
        'restriction': deckRestriction,
      };

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    return int.tryParse('$v');
  }

  static String? _blankToNull(Object? v) {
    final s = v?.toString().trim();
    return (s == null || s.isEmpty || s == '-' || s == '—') ? null : s;
  }

  /// 卡牌种类翻成中文
  String? get kindZh => kKindZh(kind);

  static List<LyceeCard> listFromJsonString(String s) {
    final raw = jsonDecode(s) as List<dynamic>;
    return raw
        .map((e) => LyceeCard.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}
