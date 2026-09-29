import '../models/lycee_card.dart';
import 'keyword_db.dart';

/// 检索页的「组合筛选」条件。
///
/// 所有条件之间是 **AND**（同时满足），同一组里勾了多个是 **OR**。
class CardFilter {
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
