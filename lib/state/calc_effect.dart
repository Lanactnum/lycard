import '../models/lycee_card.dart';
import 'calc_field.dart';

/// 效果能影响的目标（相对于效果来源那张卡）。
///
/// 解析不出来的一律进 [unknown]，由玩家自己指定 —— **宁可让玩家多点一下，
/// 也不能替玩家猜错目标**：局内数值算错的代价比多一次点击大得多。
enum EffectTarget {
  self,
  allyOne,
  allyAll,
  allyAfAll,
  allyDfAll,
  enemyOne,
  enemyAll,
  unknown,
}

const Map<EffectTarget, String> kEffectTargetNames = <EffectTarget, String>{
  EffectTarget.self: '自身',
  EffectTarget.allyOne: '我方 1 体',
  EffectTarget.allyAll: '我方全体',
  EffectTarget.allyAfAll: '我方 AF 全体',
  EffectTarget.allyDfAll: '我方 DF 全体',
  EffectTarget.enemyOne: '对方 1 体',
  EffectTarget.enemyAll: '对方全体',
  EffectTarget.unknown: '目标待定',
};

/// 从效果文本里解析出的一条「可套用的数值加成」。
class EffectBonus {
  const EffectBonus({
    required this.sourceCode,
    required this.raw,
    required this.values,
    required this.target,
    required this.phase,
    this.hasVariable = false,
    this.conditional = false,
    this.activated = false,
    this.variableNote = '',
  });

  /// 效果来自哪张卡
  final String sourceCode;

  /// 原文片段（留档，方便玩家核对）
  final String raw;

  /// 解析出的数值；含变量时为全 0（要玩家自己填）
  final CalcValues values;

  final EffectTarget target;
  final CalcPhase phase;

  /// 含 `[变量]`（例如「+[コストが2点以下の味方[宙]キャラの数]」）——
  /// 这种算不出来，数值要玩家自己填
  final bool hasVariable;

  /// 含条件（〜の場合 / 〜とき / 〜なら）—— 不一定生效，默认不自动套用
  final bool conditional;

  /// 「要用才生效」的能力（[宣言] / [誘発] / [手札宣言] / 带代价括号的）——
  /// 卡在场上 ≠ 这个效果已经用过了，所以也不自动套用。
  final bool activated;

  /// 变量的原文说明
  final String variableNote;

  bool get isZero => values.isZero;

  /// 无变量 + 无条件 + 不是「要用才生效」= 可以放心自动套用
  bool get isAutoApplicable => !hasVariable && !conditional && !activated;

  /// 显示用的说明，例如「我方 1 体　AP+1」
  String get summary {
    final List<String> parts = <String>[];
    if (values.ap != 0) parts.add('AP${CalcMod.signed(values.ap)}');
    if (values.dp != 0) parts.add('DP${CalcMod.signed(values.dp)}');
    if (values.sp != 0) parts.add('SP${CalcMod.signed(values.sp)}');
    if (values.dmg != 0) parts.add('DMG${CalcMod.signed(values.dmg)}');
    final String v = parts.isEmpty ? (hasVariable ? '数值待填' : '无数值') : parts.join(' ');
    return '${kEffectTargetNames[target]}　$v';
  }

  /// 套用后落到修正上的说明文字
  String label(String cardName) => '$cardName 的效果：$summary';
}

/// 效果文本解析器。
///
/// 设计原则：**保守**。Lycee 的效果文本花样极多，这里只认几种高度规整的写法，
/// 认不出来就当没有 —— 漏掉一条玩家可以手动补，认错一条玩家会算错数值。
class EffectParser {
  EffectParser._();

