import '../models/lycee_card.dart';

/// 场地格数：前 3 格 AF（攻击区）+ 后 3 格 DF（防御区），共 6 格。
/// 和「对战规则」页里写的口径保持一致，不另造一套。
const int kAfSlots = 3;
const int kDfSlots = 3;

/// 修正的时机。
///
/// 玩家在局内要记的是「这个数为什么会变成这样」，所以每条修正都挂在
/// 一个时机上：上回合留下的、本回合做的、对方应对时做的、以及常驻的
/// （道具／区域这类一直在场上的）。
enum CalcPhase { lastTurn, thisTurn, response, always }

const Map<CalcPhase, String> kCalcPhaseNames = <CalcPhase, String>{
  CalcPhase.lastTurn: '上回合',
  CalcPhase.thisTurn: '此回合',
  CalcPhase.response: '应对',
  CalcPhase.always: '常时',
};

/// 四个数值的容器。[CalcValues.zero] 表示全 0。
class CalcValues {
  const CalcValues(this.ap, this.dp, this.sp, this.dmg);

  final int ap;
  final int dp;
  final int sp;
  final int dmg;

  static const CalcValues zero = CalcValues(0, 0, 0, 0);

  bool get isZero => ap == 0 && dp == 0 && sp == 0 && dmg == 0;

  CalcValues operator +(CalcValues o) =>
      CalcValues(ap + o.ap, dp + o.dp, sp + o.sp, dmg + o.dmg);

  CalcValues operator -(CalcValues o) =>
      CalcValues(ap - o.ap, dp - o.dp, sp - o.sp, dmg - o.dmg);

  @override
  String toString() => 'AP$ap/DP$dp/SP$sp/DMG$dmg';

  @override
  bool operator ==(Object other) =>
      other is CalcValues &&
      other.ap == ap &&
      other.dp == dp &&
      other.sp == sp &&
      other.dmg == dmg;

  @override
  int get hashCode => Object.hash(ap, dp, sp, dmg);
}

/// 一条修正：挂在某个时机下的一组数值增减。
///
/// [label] 是玩家自己写的来源说明（例如「XX 的效果」「支援 +2」），
/// 可以留空 —— 数值才是要紧的。
///
/// [source] 记录这条修正是怎么来的：手动加的、从卡面效果解析出来的、
/// 还是自动套用的。计算器要能**逐步查看和修改每一步**，所以来源要留着。
enum CalcModSource { manual, effect, auto }

const Map<CalcModSource, String> kCalcModSourceNames = <CalcModSource, String>{
  CalcModSource.manual: '手动',
  CalcModSource.effect: '效果',
  CalcModSource.auto: '自动',
};

class CalcMod {
  CalcMod({
    required this.phase,
    this.label = '',
    this.ap = 0,
    this.dp = 0,
    this.sp = 0,
    this.dmg = 0,
    this.source = CalcModSource.manual,
    this.effectRaw = '',
    this.sourceCode = '',
    this.key = '',
  });

  final CalcPhase phase;

  /// 说明文字（玩家可改）
  String label;

  /// 数值可改 —— 玩家要能「修改每一步」
  int ap, dp, sp, dmg;

  /// 这条修正的来源（手动 / 效果 / 自动）
  final CalcModSource source;

  /// 效果原文片段（来源是效果时留档，方便核对）
  final String effectRaw;

  /// 这条修正来自哪张卡（空的 = 玩家手动加的）。
  /// 「撤销这条效果」靠它 + [effectRaw] 定位。
  final String sourceCode;

  /// 自动算出来的条目靠这个 key 认领自己。
  ///
  /// 自动条目每次场地变化都要**重算**，重算时用 key 把玩家的改动/删除找回来：
  /// 改过的进 [CalcSlot.autoOverrides]，删掉的进 [CalcSlot.autoSuppressed]。
  final String key;

  CalcValues get values => CalcValues(ap, dp, sp, dmg);

  bool get isZero => values.isZero;

  /// 「+2」「-1」这种显示写法
  static String signed(int v) => v > 0 ? '+$v' : '$v';
}

/// 场上一个格子：放了哪张卡 + 这张卡身上/下面挂的东西。
class CalcSlot {
  CalcSlot({this.code});

  /// 卡号；null 表示空格
  String? code;

  /// 放在这张卡**下面**的充能卡数（充能：弃牌堆的卡放到角色下面，
  /// 用来支付「C」图标的费用；上限见卡面的 [チャージ:N]）
  int charge = 0;

