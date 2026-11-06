import '../models/lycee_card.dart';
import 'keyword_db.dart';

/// 检索页的「组合筛选」条件。
///
/// 所有条件之间是 **AND**（同时满足），同一组里勾了多个是 **OR**。
class CardFilter {
  CardFilter();

  /// 属性（多色卡只要包含勾选的颜色就算命中）
  final Set<String> colors = {};

  /// 卡种：キャラクター / イベント / アイテム / エリア
  final Set<String> kinds = {};

  /// 类型（タイプ）
  final Set<String> types = {};

  /// 稀有度
  final Set<String> rarities = {};

  /// 词条：卡的效果里必须出现这些词（全部满足）
  final Set<String> keywords = {};

  // 数值范围（null = 不限）
  int? costMin, costMax; // 费用按属性符号个数算，比如「花花」= 2
  int? exMin, exMax;
  int? apMin, apMax;
  int? dpMin, dpMax;
  int? spMin, spMax;
  int? dmgMin, dmgMax;

  bool get isEmpty => activeCount == 0;

  int get activeCount {
    var n = colors.length + kinds.length + types.length +
        rarities.length + keywords.length;
    for (final v in [costMin, costMax, exMin, exMax, apMin, apMax,
                     dpMin, dpMax, spMin, spMax, dmgMin, dmgMax]) {
      if (v != null) n++;
    }
    return n;
  }

  void clear() {
    colors.clear();
    kinds.clear();
    types.clear();
    rarities.clear();
    keywords.clear();
    costMin = costMax = null;
    exMin = exMax = null;
    apMin = apMax = null;
    dpMin = dpMax = null;
    spMin = spMax = null;
    dmgMin = dmgMax = null;
  }

  /// 复制当前筛选条件
  CardFilter copy() {
    return CardFilter()
      ..colors.addAll(colors)
      ..kinds.addAll(kinds)
      ..types.addAll(types)
      ..rarities.addAll(rarities)
      ..keywords.addAll(keywords)
      ..costMin = costMin
      ..costMax = costMax
      ..exMin = exMin
      ..exMax = exMax
      ..apMin = apMin
      ..apMax = apMax
      ..dpMin = dpMin
      ..dpMax = dpMax
      ..spMin = spMin
      ..spMax = spMax
      ..dmgMin = dmgMin
      ..dmgMax = dmgMax;
  }

  /// 从 JSON 恢复
  factory CardFilter.fromJson(Map<String, dynamic> j) {
    return CardFilter()
      ..colors.addAll((j['colors'] as List<dynamic>? ?? []).cast<String>())
      ..kinds.addAll((j['kinds'] as List<dynamic>? ?? []).cast<String>())
      ..types.addAll((j['types'] as List<dynamic>? ?? []).cast<String>())
      ..rarities.addAll((j['rarities'] as List<dynamic>? ?? []).cast<String>())
      ..keywords.addAll((j['keywords'] as List<dynamic>? ?? []).cast<String>())
      ..costMin = j['costMin'] as int?
      ..costMax = j['costMax'] as int?
      ..exMin = j['exMin'] as int?
      ..exMax = j['exMax'] as int?
      ..apMin = j['apMin'] as int?
      ..apMax = j['apMax'] as int?
      ..dpMin = j['dpMin'] as int?
      ..dpMax = j['dpMax'] as int?
      ..spMin = j['spMin'] as int?
      ..spMax = j['spMax'] as int?
      ..dmgMin = j['dmgMin'] as int?
      ..dmgMax = j['dmgMax'] as int?;
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      if (colors.isNotEmpty) 'colors': colors.toList(),
      if (kinds.isNotEmpty) 'kinds': kinds.toList(),
      if (types.isNotEmpty) 'types': types.toList(),
      if (rarities.isNotEmpty) 'rarities': rarities.toList(),
      if (keywords.isNotEmpty) 'keywords': keywords.toList(),
      if (costMin != null) 'costMin': costMin,
      if (costMax != null) 'costMax': costMax,
      if (exMin != null) 'exMin': exMin,
      if (exMax != null) 'exMax': exMax,
      if (apMin != null) 'apMin': apMin,
      if (apMax != null) 'apMax': apMax,
      if (dpMin != null) 'dpMin': dpMin,
      if (dpMax != null) 'dpMax': dpMax,
      if (spMin != null) 'spMin': spMin,
      if (spMax != null) 'spMax': spMax,
      if (dmgMin != null) 'dmgMin': dmgMin,
      if (dmgMax != null) 'dmgMax': dmgMax,
    };
  }

  static bool _inRange(int? v, int? lo, int? hi) {
    if (lo == null && hi == null) return true;
    if (v == null) return false;
    if (lo != null && v < lo) return false;
    if (hi != null && v > hi) return false;
    return true;
  }

  bool matches(LyceeCard c) {
    if (colors.isNotEmpty) {
      final col = c.color ?? '';
      if (!colors.any(col.contains)) return false;
    }
    if (kinds.isNotEmpty && !kinds.contains(c.kind ?? '')) return false;
    if (types.isNotEmpty && !types.contains(c.cardType ?? '')) return false;
    if (rarities.isNotEmpty && !rarities.contains(c.rarity ?? '')) return false;

    if (keywords.isNotEmpty) {
      final text = '${c.effectZh ?? ''} ${c.effectJp ?? ''}';
      final hit = KeywordDb.instance.scan(text).map((e) => e.$3.zh).toSet();
      for (final k in keywords) {
        if (!hit.contains(k)) return false;
      }
    }

    if (!_inRange(c.cost?.length, costMin, costMax)) return false;
    if (!_inRange(c.ex, exMin, exMax)) return false;
    if (!_inRange(c.ap, apMin, apMax)) return false;
    if (!_inRange(c.dp, dpMin, dpMax)) return false;
    if (!_inRange(c.sp, spMin, spMax)) return false;
    if (!_inRange(c.dmg, dmgMin, dmgMax)) return false;
    return true;
  }
}
