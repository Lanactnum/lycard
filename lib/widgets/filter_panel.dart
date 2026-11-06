import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_filter.dart';
import '../data/card_repository.dart';
import '../data/keyword_db.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'tags.dart';
import '../models/lycee_card.dart';
import '../l10n/l10n.dart';

/// 检索页的「筛选」栏（跟搜索并列，改一下就实时刷新结果）。
///
/// 每个分类默认只露前 8 个选项，点「展开」看全部；已勾选的项永远可见，
/// 折叠时也不会被藏起来。
class FilterPanel extends StatefulWidget {
  const FilterPanel({
    super.key,
    required this.filter,
    required this.onChanged,
    this.initialVisible = 8,
  });

  final CardFilter filter;
  final VoidCallback onChanged;
  final int initialVisible;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  final Set<String> _open = {};

  CardFilter get f => widget.filter;

  void _toggle(String key) => setState(() {
        _open.contains(key) ? _open.remove(key) : _open.add(key);
      });

  void _hit() {
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final repo = CardRepository.instance;
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();

    return Glass(
            margin: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      padding: EdgeInsets.fromLTRB(2, f.activeCount > 0 ? 6 : 0, 2, 6),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 没选条件的时候整行都不渲染，免得留一段空位
        if (f.activeCount > 0)
          Row(
            children: [
              Expanded(
                child: Text(
                  tr('已选 {0} 个条件', [f.activeCount]),
                  style: TextStyle(fontSize: 12, color: scheme.primary),
                ),
              ),
              // 预设菜单
              if (state.filterPresets.isNotEmpty)
                PopupMenuButton<String>(
                  icon: Icon(Icons.bookmarks_outlined, size: 20),
                  tooltip: tr('应用预设'),
                  onSelected: (name) {
                    final preset = state.filterPresets.firstWhere((p) => p.name == name);
                    f.clear();
                    f.colors.addAll(preset.filter.colors);
                    f.kinds.addAll(preset.filter.kinds);
                    f.types.addAll(preset.filter.types);
                    f.rarities.addAll(preset.filter.rarities);
                    f.keywords.addAll(preset.filter.keywords);
                    f.costMin = preset.filter.costMin;
                    f.costMax = preset.filter.costMax;
                    f.exMin = preset.filter.exMin;
                    f.exMax = preset.filter.exMax;
                    f.apMin = preset.filter.apMin;
                    f.apMax = preset.filter.apMax;
                    f.dpMin = preset.filter.dpMin;
                    f.dpMax = preset.filter.dpMax;
                    f.spMin = preset.filter.spMin;
                    f.spMax = preset.filter.spMax;
                    f.dmgMin = preset.filter.dmgMin;
                    f.dmgMax = preset.filter.dmgMax;
                    _hit();
                  },
                  itemBuilder: (c) => [
                    for (final p in state.filterPresets)
                      PopupMenuItem(
                        value: p.name,
                        child: Row(
                          children: [
                            Expanded(child: Text(p.name)),
                            IconButton(
                              icon: Icon(Icons.delete_outline, size: 18),
                              onPressed: () {
                                Navigator.pop(c);
                                state.deleteFilterPreset(p.name);
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              IconButton(
                icon: Icon(Icons.bookmark_add_outlined, size: 20),
                tooltip: tr('保存预设'),
                onPressed: () => _savePreset(context, state),
              ),
              TextButton(
                onPressed: () {
                  f.clear();
                  _hit();
                },
                child: Text(tr('清空')),
              ),
            ],
          ),
        _section(tr('属性'), repo.allColors, f.colors, (v) => v),
        _section(tr('卡种'), repo.allKinds, f.kinds, (v) => kKindZh(v) ?? v),
        _section(tr('稀有度'), repo.allRarities, f.rarities, (v) => v),
        _section(tr('类型'), repo.allTypes, f.types, (v) => v),
        _section(
          tr('词条'),
          KeywordDb.instance.all.map((k) => k.zh).toList()..sort(),
          f.keywords,
          (v) => v,
        ),
        _rangeSection(),
      ],
    ),
    );
    }

    Future<void> _savePreset(BuildContext context, AppState state) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('保存筛选预设')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(
          labelText: tr('预设名称'),
          hintText: tr('如：低费雪角色'),
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: Text(tr('保存')),
        ),
      ],
    ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty) {
    state.saveFilterPreset(name, f);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('已保存预设「{0}」', [name]))),
      );
    }
    }
    }

    /// 一个分类：标题 + （前 N 个）选项 + 展开/收起
  Widget _section(
    String title,
    List<String> options,
    Set<String> selected,
    String Function(String) label,
  ) {
    if (options.isEmpty) return const SizedBox.shrink();

    final expanded = _open.contains(title);
    // 已勾选的永远排在前面、永远可见
    final picked = options.where(selected.contains).toList();
    final rest = options.where((o) => !selected.contains(o)).toList();
    final shown = expanded
        ? options
        : [...picked, ...rest.take(widget.initialVisible)];
    final more = options.length - shown.length;

    return _SectionShell(
      title: title,
      trailing: more > 0
          ? TextButton(
              onPressed: () => _toggle(title),
              child: Text(tr('展开（还有 {0}）', [more])),
            )
          : (expanded
              ? TextButton(
                  onPressed: () => _toggle(title),
                  child: Text(tr('收起')),
                )
              : null),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final v in shown)
            LyTag(
              label: label(v),
              dense: true,
              selected: selected.contains(v),
              onTap: () {
                selected.contains(v) ? selected.remove(v) : selected.add(v);
                _hit();
              },
            ),
        ],
      ),
    );
  }

  /// 数值范围（默认收起）
  Widget _rangeSection() {
    final expanded = _open.contains(tr('数值范围'));
    return _SectionShell(
      title: tr('数值范围'),
      trailing: TextButton(
        onPressed: () => _toggle(tr('数值范围')),
        child: Text(expanded ? tr('收起') : tr('展开')),
      ),
      child: expanded
          ? Column(
              children: [
                _range(tr('费用'), f.costMin, f.costMax, (a, b) {
                  f.costMin = a;
                  f.costMax = b;
                }),
                _range('EX', f.exMin, f.exMax, (a, b) {
                  f.exMin = a;
                  f.exMax = b;
                }),
                _range('AP', f.apMin, f.apMax, (a, b) {
                  f.apMin = a;
                  f.apMax = b;
                }),
                _range('DP', f.dpMin, f.dpMax, (a, b) {
                  f.dpMin = a;
                  f.dpMax = b;
                }),
                _range('SP', f.spMin, f.spMax, (a, b) {
                  f.spMin = a;
                  f.spMax = b;
                }),
                _range('DMG', f.dmgMin, f.dmgMax, (a, b) {
                  f.dmgMin = a;
                  f.dmgMax = b;
                }),
              ],
            )
          : const SizedBox.shrink(),
    );
  }

  static const _vals = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15];

  Widget _range(
    String label,
    int? lo,
    int? hi,
    void Function(int? lo, int? hi) set,
  ) {
    return Row(
      children: [
        SizedBox(width: 44, child: Text(label, style: const TextStyle(fontSize: 13))),
        const Text('≥'),
        const SizedBox(width: 4),
        _dd(lo, (v) => set(v, hi)),
        const SizedBox(width: 10),
        const Text('≤'),
        const SizedBox(width: 4),
        _dd(hi, (v) => set(lo, v)),
      ],
    );
  }

  Widget _dd(int? value, void Function(int?) set) {
    return DropdownButton<int?>(
      value: value,
      hint: Text(tr('不限'), style: TextStyle(fontSize: 12)),
      isDense: true,
      style: const TextStyle(fontSize: 13),
      items: [
        DropdownMenuItem(value: null, child: Text(tr('不限'))),
        for (final v in _vals) DropdownMenuItem(value: v, child: Text('$v')),
      ],
      onChanged: (v) {
        set(v);
        _hit();
      },
    );
  }
}

class _SectionShell extends StatelessWidget {
  const _SectionShell({required this.title, this.trailing, required this.child});

  final String title;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: child,
          ),
        ],
      ),
    );
  }
}
