import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/collect_info.dart';
import 'glass.dart';
import '../l10n/l10n.dart';

/// 罕贵度角标：颜色 / 模糊 / 透明度都来自设置里的自定义样式
class RarityBadge extends StatelessWidget {
  const RarityBadge({
    super.key,
    required this.text,
    required this.style,
    this.parallel = false,
  });

  final String text;
  final RarityStyle style;

  /// 异画（平行闪）——角标会多一个 ✦
  final bool parallel;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty && !parallel) return const SizedBox.shrink();
    final c = style.effective;
    final onColor =
        c.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;

    Widget chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(4),
        boxShadow: style.blur > 0
            ? [
                BoxShadow(
                  color: style.color.withValues(alpha: style.opacity * 0.55),
                  blurRadius: style.blur,
                  spreadRadius: style.blur / 4,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (parallel)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Text('✦',
                  style: TextStyle(
                      fontSize: 8, height: 1.1, color: onColor)),
            ),
          Text(
            text,
            style: TextStyle(
              fontSize: 9,
              height: 1.2,
              fontWeight: FontWeight.w700,
              color: onColor,
            ),
          ),
        ],
      ),
    );

    if (style.blur > 0) {
      chip = ImageFiltered(
        imageFilter: ImageFilter.blur(
            sigmaX: style.blur / 3.2, sigmaY: style.blur / 3.2),
        child: chip,
      );
    }
    return chip;
  }
}

/// 选「我收集到的是哪个罕贵度 / 是不是异画」
Future<void> showCollectDialog(
    BuildContext context, dynamic state, String code, List<String> rarities) async {
  final info = state.collectInfoOf(code) as CollectInfo? ?? CollectInfo();
  final official = (state.rarityOf(code, null) as String);
  // 用自增的 tick 当值：改完 bump 一下就能刷新
  // （原来是 ValueNotifier<CollectInfo> + notifyListeners()，
  //   但 notifyListeners 是 protected，从外面调不生效 —— 选罕贵度界面不刷新）
  final picked = ValueNotifier<int>(0);
  final pickedInfo = CollectInfo(
    rarity: info.rarity,
    parallel: info.parallel,
  );
  void bump() => picked.value++;

  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: picked,
          builder: (c, _, __) => Builder(builder: (c) {
            final v = pickedInfo;
            return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('我的这张卡'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('$code${official.isEmpty ? '' : ' · 官方罕贵 $official'}',
                  style: const TextStyle(fontSize: 11)),
              const SizedBox(height: 12),
              Text(tr('罕贵度'), style: TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(tr('按官方')),
                    selected: v.rarity.isEmpty,
                    onSelected: (_) {
                      v.rarity = '';
                      bump();
                    },
                  ),
                  for (final r in rarities)
                    ChoiceChip(
                      label: Text(r),
                      selected: v.rarity == r,
                      onSelected: (_) {
                        v.rarity = r;
                        bump();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: v.parallel,
                onChanged: (on) {
                  v.parallel = on;
                  bump();
                },
                title: Text(tr('异画（平行闪）'), style: TextStyle(fontSize: 13)),
                subtitle: Text(tr('角标会多一个 ✦'), style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        state.setCollectInfo(code, v);
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.check),
                      label: Text(tr('保存')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () {
                      state.setCollectInfo(code, CollectInfo());
                      Navigator.pop(c);
                    },
                    child: Text(tr('清除')),
                  ),
                ],
              ),
            ],
          );
          }),
        ),
      ),
    ),
  );
}
