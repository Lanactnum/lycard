import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// M3 Expressive 那几套动效（要求 L123 Shape Morphing / L125 Spring Physics /
/// L126 卡片悬浮 / L128 悬浮阴影）
///
/// 全部吃 AppState.motionScale（动效程度）：0 = 不动，1 = 默认，1.5 = 夸张。
double _scaleOf(BuildContext c) {
  final s = c.watch<AppState>();
  return s.motionScale;
}

/// 弹簧曲线（带回弹，比 easeOut 有“果冻感”）
class SpringCurves {
  static const Curve soft = Cubic(0.22, 1.4, 0.36, 1); // 轻微过冲
  static const Curve bouncy = Cubic(0.18, 1.9, 0.32, 1); // 明显回弹
  static const Curve settle = Cubic(0.2, 1.0, 0.3, 1.0);
}

/// 出现时弹簧放大 + 淡入（列表项、卡片网格用）
class SpringIn extends StatefulWidget {
  const SpringIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.from = 0.92,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration delay;
  final double from;
  final Duration duration;

  @override
  State<SpringIn> createState() => _SpringInState();
}

class _SpringInState extends State<SpringIn> {
  bool _on = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _on = true;
    } else {
      // 用可取消的 Timer：否则被 dispose 时测试框架会报「还有 Timer 没结束」
      _t = Timer(widget.delay, () {
        if (mounted) setState(() => _on = true);
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = _scaleOf(context);
    if (k == 0) return widget.child;
    final from = 1 - (1 - widget.from) * k;
    // 注意：延迟期间也要把孩子留在树里（只是透明），
    // 否则第一帧找不到内容，widget 测试会莫名其妙失败。
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from, end: 1),
      duration: widget.duration,
      curve: SpringCurves.soft,
      builder: (c, t, child) => Opacity(
        opacity: (_on ? t : 0.0).clamp(0.0, 1.0),
        child: Transform.scale(scale: _on ? t : from, child: child),
      ),
      child: widget.child,
    );
  }
}

/// 底栏图标：被点中的那个自己弹一下（缩放轴心就在那个图标上）
class NavSpring extends StatefulWidget {
  const NavSpring({super.key, required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<NavSpring> createState() => _NavSpringState();
}

class _NavSpringState extends State<NavSpring>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(covariant NavSpring old) {
    super.didUpdateWidget(old);
    if (!old.selected && widget.selected) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = _scaleOf(context);
    if (k == 0) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (c, child) {
        final t = _c.value;
        // 0→1 的过冲弹跳：先胀大再回落
        final bump = math.sin(t * math.pi) * 0.22 * k;
        final squash = math.sin(t * math.pi) * 0.10 * k;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scaleByDouble(1 + bump, 1 - squash, 1, 1),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 卡片「悬浮」：长按 / 拖起时抬起来（放大 + 阴影），松手落回。
/// 同时满足 L126（卡片悬浮）与 L128（悬浮时的阴影）。
class HoverCard extends StatefulWidget {
  const HoverCard({
    super.key,
    required this.child,
    this.radius = 12,
    this.lift = 1.06,
    this.onTap,
    this.onLongPress,
    this.enable = true,
  });

  final Widget child;
  final double radius;
  final double lift;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool enable;

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _up = false;

  @override
  Widget build(BuildContext context) {
    final k = _scaleOf(context);
    final shape = BorderRadius.circular(widget.radius);
    final lift = 1 + (widget.lift - 1) * k;

    return GestureDetector(
      onTapDown: widget.enable ? (_) => setState(() => _up = true) : null,
      onTapUp: widget.enable ? (_) => setState(() => _up = false) : null,
      onTapCancel: widget.enable ? () => setState(() => _up = false) : null,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: Duration(milliseconds: k == 0 ? 1 : 220),
        curve: SpringCurves.bouncy,
        transform: Matrix4.identity()
          ..scaleByDouble(_up ? lift : 1.0, _up ? lift : 1.0, 1, 1)
          ..translateByDouble(0.0, _up ? -2.0 * k : 0.0, 0.0, 1),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: shape,
        ),
        child: ClipRRect(borderRadius: shape, child: widget.child),
      ),
    );
  }
}

/// 形状形变（L123）：按下时圆角「捏」成更圆/更方，松手弹回。
class MorphTap extends StatefulWidget {
  const MorphTap({
    super.key,
    required this.child,
    required this.radius,
    this.pressedRadius,
    this.onTap,
    this.duration = const Duration(milliseconds: 220),
  });

  final Widget child;
  final double radius;
  final double? pressedRadius;
  final VoidCallback? onTap;
  final Duration duration;

  @override
  State<MorphTap> createState() => _MorphTapState();
}

class _MorphTapState extends State<MorphTap> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final k = _scaleOf(context);
    final base = widget.radius;
    final target = widget.pressedRadius ?? base * 2;
    final r = _down ? base + (target - base) * k : base;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: widget.duration,
        curve: SpringCurves.bouncy,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          color: _down
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Colors.transparent,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: widget.child,
        ),
      ),
    );
  }
}

