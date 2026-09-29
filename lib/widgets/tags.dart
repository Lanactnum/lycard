import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// ─────────────────────────────────────────────────────────────
/// 全 app 的小控件统一来源。以后要调"标签/小信息块"的样子，
/// 只改这个文件，所有页面一起变 —— 不要再在页面里手搓。
///
/// 规律（照这个来）：
///   大面板（顶栏/底栏/搜索框/弹层）→ 用 Glass（有模糊 + 面底，可调）
///   小标签（卡号、属性、筛选词、示例词）→ 用 LyTag（默认完全无底）
///   小信息块（属性/费用/EX/AP/DP…）→ 用 LyInfoTile（淡底，跟随全局不透明度）
/// ─────────────────────────────────────────────────────────────

/// 统一的小标签：默认**完全无底**，只有文字叠在背景上；
/// 需要"选中"时给一层淡色（筛选、多选）。
///
/// 之所以手搓而不是用 Flutter 的 Chip：M3 的 Chip/ActionChip/FilterChip
/// 内部一定会铺一层 surface 底，设 transparent 也去不掉。
class LyTag extends StatelessWidget {
  const LyTag({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 9 : 11,
          vertical: dense ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.24)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(
            dense ? 999 : s.cornerRadius,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: dense ? 12 : 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 统一的小信息块（卡详情的 属性/费用/EX/AP/DP/SP/DMG…）：
/// 一层淡底 + 跟随全局不透明度与圆角。
class LyInfoTile extends StatelessWidget {
  const LyInfoTile({
    super.key,
    required this.label,
    required this.value,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  final String label;
  final String value;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: s.glassOpacity),
        borderRadius: BorderRadius.circular(s.cornerRadius),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