  /// 全角 → 半角（ＡＰ→AP、＋→+、１２３→123、全角空格→半角）
  static String normalize(String s) {
    final StringBuffer out = StringBuffer();
    for (final int r in s.runes) {
      if (r == 0x3000) {
        out.write(' ');
      } else if (r >= 0xFF01 && r <= 0xFF5E) {
        out.writeCharCode(r - 0xFEE0);
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString();
  }

  /// 数值串里的单个项：AP+2 / DP-1 / SP+3 / DMG+2
  static final RegExp _oneValue = RegExp(r'(AP|DP|SP|DMG)\s*([+-])\s*(\d+)');

  /// 带变量的数值：`APに+[コストが2点以下の味方[宙]キャラの数]する`
  static final RegExp _varValue = RegExp(
    r'(AP|DP|SP|DMG)(?:と(?:AP|DP|SP|DMG))*に\+?\[([^\]]+)\]',
  );

  /// 条件句
  static final RegExp _cond = RegExp(r'場合|とき|なら|いたら|中は|中、');

  /// 方括号变量（数值型，例如 `[破棄した枚数]`）—— 出现在同句里就不自动套用
  static final RegExp _bracketVar = RegExp(r'\[[^\]]*(?:枚数|数|した|いる|ある)[^\]]*\]');

  /// 找目标：在数值串前面的一段里，取**最后**出现的那个目标写法；
  /// 位置相同时取**更具体**的那个（「味方ＤＦキャラ全て」要赢过
  /// 「味方キャラ全て」，否则 DF 全体会被当成全体）。
  static EffectTarget _targetOf(String pre) {
    final List<(int, int, EffectTarget)> found = <(int, int, EffectTarget)>[];

    void probe(String pattern, EffectTarget t, int specificity) {
      for (final RegExpMatch m in RegExp(pattern).allMatches(pre)) {
        found.add((m.start, specificity, t));
      }
    }

    // specificity 越大越具体
    probe(r'このキャラに', EffectTarget.self, 9);
    // 对战角色（战斗中的对手，具体哪一体由玩家点）
    probe(r'対戦キャラに', EffectTarget.enemyOne, 6);
    // 指定卡名的友方：味方「アサシン／ステンノ」1体に
    probe(r'味方「[^」]{1,30}」\d*体に', EffectTarget.allyOne, 6);
    probe(r'\{?味方[^。{}]{0,10}?キャラ\d*体\}?に', EffectTarget.allyOne, 5);
    probe(r'味方[^。]{0,6}?DF[^。]{0,6}?キャラ全てに', EffectTarget.allyDfAll, 8);
    probe(r'味方[^。]{0,6}?AF[^。]{0,6}?キャラ全てに', EffectTarget.allyAfAll, 8);
    probe(r'\{?味方[^。{}]{0,10}?キャラ全て\}?に', EffectTarget.allyAll, 4);
    probe(r'\{?相手[^。{}]{0,10}?キャラ\d*体\}?に', EffectTarget.enemyOne, 5);
    probe(r'\{?相手[^。{}]{0,10}?キャラ全て\}?に', EffectTarget.enemyAll, 4);

    if (found.isEmpty) return EffectTarget.unknown;
    found.sort((a, b) {
      final int byPos = a.$1.compareTo(b.$1);
      return byPos != 0 ? byPos : a.$2.compareTo(b.$2);
    });
    return found.last.$3;
  }

  /// 找时机：数值串前面最近的 `[タグ]`
  static CalcPhase _phaseOf(String text, int valueStart) {
    final String pre = text.substring(0, valueStart);
    final Iterable<RegExpMatch> tags =
        RegExp(r'\[([^\]]{1,12})\]').allMatches(pre);
    if (tags.isEmpty) return CalcPhase.thisTurn;
    final String tag = tags.last.group(1) ?? '';
    if (tag.startsWith('常時')) return CalcPhase.always;
    if (tag.startsWith('誘発')) return CalcPhase.thisTurn;
    if (tag.startsWith('宣言') || tag.startsWith('手札宣言')) {
      return CalcPhase.thisTurn;
    }
    return CalcPhase.thisTurn;
  }

  /// 数值串前面最近的 `[标签]`（没有就是 null）。
  ///
  /// 代价括号（[0] / [花花] / [C1]）也算标签 —— 带这类括号的效果基本
  /// 都得「用过才算数」，归到需要玩家确认反而更安全。
  static String? _nearestTag(String pre) {
    final Iterable<RegExpMatch> tags =
        RegExp(r'\[([^\]]{1,12})\]').allMatches(pre);
    if (tags.isEmpty) return null;
    return tags.last.group(1) ?? '';
  }

  /// 解析一张卡的效果，返回所有能算的数值加成。
  static List<EffectBonus> parse(LyceeCard card) {
    final String raw = card.effectJp ?? '';
    if (raw.isEmpty) return const <EffectBonus>[];
    final String text = normalize(raw);
    final List<EffectBonus> out = <EffectBonus>[];

    // ① 普通数值串：AP+2・DP+2 这种（可能连着写好几项）
    final List<RegExpMatch> matches = _oneValue.allMatches(text).toList();
    int i = 0;
    while (i < matches.length) {
      final RegExpMatch first = matches[i];
      int ap = 0, dp = 0, sp = 0, dmg = 0;
      int runEnd = first.end;
      int j = i;
      // 把紧挨着的项归成一组（中间只允许 ・、・、空格）
      while (j < matches.length) {
        final RegExpMatch m = matches[j];
        final String gap = j == i
            ? ''
            : text.substring(matches[j - 1].end, m.start).trim();
        if (j > i && gap.isNotEmpty && gap != '・' && gap != '、') break;
        final int v = int.parse(m.group(3)!) * (m.group(2) == '-' ? -1 : 1);
        switch (m.group(1)!) {
          case 'AP':
            ap += v;
          case 'DP':
            dp += v;
          case 'SP':
            sp += v;
          case 'DMG':
            dmg += v;
        }
        runEnd = m.end;
        j++;
      }
      i = j;

      final String pre = text.substring(0, first.start);
      final EffectTarget target = _targetOf(pre);
      final CalcPhase phase = _phaseOf(text, first.start);
      // 「要用才生效」判定：往前看最近的一个 [标签]。
      // 没有标签（纯事件/道具效果）或 [常時] → 放上场就算数；
      // [宣言]/[誘発]/[手札宣言] 以及代价括号（[0] / [花花] / [C1]）
      // 都得玩家点过才算用了，不自动套。
      final String? tag = _nearestTag(pre);
      final bool activated = tag != null && !tag.startsWith('常時');
      // 条件判定：看本句（上一个 。或 ]] 之后）里有没有条件词
      final int clauseStart = _clauseStart(text, first.start);
      final String clause = text.substring(clauseStart, first.start);
      final bool conditional = _cond.hasMatch(clause);
      // ⚠ 安全规则：同一句里有 `[变量]`（例如「+[破棄した枚数]」）时，
      // 这组数值多半和变量挂钩，算不准 —— 一律不自动套用，让玩家填。
      final bool sameClauseVariable = _varValue.hasMatch(clause) ||
          _bracketVar.hasMatch(clause);

      out.add(EffectBonus(
        sourceCode: card.code,
        raw: text.substring(
          first.start,
          runEnd.clamp(0, text.length),
        ),
        values: CalcValues(ap, dp, sp, dmg),
        target: target,
        phase: phase,
        conditional: conditional || sameClauseVariable,
        activated: activated,
      ));
    }

    // ② 带变量的数值：APに+[变量] 这种算不出来，但要让玩家知道有这回事
    for (final RegExpMatch m in _varValue.allMatches(text)) {
      final int clauseStart = _clauseStart(text, m.start);
      final String clause = text.substring(clauseStart, m.start);
      out.add(EffectBonus(
        sourceCode: card.code,
        raw: text.substring(m.start, m.end),
        values: CalcValues.zero,
        target: _targetOf(text.substring(0, m.start)),
        phase: _phaseOf(text, m.start),
        hasVariable: true,
        variableNote: m.group(2) ?? '',
        conditional: _cond.hasMatch(clause),
      ));
    }

    return out;
  }

  /// 找到「本句」的起点：上一个 。／改行／`]]` 之后
  static int _clauseStart(String text, int before) {
    int start = 0;
    for (int k = before - 1; k >= 0; k--) {
      final String ch = text[k];
      if (ch == '。' || ch == '\n') {
        start = k + 1;
        break;
      }
      if (k >= 1 && text[k - 1] == ']' && ch == ']') {
        start = k + 1;
        break;
      }
    }
    return start;
  }

  /// 卡面的 [チャージ:N] 上限（没有就是 null）
  static int? chargeMaxOf(LyceeCard? card) {
    final String raw = card?.effectJp ?? '';
    if (raw.isEmpty) return null;
    final RegExpMatch? m =
        RegExp(r'チャージ[:：]\s*(\d+)').firstMatch(normalize(raw));
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// 卡面里写到的「〜置き場」名字（去重，最多 8 个）。
  ///
  /// 一张卡可能同时开好几个置き場，名字也五花八门（「迷宮」「経験値」
  /// 「卒業」…），所以只当**建议**列在新建对话框里，玩家照样可以自己填。
  static List<String> storageNamesOf(LyceeCard? card) {
    final String raw = card?.effectJp ?? '';
    if (raw.isEmpty) return const <String>[];
    final List<String> out = <String>[];
    for (final RegExpMatch m
        in RegExp(r'「([^」]{1,20})」置き場').allMatches(normalize(raw))) {
      final String n = m.group(1) ?? '';
      if (n.isEmpty || out.contains(n)) continue;
      out.add(n);
      if (out.length >= 8) break;
    }
    return out;
  }

  /// 把一条效果加成落到某个格子上（追加一条修正）。
  static void applyBonus(
    CalcSlot slot,
    EffectBonus b,
    String sourceName, {
    CalcModSource source = CalcModSource.auto,
    String key = '',
  }) {
    slot.mods.add(CalcMod(
      phase: b.phase,
      label: b.label(sourceName),
      ap: b.values.ap,
      dp: b.values.dp,
      sp: b.values.sp,
      dmg: b.values.dmg,
      source: source,
      effectRaw: b.raw,
      sourceCode: b.sourceCode,
      key: key,
    ));
  }

  /// 目标 → 实际落到哪些格子上。
  ///
  /// 返回空列表 = 这个目标解析不出来（或需要玩家指定某一体），
  /// 由玩家自己点选 —— 绝不替玩家猜。
  static List<CalcSlot> resolveTargets(
    EffectTarget t, {
    required CalcSlot source,
    required List<CalcSlot> allyAf,
    required List<CalcSlot> allyDf,
    required List<CalcSlot> enemyAf,
    required List<CalcSlot> enemyDf,
  }) {
    List<CalcSlot> occupied(List<CalcSlot> l) =>
        l.where((CalcSlot s) => !s.isEmpty).toList();

    switch (t) {
      case EffectTarget.self:
        return <CalcSlot>[source];
      case EffectTarget.allyAll:
        return <CalcSlot>[...occupied(allyAf), ...occupied(allyDf)];
      case EffectTarget.allyAfAll:
        return occupied(allyAf);
      case EffectTarget.allyDfAll:
        return occupied(allyDf);
      case EffectTarget.enemyAll:
        return <CalcSlot>[...occupied(enemyAf), ...occupied(enemyDf)];
      case EffectTarget.allyOne:
      case EffectTarget.enemyOne:
      case EffectTarget.unknown:
        return const <CalcSlot>[];
    }
  }
}

/// 把双方场上的效果重算一遍，写进每个格子的 [CalcSlot.autoMods]。
///
/// 为什么是「重算」而不是「放牌那一刻算一次」：「味方キャラ全てにＡＰ＋１」
/// 这种全场效果，**后上场的卡也该吃到** —— 只在放牌时算一次，后来的卡就漏了。
///
/// 只算确定生效的（[EffectBonus.isAutoApplicable]）：条件句、含变量、
/// 需要指定单体目标的一律不自动套，留在面板里让玩家点 ——
/// 宁可让玩家多点一下，也不能替玩家猜错目标。
///
/// 玩家对自动条目的改动/删除会保留：改过的用 [CalcSlot.autoOverrides]，
/// 删掉的记进 [CalcSlot.autoSuppressed]，重算时都认。
void recomputeAuto(
  CalcSide mine,
  CalcSide theirs,
  LyceeCard? Function(String code) lookup,
) {
  for (final CalcSlot s in <CalcSlot>[...mine.all, ...theirs.all]) {
    s.autoMods.clear();
  }
  _autoOneSide(mine, theirs, lookup);
  _autoOneSide(theirs, mine, lookup);
}

void _autoOneSide(
  CalcSide ally,
  CalcSide enemy,
  LyceeCard? Function(String code) lookup,
) {
  for (final CalcSlot src in ally.all) {
    final String? code = src.code;
    if (code == null) continue;
    final LyceeCard? card = lookup(code);
    if (card == null) continue;
    final List<EffectBonus> bonuses = EffectParser.parse(card);
    for (int i = 0; i < bonuses.length; i++) {
      final EffectBonus b = bonuses[i];
      if (!b.isAutoApplicable) continue;
      final List<CalcSlot> targets = EffectParser.resolveTargets(
        b.target,
        source: src,
        allyAf: ally.af,
        allyDf: ally.df,
        enemyAf: enemy.af,
        enemyDf: enemy.df,
      );
      if (targets.isEmpty) continue; // 单体/目标不明 → 交给玩家点
      final String key = '$code#$i';
      for (final CalcSlot t in targets) {
        if (t.autoSuppressed.contains(key)) continue;
        final CalcMod? edited = t.autoOverrides[key];
        t.autoMods.add(edited ??
            CalcMod(
              phase: b.phase,
              label: b.label(card.displayName),
              ap: b.values.ap,
              dp: b.values.dp,
              sp: b.values.sp,
              dmg: b.values.dmg,
              source: CalcModSource.auto,
              effectRaw: b.raw,
              sourceCode: code,
              key: key,
            ));
      }
    }
  }
}
