import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../l10n/l10n.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import '../state/calc_effect.dart';
import '../state/calc_field.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/card_art.dart';
import '../widgets/card_picker.dart';
import '../widgets/glass.dart';
import '../widgets/layout.dart';
import '../widgets/tags.dart';

/// 局内数值计算器。
///
/// 用途：对局中把牌摆到场上，随手记下「上回合 / 此回合 / 应对 / 常时」
/// 各自的数值增减，App 实时算出每个角色的当前 AP/DP/SP/DMG 和场上合计。
///
/// 三件事在这里汇合：
/// ① **摆牌**：空格点一下放牌（可直接从自己的卡组里挑）；
/// ② **记状态**：每张卡下面的充能张数和储存区（置き場）—— 都挂在这张卡上；
/// ③ **算数值**：**每张卡放上去就自动算**。卡面效果里「确定生效」的
///    （[常時] 或没写标签的）自动套上，而且场地一变就整体重算 ——
///    后上场的卡也能吃到先前那张的全场效果；其余（含条件、含变量、
///    要发动的、目标要指定的）在卡的面板里逐条查看/修改/撤销，
///    或者一键把剩下的全部算上。
///
/// 为什么不存：局内是一次性的，退出即清空（玩家的选择）。所以状态就放在
/// 这个 State 里，不进 AppState、不落盘。
class CalcPage extends StatefulWidget {
  const CalcPage({super.key});

  @override
  State<CalcPage> createState() => _CalcPageState();
}

class _CalcPageState extends State<CalcPage> {
  /// 我方 / 对方各一块场地（AF 3 格 + DF 3 格 + 储存区）
  final CalcSide _mine = CalcSide();
  final CalcSide _theirs = CalcSide();

  /// 刚删掉的那一条修正（面板顶上「撤销删除」用，顺手删错了不必重填一遍）
  CalcMod? _removedMod;
  CalcSlot? _removedFrom;
  CalcMod? _removedOverride;
  int _removedAt = -1;

  LyceeCard? _cardOf(CalcSlot slot) {
    final String? code = slot.code;
    return code == null ? null : CardRepository.instance.byCode(code);
  }

  /// 场地一变就整体重算自动数值。
  ///
  /// 为什么不是「放牌那一刻算一次」：「味方キャラ全てにＡＰ＋１」这种
  /// 全场效果，**后上场的卡也该吃到** —— 只算一次，后来的卡就漏了。
  void _recompute() =>
      recomputeAuto(_mine, _theirs, CardRepository.instance.byCode);

  Future<void> _tapSlot(CalcSlot slot, {required bool mine}) async {
    if (slot.isEmpty) {
      final List<Deck> decks = context.read<AppState>().decks;
      final String? code = await pickCard(
        context,
        title: tr('放进场上'),
        decks: decks.isEmpty ? null : decks,
      );
      if (code == null || !mounted) return;
      setState(() {
        slot.code = code;
        _recompute(); // 上卡即自动算
      });
      return;
    }
    if (!mounted) return;
    await _openSlotSheet(slot, mine: mine);
  }

