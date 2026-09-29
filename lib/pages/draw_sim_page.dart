import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../data/draw_sim.dart';
import '../state/app_state.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/card_art.dart';
import '../widgets/glass.dart';
import '../widgets/layout.dart';
import '../l10n/l10n.dart';

/// 起手模拟（要求 L86 / L87）
///
/// · 先手抽 8 张 / 后手抽 9 张
/// · 可以换牌（选中不想要的换掉重抽）、也可以"再摸一张"
/// · 点手牌里的卡把它设为"关注牌"，实时算出起手至少摸到一张的概率
class DrawSimPage extends StatefulWidget {
  const DrawSimPage({super.key, required this.deck});

  final Deck deck;

  @override
  State<DrawSimPage> createState() => _DrawSimPageState();
}

class _DrawSimPageState extends State<DrawSimPage> {
  late DrawSim _sim;
  int _dealSize = 8; // 8 = 先手，9 = 后手
  final Set<String> _pick = {}; // 手牌里选中的（准备换掉）
  final Set<String> _watch = {}; // 关注牌（算概率用）
  int _seed = 0;

  @override
  void initState() {
    super.initState();
    _reshuffle();
  }

  void _reshuffle() {
    _seed = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;
    _sim = DrawSim(widget.deck.cards, seed: _seed)..deal(_dealSize);
    _pick.clear();
  }

  void _setSize(int n) {
    setState(() {
      _dealSize = n;
      _reshuffle();
    });
  }

  void _mulligan() {
    if (_pick.isEmpty) return;
    setState(() {
      final n = _sim.mulligan(_pick.toList());
      _pick.clear();
      if (n > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('换掉 {0} 张，已补抽', [n]))));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = CardRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    final fullDeck = widget.deck.cards;

    // ── 关注牌的概率（超几何分布）──
    final total = _sim.deckSize;
    var watchCards = 0;
    for (final c in _watch) {
      watchCards += fullDeck[c] ?? 0;
    }
    final p8 = DrawSim.probAtLeastOne(
        deckSize: total, targets: watchCards, drawCount: 8);
    final p9 = DrawSim.probAtLeastOne(
        deckSize: total, targets: watchCards, drawCount: 9);
    final pNow = DrawSim.probAtLeastOne(
        deckSize: total, targets: watchCards, drawCount: _dealSize);

    return BgScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(tr('起手模拟')),
        actions: [
          IconButton(
            tooltip: tr('重新洗牌'),
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(_reshuffle),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, kBottomBarSpace),
        children: [
          // 先手 / 后手
          Row(
            children: [
              _seg(tr('先手 8 张'), _dealSize == 8, () => _setSize(8)),
              const SizedBox(width: 8),
              _seg(tr('后手 9 张'), _dealSize == 9, () => _setSize(9)),
              const Spacer(),
              Text(tr('牌库剩 {0}', [_sim.remaining]),
                  style: TextStyle(
                      fontSize: 11.5, color: scheme.onSurfaceVariant)),
              if (_sim.mulligans > 0) ...[
                const SizedBox(width: 8),
                Text(tr('已换 {0} 次', [_sim.mulligans]),
                    style: TextStyle(fontSize: 11.5, color: scheme.primary)),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // 手牌
          Text(tr('手牌（点击选中；长按设为关注牌）'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _sim.hand.length; i++)
                _handCard(repo, _sim.hand[i], i, scheme),
            ],
          ),
          const SizedBox(height: 12),

          // 操作
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.swap_horiz, size: 17),
                  label: Text(_pick.isEmpty ? tr('换牌（先选择手牌）') : tr('换掉 {0} 张', [_pick.length])),
                  onPressed: _pick.isEmpty ? null : _mulligan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.add_card, size: 17),
                  label: Text(tr('再摸一张')),
                  onPressed: () => setState(() => _sim.drawOne()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 概率
          Row(
            children: [
              Icon(Icons.calculate_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(tr('摸到关注牌的概率'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 15),
                label: Text(tr('选关注牌')),
                onPressed: () => _pickWatch(context, state),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_watch.isEmpty)
            Text(tr('还没有选关注牌 —— 长按手牌，或点击「选关注牌」'),
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in _watch)
                  _tag('$c ×${fullDeck[c] ?? 0}', true, () {
                    setState(() => _watch.remove(c));
                  }),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(state.cornerRadius),
              ),
              child: Column(
                children: [
                  _probRow(tr('当前 {0} 张起手', [_dealSize]), pNow, scheme),
                  const SizedBox(height: 6),
                  _probRow(tr('先手 8 张'), p8, scheme),
                  const SizedBox(height: 6),
                  _probRow(tr('后手 9 张'), p9, scheme),
                  const SizedBox(height: 8),
                  Text(
                    tr('关注牌共 {0} 张 / 卡组 {1} 张', [watchCards, total]),
                    style:
                        TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _handCard(dynamic repo, String code, int idx, ColorScheme scheme) {
    final card = repo.byCode(code);
    final watched = _watch.contains(code);
    return GestureDetector(
      onTap: () => setState(() {
        // 同名多张：点一张就选中一张（用索引区分）
        final pickedIdx = _pick.toList().indexOf(code);
        if (pickedIdx >= 0) {
          _pick.remove(code);
        } else {
          _pick.add(code);
        }
      }),
      onLongPress: () => setState(() {
        watched ? _watch.remove(code) : _watch.add(code);
      }),
      child: SizedBox(
        width: 84,
        child: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _pick.contains(code)
                      ? scheme.primary
                      : (watched ? scheme.tertiary : Colors.transparent),
                  width: 2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: card == null
                    ? const SizedBox(height: 100)
                    : CardArt(card: card, showName: false),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _probRow(String label, double p, ColorScheme scheme) {
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: Text(
            '${(p * 100).toStringAsFixed(1)}%',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _seg(String label, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? scheme.primary.withValues(alpha: 0.24) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? scheme.primary : scheme.onSurfaceVariant,
            )),
      ),
    );
  }

  Widget _tag(String label, bool on, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? scheme.primary.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: on ? scheme.primary : scheme.onSurfaceVariant)),
      ),
    );
  }

  /// 从卡组里挑关注牌
  Future<void> _pickWatch(BuildContext context, AppState state) async {
    final fullDeck = widget.deck.cards;
    final repo = CardRepository.instance;
    final tmp = Set<String>.from(_watch);
    await showGlassSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(c).height * 0.6,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Text(tr('选关注牌'),
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(tr('共 {0} 张', [tmp.length]),
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(c).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final e in fullDeck.entries)
                        CheckboxListTile(
                          dense: true,
                          value: tmp.contains(e.key),
                          title: Text(
                            repo.byCode(e.key)?.nameZh ??
                                repo.byCode(e.key)?.nameJp ??
                                e.key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(tr('{0} · {1} 张', [e.key, e.value]),
                              style: const TextStyle(fontSize: 11)),
                          onChanged: (on) => setLocal(() {
                            on == true
                                ? tmp.add(e.key)
                                : tmp.remove(e.key);
                          }),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _watch
                            ..clear()
                            ..addAll(tmp);
                        });
                        Navigator.pop(c);
                      },
                      child: Text(tr('确定')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