  /// 这张卡下面的储存区（置き場）—— 和充能一样挂在这张卡上
  final List<CalcZone> zones = <CalcZone>[];

  /// 玩家手动加的 / 手动套用效果的修正
  final List<CalcMod> mods = <CalcMod>[];

  /// 自动算出来的修正。**不直接持久化**：每次场地变化重算一遍。
  final List<CalcMod> autoMods = <CalcMod>[];

  /// 玩家改过的自动条目（key → 改后的那条），重算时用改后的那条
  final Map<String, CalcMod> autoOverrides = <String, CalcMod>{};

  /// 玩家删掉的自动条目，重算时不再补回来
  final Set<String> autoSuppressed = <String>{};

  bool get isEmpty => code == null;

  bool get hasMods => mods.isNotEmpty || autoMods.isNotEmpty;

  /// 卡下面压着的总张数（充能 + 各储存区）—— 格子上显示用
  int get underCount =>
      charge + zones.fold(0, (int a, CalcZone z) => a + z.count);

  void clear() {
    code = null;
    charge = 0;
    zones.clear();
    mods.clear();
    autoMods.clear();
    autoOverrides.clear();
    autoSuppressed.clear();
  }
}

/// 一个储存区（置き場）。
///
/// 游戏里有 20 多种具名的「〜置き場」（「迷宮」「経験値」「卒業」…），
/// 每张卡挂自己的那一个，所以这里让玩家**自由命名**，不写死任何名字。
class CalcZone {
  CalcZone({required this.name});

  String name;

  /// 里面存了几张卡
  int count = 0;

  void clear() => count = 0;
}

/// 一方的场地：AF 三格（前）+ DF 三格（后）。
///
/// 储存区不在这里 —— 它挂在 [CalcSlot.zones] 上，跟着卡走。
class CalcSide {
  CalcSide()
      : af = List<CalcSlot>.generate(kAfSlots, (_) => CalcSlot()),
        df = List<CalcSlot>.generate(kDfSlots, (_) => CalcSlot());

  final List<CalcSlot> af;
  final List<CalcSlot> df;

  Iterable<CalcSlot> get all sync* {
    yield* af;
    yield* df;
  }

  bool get isEmpty => all.every((CalcSlot s) => s.isEmpty);

  int get occupied => all.where((CalcSlot s) => !s.isEmpty).length;

  void clear() {
    for (final CalcSlot s in all) {
      s.clear();
    }
  }
}

/// 卡面基础值（卡不在或字段缺失都按 0 算，局内不至于因为缺字段崩掉）。
CalcValues baseOf(LyceeCard? card) => card == null
    ? CalcValues.zero
    : CalcValues(card.ap ?? 0, card.dp ?? 0, card.sp ?? 0, card.dmg ?? 0);

/// 全部修正的合计（手动 + 自动）。
CalcValues modsTotal(CalcSlot slot) {
  var v = CalcValues.zero;
  for (final CalcMod m in slot.mods) {
    v = v + m.values;
  }
  for (final CalcMod m in slot.autoMods) {
    v = v + m.values;
  }
  return v;
}

/// 某个时机下的修正合计（手动 + 自动）。
CalcValues modsOfPhase(CalcSlot slot, CalcPhase phase) {
  var v = CalcValues.zero;
  for (final CalcMod m in slot.mods) {
    if (m.phase == phase) v = v + m.values;
  }
  for (final CalcMod m in slot.autoMods) {
    if (m.phase == phase) v = v + m.values;
  }
  return v;
}

/// 当前数值 = 卡面基础值 + 全部修正。
CalcValues currentOf(CalcSlot slot, LyceeCard? card) =>
    baseOf(card) + modsTotal(slot);

/// 一方场上合计：只算放了卡的格子。
CalcValues sideTotal(CalcSide side, LyceeCard? Function(String code) lookup) {
  var v = CalcValues.zero;
  for (final CalcSlot s in side.all) {
    final String? code = s.code;
    if (code == null) continue;
    v = v + currentOf(s, lookup(code));
  }
  return v;
}

/// 某一方的合计里，每个时机的修正各贡献了多少。
CalcValues sideModsOfPhase(CalcSide side, CalcPhase phase) {
  var v = CalcValues.zero;
  for (final CalcSlot s in side.all) {
    v = v + modsOfPhase(s, phase);
  }
  return v;
}