  Future<void> _confirmClear() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('清空场上？')),
        content: Text(tr('双方场地上的卡、充能、储存区和所有修正都会清掉。')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('清空')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _mine.clear();
      _theirs.clear();
    });
  }

  /// 格子的详细面板：看基础值 / 看当前值 / 管修正 / 充能 / 拿掉卡
  Future<void> _openSlotSheet(CalcSlot slot, {required bool mine}) async {
    _removedMod = null;
    await showGlassSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final LyceeCard? card = _cardOf(slot);
          final CalcValues base = baseOf(card);
          final CalcValues cur = currentOf(slot, card);
          final int? chargeMax = EffectParser.chargeMaxOf(card);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
            child: SizedBox(
              height: MediaQuery.sizeOf(c).height * 0.86,
              child: Column(
                children: [
                  ListTile(
                    title: Text(card?.displayName ?? (slot.code ?? '')),
                    subtitle: Text(
                      '${card?.code ?? ''}'
                      '${(card?.series ?? '').isEmpty ? '' : ' · ${card!.series}'}',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: _StatRow(base: base, cur: cur, large: true),
                  ),
                  // 充能（チャージ）：卡下面压了几张，用来支付 C 图标
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Row(
                      children: [
                        Text(tr('充能'),
                            style: Theme.of(c).textTheme.labelLarge),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            chargeMax == null
                                ? tr('卡面没写上限，随便记')
                                : tr('上限 {0} 张', ['$chargeMax']),
                            style: Theme.of(c).textTheme.bodySmall,
                          ),
                        ),
                        IconButton(
                          tooltip: tr('减一张'),
                          visualDensity: VisualDensity.compact,
                          onPressed: slot.charge <= 0
                              ? null
                              : () => setSheet(() => slot.charge--),
                          icon:
                              const Icon(Icons.remove_circle_outline, size: 20),
                        ),
                        Text('${slot.charge}',
                            style: Theme.of(c).textTheme.titleMedium),
                        IconButton(
                          tooltip: chargeMax != null && slot.charge >= chargeMax
                              ? tr('到上限了（{0} 张）', ['$chargeMax'])
                              : tr('加一张'),
                          visualDensity: VisualDensity.compact,
                          // 卡面写了上限就挡住：比上限还多的充能是不存在的状态，
                          // 记错了局内数值就跟着错。认不出上限的卡则不挡 ——
                          // 那种卡还有一百来张，不能因此让玩家没法记。
                          onPressed:
                              chargeMax != null && slot.charge >= chargeMax
                                  ? null
                                  : () => setSheet(() => slot.charge++),
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                        ),
                      ],
                    ),
                  ),
                  // 储存区（置き場）：和充能一样**挂在这一张卡下面**，
                  // 不是双方共用一个池子 —— 谁开的置き場、里面几张，
                  // 都跟着这张卡走，所以放在格子面板里管。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                    child: Row(
                      children: [
                        Text(tr('储存区'),
                            style: Theme.of(c).textTheme.labelLarge),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('这张卡下面的「〜置き場」'),
                            style: Theme.of(c).textTheme.bodySmall,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _addZone(slot, card, setSheet),
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(tr('新建')),
                        ),
                      ],
                    ),
                  ),
                  if (slot.zones.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr('还没有储存区'),
                          style: Theme.of(c).textTheme.bodySmall,
                        ),
                      ),
                    )
                  else
                    for (final CalcZone z in slot.zones)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                z.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(c).textTheme.bodyMedium,
                              ),
                            ),
                            IconButton(
                              tooltip: tr('储存减一'),
                              visualDensity: VisualDensity.compact,
                              onPressed: z.count <= 0
                                  ? null
                                  : () => setSheet(() => z.count--),
                              icon: const Icon(Icons.remove_circle_outline,
                                  size: 20),
                            ),
                            Text('${z.count}',
                                style: Theme.of(c).textTheme.titleMedium),
                            IconButton(
                              tooltip: tr('储存加一'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setSheet(() => z.count++),
                              icon: const Icon(Icons.add_circle_outline,
                                  size: 20),
                            ),
                            IconButton(
                              tooltip: tr('删掉这个储存区'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  setSheet(() => slot.zones.remove(z)),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ],
                        ),
                      ),
                  const Divider(height: 1),
                  // 效果自动计算：列出这张卡的数值效果，逐条套用
                  if (card != null)
                    _EffectPanel(
                      card: card,
                      appliedOf: (EffectBonus b) => _appliedFrom(slot, b),
                      onApply: (EffectBonus b) => _applyBonus(
                        b,
                        slot: slot,
                        mine: mine,
                        setSheet: setSheet,
                      ),
                      onUndo: (EffectBonus b) =>
                          setSheet(() => _undoFrom(slot, b)),
                      onApplyAll: () =>
                          _applyAllRest(card, slot, mine, setSheet),
                    ),
                  // 删错了的撤销入口：放在面板里，别用 SnackBar（会被面板盖住）
                  if (_removedMod != null && identical(_removedFrom, slot))
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              tr('已删掉一条修正'),
                              style: Theme.of(c).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => _undoDelete(slot, setSheet),
                            child: Text(tr('撤销删除')),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: !slot.hasMods
                        ? Center(
                            child: Text(
                              tr('还没有修正。放上卡就自动算了；也可以手动加一条。'),
                              style: Theme.of(c).textTheme.bodyMedium,
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            children: [
                              for (final CalcPhase p in CalcPhase.values)
                                ..._modRowsOf(slot, p, setSheet),
                            ],
                          ),
                  ),
                  const Divider(height: 1),
                  _AddModPanel(
                    onAdd: (CalcMod m) => setSheet(() => slot.mods.add(m)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: TextButton.icon(
                        onPressed: () {
                          setSheet(() {
                            slot.clear();
                            _recompute(); // 它的效果也要从别人身上收回去
                          });
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: Text(tr('拿掉这张卡')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  /// 把一条效果落到场上。
  ///
  /// 三种情况分开处理，**绝不替玩家猜目标**：
  /// ① 含变量 → 加一条空数值的修正，让玩家填；
  /// ② 目标能定（自身 / 全体）→ 直接套用；
  /// ③ 目标要指定（我方 1 体 / 对方 1 体）→ 弹场上选卡。
  Future<void> _applyBonus(
    EffectBonus b, {
    required CalcSlot slot,
    required bool mine,
    required void Function(void Function()) setSheet,
  }) async {
    final LyceeCard? src = _cardOf(slot);
    final String name = src?.displayName ?? (slot.code ?? '');

    if (b.hasVariable) {
      setSheet(() {
        slot.mods.add(CalcMod(
          phase: b.phase,
          label: tr('{0} 的效果（数值待填）：{1}', [name, b.variableNote]),
          source: CalcModSource.effect,
          effectRaw: b.raw,
          sourceCode: b.sourceCode,
        ));
      });
      return;
    }

    List<CalcSlot> targets = _targetsOf(b.target, slot: slot, mine: mine);
    if (targets.isEmpty) {
      final bool toEnemy = b.target == EffectTarget.enemyOne ||
          b.target == EffectTarget.enemyAll;
      final CalcSide ally = mine ? _mine : _theirs;
      final CalcSide foe = mine ? _theirs : _mine;
      // 写明了是哪一方就只列那一边；**目标待定**（「キャラ１体に」这种）两边
      // 都列 —— 目标本来就可能在对面的场上，只给我方会逼玩家白点一次。
      final List<(String, CalcSide)> sections = toEnemy
          ? <(String, CalcSide)>[(tr('对方'), foe)]
          : b.target == EffectTarget.unknown
              ? <(String, CalcSide)>[(tr('我方'), ally), (tr('对方'), foe)]
              : <(String, CalcSide)>[(tr('我方'), ally)];
      final CalcSlot? picked = await _pickSlotOnField(
        sections: sections,
        title: toEnemy
            ? tr('选对方场上的一张')
            : b.target == EffectTarget.unknown
                ? tr('选一张场上卡')
                : tr('选我方场上的一张'),
      );
      if (picked == null) return;
      targets = <CalcSlot>[picked];
    }
    setSheet(() {
      for (final CalcSlot t in targets) {
        EffectParser.applyBonus(t, b, name,
            source: CalcModSource.effect, sourceSlot: slot);
      }
    });
  }

  /// 效果目标 → 实际格子
  List<CalcSlot> _targetsOf(
    EffectTarget t, {
    required CalcSlot slot,
    required bool mine,
  }) {
    final CalcSide ally = mine ? _mine : _theirs;
    final CalcSide enemy = mine ? _theirs : _mine;
    return EffectParser.resolveTargets(
      t,
      source: slot,
      allyAf: ally.af,
      allyDf: ally.df,
      enemyAf: enemy.af,
      enemyDf: enemy.df,
    );
  }

  /// 让玩家在场上点选一格（用于「我方 1 体」「对方 1 体」「目标待定」）
  ///
  /// [sections] 是「标题 + 那一方」的列表：目标写明了哪一方就只给那一边，
  /// 目标待定就把两边都列出来。
  Future<CalcSlot?> _pickSlotOnField({
    required List<(String, CalcSide)> sections,
    required String title,
  }) async {
    final List<(String, CalcSlot)> items = <(String, CalcSlot)>[];
    for (final (String label, CalcSide side) in sections) {
      for (final CalcSlot s in side.all) {
        if (!s.isEmpty) items.add((label, s));
      }
    }
    if (items.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('场上还没有卡'))),
        );
      }
      return null;
    }
    final bool showSide = sections.length > 1;
    return showGlassSheet<CalcSlot>(
      context: context,
      showDragHandle: true,
      builder: (c) => SizedBox(
        height: MediaQuery.sizeOf(c).height * 0.55,
        child: Column(
          children: [
            ListTile(title: Text(title)),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, kBottomBarSpace),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2 / 3,
                ),
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final (String sideName, CalcSlot s) = items[i];
                  final LyceeCard? card = _cardOf(s);
                  final CalcValues v = currentOf(s, card);
                  return InkWell(
                    onTap: () => Navigator.pop(c, s),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: card == null
                              ? const SizedBox.expand()
                              : CardArt(card: card),
                        ),
                        // 两边都列的时候，得看得出哪张是哪一边的
                        if (showSide)
                          Positioned(
                            top: 2,
                            left: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              color: Theme.of(c)
                                  .colorScheme
                                  .surface
                                  .withValues(alpha: 0.85),
                              child: Text(sideName,
                                  style: const TextStyle(fontSize: 9)),
                            ),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            color: Theme.of(c)
                                .colorScheme
                                .surface
                                .withValues(alpha: 0.8),
                            child: Text(
                              'AP${v.ap} DP${v.dp}',
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 改一条修正的数值/说明 —— 「可以查看、修改每一步」
  ///
  /// ⚠ 这里刻意**不用 TextEditingController**：对话框关闭有退场动画，
  /// 动画期间 TextField 还在引用 controller，等到 `await showDialog` 返回时
  /// 再 dispose 会抛「used after being disposed」，不 dispose 又泄漏。
  /// 用 onChanged 把文本收进局部变量最稳。
  Future<void> _editMod(
    CalcMod mod,
    void Function(void Function()) setSheet, {
    CalcSlot? slot,
  }) async {
    String label = mod.label;
    CalcPhase phase = mod.phase;
    final Map<String, int> values = <String, int>{
      'AP': mod.ap,
      'DP': mod.dp,
      'SP': mod.sp,
      'DMG': mod.dmg,
    };
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('修改这条修正')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mod.effectRaw.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    tr('效果原文：{0}', [mod.effectRaw]),
                    style: Theme.of(c).textTheme.bodySmall,
                  ),
                ),
              TextField(
                // 同说明框：不用 controller，避免生命周期问题。
                // 现有文字用 hintText 回显 —— 拿不到 controller 也不能让玩家
                // 看不见原来写的是什么（改完才发现改错了最难受）。
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('说明'),
                  hintText: mod.label.isEmpty ? null : mod.label,
                ),
                onChanged: (v) => label = v,
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child:
                    Text(tr('时机'), style: Theme.of(c).textTheme.labelMedium),
              ),
              const SizedBox(height: 4),
              // 时机也能改：改错了不该逼玩家删了重建
              _PhasePicker(
                value: phase,
                onChanged: (CalcPhase p) => phase = p,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final String k in <String>['AP', 'DP', 'SP', 'DMG']) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            labelText: k,
                            hintText: '${values[k]}',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                          ),
                          onChanged: (v) =>
                              values[k] = int.tryParse(v.trim()) ?? 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              setSheet(() {
                mod.label = label.trim();
                mod.phase = phase;
                mod.ap = values['AP'] ?? 0;
                mod.dp = values['DP'] ?? 0;
                mod.sp = values['SP'] ?? 0;
                mod.dmg = values['DMG'] ?? 0;
                // 自动算出来的条目改过之后要留档 —— 否则下次重算
                // 会把玩家的修改覆盖掉
                if (mod.source == CalcModSource.auto && mod.key.isNotEmpty) {
                  slot?.autoOverrides[mod.key] = mod;
                }
              });
              Navigator.pop(c);
            },
            child: Text(tr('保存')),
          ),
        ],
      ),
    );
  }

  static String _deltaText(CalcMod m) {
    final List<String> parts = <String>[];
    if (m.ap != 0) parts.add('AP${CalcMod.signed(m.ap)}');
    if (m.dp != 0) parts.add('DP${CalcMod.signed(m.dp)}');
    if (m.sp != 0) parts.add('SP${CalcMod.signed(m.sp)}');
    if (m.dmg != 0) parts.add('DMG${CalcMod.signed(m.dmg)}');
    return parts.isEmpty ? tr('没有数值') : parts.join('  ');
  }

  /// 某个时机下的修正行（手动 + 自动一起列）。
  ///
  /// 自动条目也允许改/删：改过的记进 [CalcSlot.autoOverrides]，
  /// 删掉的记进 [CalcSlot.autoSuppressed]，下次重算不会把玩家的意见盖掉。
  List<Widget> _modRowsOf(
    CalcSlot slot,
    CalcPhase p,
    void Function(void Function()) setSheet,
  ) {
    final List<CalcMod> list = <CalcMod>[
      ...slot.mods.where((CalcMod m) => m.phase == p),
      ...slot.autoMods.where((CalcMod m) => m.phase == p),
    ];
    if (list.isEmpty) return const <Widget>[];
    return <Widget>[
      _PhaseHeader(phase: p, sum: modsOfPhase(slot, p)),
      for (final CalcMod m in list)
        _ModRow(
          mod: m,
          onEdit: () => _editMod(m, setSheet, slot: slot),
          onDelete: () => _deleteMod(m, slot, setSheet),
        ),
    ];
  }

  /// 删一条修正 —— 删错了能撤销。
  ///
  /// 局内手滑删掉一条手动修正很烦；自动条目删掉会被记进 suppressed，
  /// 反悔了得手动加回来，所以这里也一起兜住。
  ///
  /// ⚠ 撤销入口**必须放在这个面板里**，不能用 SnackBar：面板本身就铺在
  /// 屏幕下半部，SnackBar 会被它整个盖住 —— 提示看得见、按钮点不到。
  void _deleteMod(
    CalcMod m,
    CalcSlot slot,
    void Function(void Function()) setSheet,
  ) {
    final bool isAuto = m.source == CalcModSource.auto && m.key.isNotEmpty;
    setSheet(() {
      _removedMod = m;
      _removedFrom = slot;
      _removedOverride = isAuto ? slot.autoOverrides[m.key] : null;
      _removedAt = isAuto ? slot.autoMods.indexOf(m) : slot.mods.indexOf(m);
      if (isAuto) {
        slot.autoSuppressed.add(m.key);
        slot.autoOverrides.remove(m.key);
      }
      slot.mods.remove(m);
      slot.autoMods.remove(m);
    });
  }

  /// 把刚删掉的那条放回去（面板顶上的「撤销删除」）
  void _undoDelete(CalcSlot slot, void Function(void Function()) setSheet) {
    final CalcMod? m = _removedMod;
    if (m == null) return;
    setSheet(() {
      final bool isAuto = m.source == CalcModSource.auto && m.key.isNotEmpty;
      if (isAuto) {
        slot.autoSuppressed.remove(m.key);
        final CalcMod? o = _removedOverride;
        if (o != null) slot.autoOverrides[m.key] = o;
      }
      final List<CalcMod> list = isAuto ? slot.autoMods : slot.mods;
      if (_removedAt >= 0 && _removedAt <= list.length) {
        list.insert(_removedAt, m);
      } else {
        list.add(m);
      }
      _removedMod = null;
      _removedOverride = null;
      _removedAt = -1;
    });
  }

  /// 这条效果**是不是从这一格**算上去的（自动算上的 + 手动套用的都算）。
  ///
  /// ⚠ 必须连来源格子一起比：场上同时放着两张同编号的卡时，只比
  /// 「卡号 + 原文」会让两张卡的面板都显示「已算上」，撤一张还会把另一张
  /// 的加成一起撤掉。
  bool _appliedFrom(CalcSlot source, EffectBonus b) {
    for (final CalcSlot s in <CalcSlot>[..._mine.all, ..._theirs.all]) {
      for (final CalcMod m in <CalcMod>[...s.mods, ...s.autoMods]) {
        if (m.sourceCode == b.sourceCode &&
            m.effectRaw == b.raw &&
            identical(m.sourceSlot, source)) {
          return true;
        }
      }
    }
    return false;
  }

  /// 撤销**这一格**的一条效果：把场上由它产生的那几条修正都拿掉。
  ///
  /// 自动算上的那部分要记进 suppressed，否则下一次重算又补回来了。
  void _undoFrom(CalcSlot source, EffectBonus b) {
    bool match(CalcMod m) =>
        m.sourceCode == b.sourceCode &&
        m.effectRaw == b.raw &&
        identical(m.sourceSlot, source);
    for (final CalcSlot s in <CalcSlot>[..._mine.all, ..._theirs.all]) {
      s.mods.removeWhere(match);
      final List<CalcMod> gone = s.autoMods.where(match).toList();
      for (final CalcMod m in gone) {
        if (m.key.isNotEmpty) s.autoSuppressed.add(m.key);
        s.autoOverrides.remove(m.key);
        s.autoMods.remove(m);
      }
    }
  }

  /// 效果目标是「能直接定下来的那几种」—— 自身 / 全体类。
  static bool _resolvable(EffectTarget t) =>
      t == EffectTarget.self ||
      t == EffectTarget.allyAll ||
      t == EffectTarget.allyAfAll ||
      t == EffectTarget.allyDfAll ||
      t == EffectTarget.enemyAll;

  /// 一键把这张卡剩下能算的效果全部算上（含带条件、要发动的）。
  ///
  /// 自动算值只敢套「确定生效」的那部分，剩下的在这里让玩家**一次确认**：
  /// 点了就等于说「这些现在都生效」。目标要指定单体（我方 1 体 / 对方 1 体）
  /// 的仍然得逐个点 —— 那属于不能替你猜的部分。
  void _applyAllRest(
    LyceeCard card,
    CalcSlot slot,
    bool mine,
    void Function(void Function()) setSheet,
  ) {
    final String name = card.displayName;
    setSheet(() {
      for (final EffectBonus b in EffectParser.parse(card)) {
        if (b.hasVariable || !_resolvable(b.target)) continue;
        if (_appliedFrom(slot, b)) continue;
        final List<CalcSlot> targets =
            _targetsOf(b.target, slot: slot, mine: mine);
        if (targets.isEmpty) continue;
        for (final CalcSlot t in targets) {
          EffectParser.applyBonus(t, b, name,
              source: CalcModSource.effect, sourceSlot: slot);
        }
      }
    });
  }

  Widget _field(String title, CalcSide side, {required bool mine}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                tr('{0} 张在场', ['${side.occupied}']),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        _row(side.af, mine: mine),
        const SizedBox(height: 6),
        _row(side.df, mine: mine),
      ],
    );
  }

  Widget _row(List<CalcSlot> slots, {required bool mine}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < slots.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _SlotBox(
                key: slots[i].code == null
                    ? null
                    : ValueKey<String>('calc_slot_${slots[i].code}'),
                slot: slots[i],
                card: _cardOf(slots[i]),
                onTap: () => _tapSlot(slots[i], mine: mine),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 给**这张卡**新建一个储存区（置き場）。
  ///
  /// 卡面里写到的「〜」置き場会先列出来当建议 —— 一张卡可能同时开好几个
  /// 置き場，名字也五花八门，所以允许多个、也允许自己手填。
  Future<void> _addZone(
    CalcSlot slot,
    LyceeCard? card,
    void Function(void Function()) setSheet,
  ) async {
    // ⚠ 不用 TextEditingController：showDialog 的 Future 在 pop 时就完成，
    // 但对话框的退场动画还在跑、widget 还在引用 controller ——
    // await 之后立刻 dispose 必然抛「used after being disposed」。
    // 用 onChanged 收文本，绕开整个生命周期问题。
    final List<String> suggested = EffectParser.storageNamesOf(card);
    String input = '';
    final String? result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('新建储存区')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (suggested.isNotEmpty) ...[
              Text(
                tr('卡面写到的置き場（点一下直接用）：'),
                style: Theme.of(c).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final String n in suggested)
                    LyTag(label: n, onTap: () => Navigator.pop(c, n)),
                ],
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              key: const ValueKey<String>('zone_name_field'),
              autofocus: suggested.isEmpty,
              decoration: InputDecoration(
                hintText: tr('名字（例：迷宮 / 経験値 / 卒業）'),
              ),
              onChanged: (v) => input = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, input.trim()),
            child: Text(tr('建')),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final String zoneName = result;
    setSheet(() => slot.zones.add(CalcZone(name: zoneName)));
  }

  @override
  Widget build(BuildContext context) {
    return BgScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(tr('计算器')),
        actions: [
          IconButton(
            tooltip: tr('清空'),
            onPressed: _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kBottomBarSpace),
        children: [
          _Summary(
            mineTotal: sideTotal(_mine, CardRepository.instance.byCode),
            theirsTotal: sideTotal(_theirs, CardRepository.instance.byCode),
            minePhases: <CalcPhase, CalcValues>{
              for (final CalcPhase p in CalcPhase.values)
                p: sideModsOfPhase(_mine, p),
            },
            theirsPhases: <CalcPhase, CalcValues>{
              for (final CalcPhase p in CalcPhase.values)
                p: sideModsOfPhase(_theirs, p),
            },
          ),
          _field(tr('对方场地'), _theirs, mine: false),
          const Divider(height: 24),
          _field(tr('我方场地'), _mine, mine: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              tr('点空格放牌（可从卡组挑）；放上去就自动算效果。点场上的牌可以改数值、记充能/储存区。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// 效果面板：列出这张卡的数值效果，逐条套用
///
/// 已经自动算上的条目显示成「已算上」+「撤销」—— 免得同一张卡
/// 被手动点两次而重复计数。
class _EffectPanel extends StatelessWidget {
  const _EffectPanel({
    required this.card,
    required this.appliedOf,
    required this.onApply,
    required this.onUndo,
    required this.onApplyAll,
  });

  final LyceeCard card;
  final bool Function(EffectBonus) appliedOf;
  final void Function(EffectBonus) onApply;
  final void Function(EffectBonus) onUndo;
  final VoidCallback onApplyAll;

  @override
  Widget build(BuildContext context) {
    final List<EffectBonus> bonuses = EffectParser.parse(card);
    if (bonuses.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme cs = Theme.of(context).colorScheme;
    final int rest = bonuses
        .where((EffectBonus b) =>
            !b.hasVariable &&
            _CalcPageState._resolvable(b.target) &&
            !appliedOf(b))
        .length;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                tr('这张卡的数值效果'),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                tr('{0} 条', ['${bonuses.length}']),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final EffectBonus b in bonuses)
                  _EffectBonusRow(
                    bonus: b,
                    applied: appliedOf(b),
                    onApply: () => onApply(b),
                    onUndo: () => onUndo(b),
                  ),
              ],
            ),
          ),
          if (rest > 0)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onApplyAll,
                icon: const Icon(Icons.playlist_add_check, size: 16),
                label: Text(tr('剩下 {0} 条全部算上', ['$rest'])),
              ),
            ),
        ],
      ),
    );
  }
}

