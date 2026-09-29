import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'motion.dart';

/// 胶囊切换（iOS 分段控件那种做法）：
/// 选中的那一半**铺满**、不留内边距，外侧用外层胶囊的圆角、内侧用小圆角，
/// 所以高亮块和外层胶囊严丝合缝（以前是内缩的小圆角块，怎么调都"对不上"）。
class PillSwitch extends StatelessWidget {
  const PillSwitch({
    super.key,
    required this.labels,
    required this.icons,
    required this.index,
    required this.onChanged,
    this.height = 44,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int index;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final outer = s.cornerRadius;

    return SizedBox(
      height: height,
      child: Row(
        // 关键：拉伸，否则 AnimatedContainer 只有内容那么高，
        // 选中块会上下内缩，看起来永远"和胶囊对不齐"
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: i == index
                        ? scheme.primary.withValues(alpha: 0.24)
                        : Colors.transparent,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(i == 0 ? outer : 4),
                      bottomLeft: Radius.circular(i == 0 ? outer : 4),
                      topRight:
                          Radius.circular(i == labels.length - 1 ? outer : 4),
                      bottomRight:
                          Radius.circular(i == labels.length - 1 ? outer : 4),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icons[i],
                        size: 17,
                        color: i == index
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      // 选中 → 字重平滑升上去（要求 L105：选中某项时字重无极变化）
                      WeightText(
                        labels[i],
                        base: 500,
                        max: 800,
                        value: i == index ? 1 : 0,
                        style: TextStyle(
                          fontSize: 13,
                          color: i == index
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
