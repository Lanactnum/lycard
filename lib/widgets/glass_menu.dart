import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'glass.dart';

/// 玻璃弹出菜单里的一项
class GlassMenuItem<T> {
  const GlassMenuItem(this.value, this.label, {this.icon, this.danger = false});

  final T value;
  final String label;
  final IconData? icon;

  /// 删除类操作：文字用错误色
  final bool danger;
}

/// 右上角「三个点」的玻璃版菜单。
///
/// 为什么不用 `PopupMenuButton`：它的菜单走 Overlay，
/// 塞不进 `BackdropFilter`，所以**永远没有模糊**，
/// 透明度和颜色也跟顶栏/底栏那套对不上。
/// 这里改成自己弹一个 `Glass`，模糊与不透明度跟**顶栏共用**同一组参数。
class GlassMenuButton<T> extends StatelessWidget {
  const GlassMenuButton({
    super.key,
    required this.items,
    required this.onSelected,
    this.icon = Icons.more_vert,
    this.tooltip,
  });

  final List<GlassMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final IconData icon;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: () {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        showGlassMenu<T>(
          context: context,
          anchor: box,
          items: items,
          onSelected: onSelected,
        );
      },
    );
  }
}

/// 在 [anchor]（一般是那个三点按钮）下方弹出玻璃菜单
Future<void> showGlassMenu<T>({
  required BuildContext context,
  required RenderBox anchor,
  required List<GlassMenuItem<T>> items,
  required ValueChanged<T> onSelected,
}) async {
  final overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox? ?? anchor;
  final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  final s = context.read<AppState>();
  final scheme = Theme.of(context).colorScheme;

  final picked = await showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'menu',
    barrierColor: Colors.black.withValues(alpha: 0.04),
    transitionDuration: const Duration(milliseconds: 170),
    // MediaQuery.removePadding：showGeneralDialog 自带 SafeArea，
    // 会让 Stack 从状态栏下面开始 → 菜单整体上移、压到顶栏上。
    // 去掉它之后 origin 就是真正的屏幕坐标。
    pageBuilder: (c, a, sa) => MediaQuery.removePadding(
      context: c,
      removeTop: true,
      removeBottom: true,
      child: Stack(
      children: [
        Positioned(
          right: 8,
          top: origin.dy + anchor.size.height + 10,
          // Material：Text 少了 Material 祖先会被画上黄色双下划线
          child: Material(
            type: MaterialType.transparency,
            child: Glass(
            // 和顶栏共用同一组模糊/不透明度（外观页「顶栏与胶囊」）
            blur: s.barBlur,
            opacity: s.barOpacity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 150, maxWidth: 280),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final it in items)
                    InkWell(
                      borderRadius: BorderRadius.circular(s.cornerRadius),
                      onTap: () => Navigator.pop(c, it.value),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            if (it.icon != null) ...[
                              Icon(
                                it.icon,
                                size: 17,
                                color: it.danger
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Text(
                                it.label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: it.danger
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),
          ),
        ),
      ],
      ),
    ),
    transitionBuilder: (c, a, s2, child) {
      final cur = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: cur,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(cur),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );

  if (picked != null) onSelected(picked);
}
