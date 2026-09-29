import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../pages/card_detail_page.dart';
import 'scatter.dart';

/// 全局路由观察者：页面可以 with RouteAware 感知「被别的页面盖住」和
/// 「别人退出后重新露出」，用来暂停/恢复相机这类昂贵资源。
final appRouteObserver = RouteObserver<ModalRoute<void>>();


/// 卡详情页的进出场（要求：从卡缩略图平滑放大过渡，而不是从右滑入）
///
/// 用 Hero 把缩略图和详情页大图连起来，再配一个淡入 + 从 0.92 放大的过渡。
/// [scope] 用来区分「同一张卡同时出现在一屏两处」的情况（主卡区/备卡区等），
/// tag 不一致时 Flutter 会自动退化成普通过渡，不会报错。
String cardHeroTag(String code, String scope) => 'card-$scope-$code';

Route<T> cardRoute<T>(Widget page) => PageRouteBuilder<T>(
      // 进出都用同一条曲线（匀速），退出就是进入的倒序
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 460),
      pageBuilder: (c, a, sa) => page,
      transitionsBuilder: (c, a, sa, child) {
        final curve = CurvedAnimation(parent: a, curve: Curves.linear);
        return FadeTransition(
          opacity: curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curve),
            child: child,
          ),
        );
      },
    );


/// Hero 的路径补间：让卡片在两端之间**沿一条小弧线**走，而不是直线。
///
/// - 列表 → 详情：微微**下凹**（往屏幕下方弯一点）
/// - 详情 → 列表：微微**上凸**（方向反过来）
///
/// 靠 begin/end 的高度关系判断方向：从大图飞回小图就是"返回"。
class ArcRectTween extends RectTween {
  ArcRectTween({super.begin, super.end, this.depth = 30});

  /// 弧线幅度（逻辑像素），越大弯得越明显
  final double depth;

  double? _sign;

  @override
  Rect? lerp(double t) {
    final r = super.lerp(t);
    if (r == null) return null;
    _sign ??= (begin != null && end != null && begin!.height > end!.height)
        ? -1.0
        : 1.0;
    final bow = math.sin(t * math.pi) * depth * _sign!;
    return Rect.fromLTWH(r.left, r.top + bow, r.width, r.height);
  }
}

/// 列表里的卡缩略图包一层它：从任何列表进详情页都会有
/// 「沿小弧线移动 + 放大」的动画。
class CardHero extends StatelessWidget {
  const CardHero({
    super.key,
    required this.code,
    required this.child,
    this.scope = 'list',
  });

  final String code;
  final String scope;
  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
        tag: cardHeroTag(code, scope),
        createRectTween: (b, e) => ArcRectTween(begin: b, end: e),
        child: child,
      );
}


/// 打开卡详情页的统一入口。
///
/// 会自动把"这一张"标记为正在打开：它由 Hero 负责飞，
/// **不参与整页散开**，所以返回时是"落回原位"，
/// 不会出现"先飞回来再插进去"的双重动画。
Future<T?> openCardDetail<T>(
  BuildContext context,
  String code, {
  String scope = 'list',
}) {
  // 先把输入焦点放掉。否则从卡详情返回时，系统会把焦点还给上一个
  // 页面里那个输入框（典型是检索页的搜索框），凭空弹出一个键盘 ——
  // 玩家从没要求搜索，键盘纯属打扰。放在这个统一入口里，
  // 所有进入卡详情的路径（8 处）一起受益。
  FocusManager.instance.primaryFocus?.unfocus();

  Scatter.activeCode = code;
  Scatter.play();
  return Navigator.of(context)
      .push<T>(cardRoute<T>(
        CardDetailPage(code: code, heroScope: scope),
      ))
      .whenComplete(() {
    // 返回：把散开的收回来（进入动画的倒序）
    Scatter.reset();
    // 关键：**等"收回"动画彻底走完**再解除标记。
    // 若立刻解除，被点的那一张会在收回进行到一半时突然被算进散开进度，
    // 于是"落回原位 → 又跳到半散开位置 → 再飞回原位"，
    // 看起来就是我们的动画做完后又插了一次列表。
    Future.delayed(const Duration(milliseconds: 380), () {
      if (Scatter.activeCode == code) Scatter.activeCode = null;
    });
  });
}