/// 效果条目一行：说明 + 「套用」/「撤销」
class _EffectBonusRow extends StatelessWidget {
  const _EffectBonusRow({
    required this.bonus,
    required this.applied,
    required this.onApply,
    required this.onUndo,
  });

  final EffectBonus bonus;
  final bool applied;
  final VoidCallback onApply;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String note = applied
        ? tr('已算上')
        : bonus.hasVariable
            ? tr('含变量，需手填')
            : bonus.activated
                ? tr('要用才生效，自己确认')
                : bonus.conditional
                    ? tr('有条件，需确认')
                    : tr('会自动算上');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(bonus.summary,
                    style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  note,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: applied
                            ? cs.primary
                            : (bonus.isAutoApplicable
                                ? cs.primary
                                : cs.onSurfaceVariant),
                      ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: applied ? onUndo : onApply,
            child: Text(applied ? tr('撤销') : tr('套用')),
          ),
        ],
      ),
    );
  }
}

/// 时机选择（自己管状态：放在对话框里也要点一下立刻变样）
class _PhasePicker extends StatefulWidget {
  const _PhasePicker({required this.value, required this.onChanged});

  final CalcPhase value;
  final ValueChanged<CalcPhase> onChanged;

  @override
  State<_PhasePicker> createState() => _PhasePickerState();
}

