import 'package:flutter/material.dart';

/// 统一的页面过渡：只做"从下轻轻推上来"，**不做淡入、不做缩放**。
///
/// 为什么：淡入/缩放会让新页面在半透明状态停留 ~300ms，
/// 那段时间屏幕上是"底下的背景图"而不是新页面，
/// 看起来就是"进新一级界面时背景卡一下才加载出来"。
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final a = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.035),
        end: Offset.zero,
      ).animate(a),
      child: child,
    );
  }
}

/// 官方的预测性返回过渡，但把普通 push 的时长压短（默认 800ms 太长，
/// 位移期间"页面自带的背景"会跟着动，看起来像两层背景错开）。
class QuickPredictiveBackTransitionsBuilder
    extends PredictiveBackPageTransitionsBuilder {
  const QuickPredictiveBackTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);
}
