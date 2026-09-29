import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../models/collect_info.dart';
import '../state/app_state.dart';
import '../widgets/rarity_badge.dart';
import '../widgets/glass.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 设置 →「罕贵度角标」：每个罕贵度的颜色 / 模糊 / 透明度
class RarityStylePage extends StatelessWidget {
  const RarityStylePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final rarities = CardRepository.instance.allRarities;

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(tr('罕贵度角标')),
        actions: [
          TextButton(
            onPressed: () {
              for (final r in rarities) {
                state.resetRarityStyle(r);
              }
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(tr('已全部恢复默认配色'))));
            },
            child: Text(tr('恢复默认')),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              tr('在「我的 → 卡组/收藏」里长按卡片，可记录罕贵度/异画。以下为角标显示样式。'),
              style: TextStyle(fontSize: 12, height: 1.6, color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 18),
          for (final r in rarities)
            ListTile(
              leading: SizedBox(
                width: 54,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RarityBadge(text: r, style: state.rarityStyle(r)),
                ),
              ),
              title: Row(
                children: [
                  Text(r),
                  if (state.hasCustomRarityStyle(r))
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(tr('已自定义'),
                          style: TextStyle(
                              fontSize: 10, color: scheme.primary)),
                    ),
                ],
              ),
              subtitle: Text(
                tr('模糊 {0} · 透明度 {1}%', [state.rarityStyle(r).blur.toStringAsFixed(1), (state.rarityStyle(r).opacity * 100).round()]),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: const Icon(Icons.tune, size: 18),
              onTap: () => _edit(context, state, r),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, AppState state, String rarity) async {
    final st = state.rarityStyle(rarity);
    final color = ValueNotifier<Color>(st.color);
    final blur = ValueNotifier<double>(st.blur);
    final opacity = ValueNotifier<double>(st.opacity);

    await showGlassSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('罕贵度 {0} 的角标样式', [rarity]),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ValueListenableBuilder<Color>(
                valueListenable: color,
                builder: (c, col, _) => ValueListenableBuilder<double>(
                  valueListenable: blur,
                  builder: (c, b, _) => ValueListenableBuilder<double>(
                    valueListenable: opacity,
                    builder: (c, o, _) => Row(
                      children: [
                        Text(tr('预览'), style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 10),
                        RarityBadge(
                            text: rarity,
                            style: RarityStyle(color: col, blur: b, opacity: o)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(tr('颜色'), style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              ValueListenableBuilder<Color>(
                valueListenable: color,
                builder: (c, col, _) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _palette)
                      InkWell(
                        onTap: () => color.value = p,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: p,
                            shape: BoxShape.circle,
                            border: Border.all(
                              width: col.toARGB32() == p.toARGB32() ? 3 : 1,
                              color: col.toARGB32() == p.toARGB32()
                                  ? Theme.of(c).colorScheme.primary
                                  : Theme.of(c).colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: blur,
                builder: (c, b, _) => Row(
                  children: [
                    SizedBox(width: 44, child: Text(tr('模糊'), style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: b,
                        max: 12,
                        divisions: 24,
                        label: b.toStringAsFixed(1),
                        onChanged: (v) => blur.value = v,
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<double>(
                valueListenable: opacity,
                builder: (c, o, _) => Row(
                  children: [
                    SizedBox(width: 44, child: Text(tr('透明度'), style: TextStyle(fontSize: 12))),
                    Expanded(
                      child: Slider(
                        value: o,
                        min: 0.1,
                        max: 1,
                        divisions: 18,
                        label: '${(o * 100).round()}%',
                        onChanged: (v) => opacity.value = v,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        state.setRarityStyle(
                          rarity,
                          RarityStyle(
                              color: color.value,
                              blur: blur.value,
                              opacity: opacity.value),
                        );
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.check),
                      label: Text(tr('保存')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () {
                      state.resetRarityStyle(rarity);
                      Navigator.pop(c);
                    },
                    child: Text(tr('默认')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<Color> _palette = [
    Color(0xFF9E9E9E), Color(0xFF7CB342), Color(0xFF29B6F6), Color(0xFF5C6BC0),
    Color(0xFF26A69A), Color(0xFF66BB6A), Color(0xFFFFA726), Color(0xFFFFCA28),
    Color(0xFFFF7043), Color(0xFFEF5350), Color(0xFFEC407A), Color(0xFFAB47BC),
    Color(0xFF8D6E63), Color(0xFF42A5F5), Color(0xFF00ACC1), Color(0xFF000000),
    Color(0xFFFFFFFF),
  ];
}