class _PhasePickerState extends State<_PhasePicker> {
  late CalcPhase _sel = widget.value;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final CalcPhase p in CalcPhase.values)
          LyTag(
            label: kCalcPhaseNames[p]!,
            selected: _sel == p,
            onTap: () {
              setState(() => _sel = p);
              widget.onChanged(p);
            },
          ),
      ],
    );
  }
}

/// 修正条目一行：说明 + 数值 + 来源 + 改/删
class _ModRow extends StatelessWidget {
  const _ModRow({
    required this.mod,
    required this.onEdit,
    required this.onDelete,
  });

  final CalcMod mod;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        mod.label.isEmpty ? tr('（未写说明）') : mod.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          if (mod.source != CalcModSource.manual) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                kCalcModSourceNames[mod.source] ?? '',
                style: TextStyle(fontSize: 9, color: cs.primary),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(_CalcPageState._deltaText(mod))),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tr('改这条'),
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: tr('删掉这条'),
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// 顶部合计：双方当前数值 + 各时机修正的贡献
class _Summary extends StatelessWidget {
  const _Summary({
    required this.mineTotal,
    required this.theirsTotal,
    required this.minePhases,
    required this.theirsPhases,
  });

  final CalcValues mineTotal;
  final CalcValues theirsTotal;
  final Map<CalcPhase, CalcValues> minePhases;
  final Map<CalcPhase, CalcValues> theirsPhases;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sideRow(context, tr('我方场上'), mineTotal, minePhases),
          const SizedBox(height: 8),
          _sideRow(context, tr('对方场上'), theirsTotal, theirsPhases),
        ],
      ),
    );
  }

  Widget _sideRow(
    BuildContext context,
    String title,
    CalcValues total,
    Map<CalcPhase, CalcValues> phases,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatRow(
                base: calcZero,
                cur: total,
                // 合计只给 AP/DP：SP、DMG 是每张卡自己的值
                show: const <String>['AP', 'DP'],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 2),
          child: Text(
            _phaseSummary(phases),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  static const CalcValues calcZero = CalcValues.zero;

  /// 「修正 上回合 +2 / 此回合 −3」——只列有值的时机
  String _phaseSummary(Map<CalcPhase, CalcValues> phases) {
    final List<String> parts = <String>[];
    for (final CalcPhase p in CalcPhase.values) {
      final CalcValues v = phases[p] ?? CalcValues.zero;
      if (v.isZero) continue;
      final List<String> one = <String>[];
      if (v.ap != 0) one.add('AP${CalcMod.signed(v.ap)}');
      if (v.dp != 0) one.add('DP${CalcMod.signed(v.dp)}');
      if (v.sp != 0) one.add('SP${CalcMod.signed(v.sp)}');
      if (v.dmg != 0) one.add('DMG${CalcMod.signed(v.dmg)}');
      parts.add('${kCalcPhaseNames[p]} ${one.join(' ')}');
    }
    if (parts.isEmpty) return tr('场上还没有修正');
    return '${tr('修正')} ${parts.join(' / ')}';
  }
}

/// 四个数值的并排显示：大的当前值 + 小的增减量
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.base,
    required this.cur,
    this.large = false,
    this.show = const <String>['AP', 'DP', 'SP', 'DMG'],
  });

  final CalcValues base;
  final CalcValues cur;
  final bool large;

  /// 只显示这几个数值。顶部「场上合计」只给 AP/DP —— SP 和 DMG 是
  /// **每张卡各自**的值（DMG 尤其如此，它是攻击力），几方的加到一起没意义。
  final List<String> show;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (String label, int b, int c) in <(String, int, int)>[
          ('AP', base.ap, cur.ap),
          ('DP', base.dp, cur.dp),
          ('SP', base.sp, cur.sp),
          ('DMG', base.dmg, cur.dmg),
        ])
          if (show.contains(label)) ...[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$c',
                      style: (large
                              ? Theme.of(context).textTheme.headlineSmall
                              : Theme.of(context).textTheme.titleMedium)
                          ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c != b
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    if (c != b) ...[
                      const SizedBox(width: 4),
                      Text(
                        CalcMod.signed(c - b),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: c - b > 0
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.error,
                            ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 一个格子
class _SlotBox extends StatelessWidget {
  const _SlotBox({
    super.key,
    required this.slot,
    required this.card,
    required this.onTap,
  });

  final CalcSlot slot;
  final LyceeCard? card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (slot.isEmpty) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 132,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Icon(Icons.add, color: cs.outline, size: 22),
        ),
      );
    }

    final CalcValues base = baseOf(card);
    final CalcValues cur = currentOf(slot, card);
    final bool changed = cur != base;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: card == null
                ? Container(
                    height: 132,
                    alignment: Alignment.center,
                    child: Text(slot.code ?? '',
                        style: const TextStyle(fontSize: 10)),
                  )
                : CardArt(card: card!),
          ),
          // 卡下面压着的东西：充能 + 各储存区（置き場）—— 和充能一样
          // 都挂在这一张卡上，各自显示张数
          if (slot.underCount > 0)
            Positioned(
              top: 4,
              left: 4,
              right: 46,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (slot.charge > 0)
                    _UnderBadge(
                      text: tr('充能{0}', ['${slot.charge}']),
                      bg: cs.secondaryContainer,
                      fg: cs.onSecondaryContainer,
                    ),
                  for (final CalcZone z in slot.zones)
                    _UnderBadge(
                      text: '${z.name} ${z.count}',
                      bg: cs.tertiaryContainer,
                      fg: cs.onTertiaryContainer,
                    ),
                ],
              ),
            ),
          if (changed)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tr('有修正'),
                  style: TextStyle(fontSize: 9, color: cs.onPrimary),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.78),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: Text(
                'AP${cur.ap} DP${cur.dp} SP${cur.sp} DMG${cur.dmg}',
                style: TextStyle(
                  fontSize: 9,
                  height: 1.25,
                  color: changed ? cs.primary : cs.onSurface,
                  fontWeight: changed ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡下面压着的东西的小标签（充能 / 储存区）
class _UnderBadge extends StatelessWidget {
  const _UnderBadge({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 9, color: fg),
      ),
    );
  }
}