/// 果冻跳一下（开关切换 / 选中状态变化时用，L125）
class Jelly extends StatefulWidget {
  const Jelly({super.key, required this.trigger, required this.child});

  /// 这个值一变就跳一下
  final Object trigger;
  final Widget child;

  @override
  State<Jelly> createState() => _JellyState();
}

class _JellyState extends State<Jelly> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  @override
  void didUpdateWidget(covariant Jelly old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = _scaleOf(context);
    if (k == 0) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (c, child) {
        final t = _c.value;
        final jump = math.sin(t * math.pi) * 0.16 * k;
        final wobble = math.sin(t * math.pi * 2) * 0.06 * k;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scaleByDouble(1 + jump, 1 - jump * 0.35, 1, 1)
            ..rotateZ(wobble * (_c.isAnimating ? 1 : 0)),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 滚动 → 字重连续变化（要求 L105「滑动页面时字重动态无极变化」）
///
/// 用法：把可滚动区域包在 [ScrollWeightScope] 里，标题用 [WeightText]，
/// 滚动时字重从 base 连续变到 max（可变字体走 wght 轴，普通字体退化成 fontWeight）。
class ScrollWeightScope extends StatelessWidget {
  const ScrollWeightScope({super.key, required this.child});

  final Widget child;

  static final ValueNotifier<double> _nv = ValueNotifier<double>(0);

  static ValueNotifier<double> notifier(BuildContext _) => _nv;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        final m = n.metrics;
        if (m.maxScrollExtent > 0) {
          _nv.value = (m.pixels / m.maxScrollExtent).clamp(0.0, 1.0);
        }
        return false;
      },
      child: child,
    );
  }
}

class WeightText extends StatelessWidget {
  const WeightText(
    this.text, {
    super.key,
    this.base = 400,
    this.max = 800,
    this.style,
    this.value,
    this.slnt = 0,
    this.wdth = 0,
  });

  final String text;
  final double base;
  final double max;
  final TextStyle? style;

  /// 指定驱动值（0~1）：用于"选中 / 展开"这类状态；
  /// 留 null 就跟随页面滚动位置（要求 L105 的两种触发方式）
  final double? value;

  /// 倾斜变化幅度（需要字体有 slnt 轴，可选）
  final double slnt;

  /// 字宽变化幅度（需要字体有 wdth 轴，可选）
  final double wdth;

  static FontWeight _nearest(double w) {
    const ws = [100, 200, 300, 400, 500, 600, 700, 800, 900];
    var best = 400;
    var d = 1e9;
    for (final x in ws) {
      final dd = (x - w).abs().toDouble();
      if (dd < d) {
        d = dd;
        best = x;
      }
    }
    return FontWeight.values[(best ~/ 100) - 1];
  }

  TextStyle _st(BuildContext context, AppState s, double t) {
    final w = s.dynWeight ? base + (max - base) * t : base;
    // 字重/倾斜/字宽一起做无极变化。
    // 有可变字体就是真的连续变化，没有的话 wght 由下面的 fontWeight 按档位兜底。
    final vs = <FontVariation>[];
    if (s.dynWeight) {
      vs.add(FontVariation('wght', w));
      if (slnt != 0) vs.add(FontVariation('slnt', slnt * t));
      if (wdth != 0) vs.add(FontVariation('wdth', 100 + wdth * t));
    }
    return (style ?? DefaultTextStyle.of(context).style).copyWith(
      fontWeight: _nearest(w),
      fontVariations: vs.isEmpty ? null : vs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final v = value;
    if (v != null) {
      // 选中 / 展开：字重平滑升上去（TweenAnimationBuilder 会从当前值续着动画）
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: v),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (c, t, _) => Text(text, style: _st(c, s, t)),
      );
    }
    return ValueListenableBuilder<double>(
      valueListenable: ScrollWeightScope.notifier(context),
      builder: (c, t, _) => Text(text, style: _st(c, s, t)),
    );
  }
}
