import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 打开卡详情时，原页面往四周散开（要求：原缩略图界面向四周飞散，
/// 检索 / 构筑 / 我的 等界面统一用这套动画）。
class Scatter {
  Scatter._();

  /// 0 = 原位，1 = 已散开
  static final ValueNotifier<double> progress = ValueNotifier<double>(0);

  static Ticker? _ticker;

  static void _run(double to, int ms) {
    _ticker?.dispose();
    final from = progress.value;
    final start = DateTime.now();
    late final Ticker tk;
    tk = Ticker((_) {
      final raw = (DateTime.now().difference(start).inMilliseconds / ms)
          .clamp(0.0, 1.0);
      // 匀速：不要缓动，否则最后会突然变快
      progress.value = from + (to - from) * raw;
      if (raw >= 1) {
        tk.stop();
      }
    });
    _ticker = tk;
    tk.start();
  }

  /// 散开（点开卡的时候调）
  static void play() => _run(1, 310);

  /// 回来时收回：时长/曲线和散开完全一致 → 就是进入动画的倒序
  static void reset() => _run(0, 310);

  /// 关掉（动效程度为 0 时什么都不做）
  static bool enabled = true;

  /// 正在打开卡详情的那一张：它由 Hero 负责飞，
  /// **不能**再跟着整页散开 —— 否则返回时要"先飞回来再插回去"，
  /// 和 Hero 的落回叠在一起，看起来就是被踢出列表又插进来。
  static String? activeCode;
}

/// 网格/列表里的一项：整页散开时自己往外面飞
class ScatterItem extends StatelessWidget {
  const ScatterItem({
    super.key,
    required this.index,
    required this.child,
    this.strength = 1.0,
    this.code,
  });

  final int index;
  final Widget child;
  final double strength;

  /// 这一项代表的卡号：等于 [Scatter.activeCode] 时原地不动（交给 Hero）
  final String? code;

  static const List<Offset> _dirs = [
    Offset(-1, -0.7), Offset(0, -1), Offset(1, -0.7),
    Offset(-1, 0), Offset(1, 0),
    Offset(-1, 0.7), Offset(0, 1), Offset(1, 0.7),
  ];

  @override
  Widget build(BuildContext context) {
    if (!Scatter.enabled) return child;
    if (code != null && code == Scatter.activeCode) return child;
    final dir = _dirs[index % _dirs.length];
    return ValueListenableBuilder<double>(
      valueListenable: Scatter.progress,
      builder: (c, t, ch) {
        if (t == 0) return ch!;
        // 正在打开详情的那一张原地不动（交给 Hero 飞）
        if (code != null && code == Scatter.activeCode) return ch!;
        final dx = dir.dx * t * 170 * strength;
        final dy = dir.dy * t * 170 * strength;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(
            scale: 1 - 0.18 * t * strength,
            child: Opacity(opacity: (1 - t * 0.9).clamp(0.0, 1.0), child: ch),
          ),
        );
      },
      child: child,
    );
  }
}