class _PhaseHeader extends StatelessWidget {
  const _PhaseHeader({required this.phase, required this.sum});

  final CalcPhase phase;
  final CalcValues sum;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Text(
        '${kCalcPhaseNames[phase]}  ${_CalcPageState._deltaText(CalcMod(
          phase: phase,
          ap: sum.ap,
          dp: sum.dp,
          sp: sum.sp,
          dmg: sum.dmg,
        ))}',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 面板底部的新增修正：选时机 + 写说明 + 填四个数值
class _AddModPanel extends StatefulWidget {
  const _AddModPanel({required this.onAdd});

  final void Function(CalcMod mod) onAdd;

  @override
  State<_AddModPanel> createState() => _AddModPanelState();
}

class _AddModPanelState extends State<_AddModPanel> {
  CalcPhase _phase = CalcPhase.thisTurn;
  final TextEditingController _label = TextEditingController();
  final Map<String, TextEditingController> _v = <String, TextEditingController>{
    'AP': TextEditingController(),
    'DP': TextEditingController(),
    'SP': TextEditingController(),
    'DMG': TextEditingController(),
  };

  @override
  void dispose() {
    _label.dispose();
    for (final TextEditingController c in _v.values) {
      c.dispose();
    }
    super.dispose();
  }

  int _intOf(String k) => int.tryParse(_v[k]!.text.trim()) ?? 0;

  void _submit() {
    final CalcMod m = CalcMod(
      phase: _phase,
      label: _label.text.trim(),
      ap: _intOf('AP'),
      dp: _intOf('DP'),
      sp: _intOf('SP'),
      dmg: _intOf('DMG'),
    );
    if (m.isZero && m.label.isEmpty) return; // 空条目不加
    widget.onAdd(m);
    setState(() {
      _label.clear();
      for (final TextEditingController c in _v.values) {
        c.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              tr('加一条修正'),
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
          // 时机用 LyTag 选（项目里禁用 SegmentedButton / Chip 系列：
          // 前者高亮块和外框永远对不齐，后者去不掉自带的 surface 底）
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final CalcPhase p in CalcPhase.values)
                LyTag(
                  label: kCalcPhaseNames[p]!,
                  selected: _phase == p,
                  onTap: () => setState(() => _phase = p),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _label,
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('说明（可留空，例：XX 的效果）'),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final String k in <String>['AP', 'DP', 'SP', 'DMG']) ...[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: TextField(
                      controller: _v[k],
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: k,
                        hintText: '0',
                      ),
                    ),
                  ),
                ),
              ],
              FilledButton(
                onPressed: _submit,
                child: Text(tr('加')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
