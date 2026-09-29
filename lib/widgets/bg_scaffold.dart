import 'package:flutter/material.dart';

import 'glass.dart';
import 'layout.dart';

/// 页面脚手架（统一入口，方便以后一处改全局）。
///
/// 背景**只有一层**，放在最底下（`MaterialApp.builder` 里那个 Stack 的底层），
/// 所有页面自己透明就行 —— 这是业界最常用的做法。
///
/// 反例（别再干）：在每个页面里也画一份背景。
/// 页面过渡期间"旧页面的背景 + 新页面的背景"会叠在一起，
/// 加上遮罩/亮度就会看起来发脏、发暗。
class BgScaffold extends StatelessWidget {
  const BgScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.drawer,
    this.backgroundColor,
    this.avoidBottomBar = false,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Widget? drawer;
  final Color? backgroundColor;

  /// 这个页面带悬浮底栏吗？带了的话 FAB 要自动往上让开
  final bool avoidBottomBar;

  @override
  Widget build(BuildContext context) {
    // 背景画在**页面自己身上**：push 新页面时第一帧就有背景，不会"卡一下才出来"。
    // 单层背景（只靠最底下那层）实测会卡 —— 别改回去。
    // 叠影问题：因为背景图本身不透明，上层页面的图会完全盖住下层那张，
    // 所以不会真的"叠"；遮罩也是同样的层序，只有过渡位移时会有短暂错位。
    return Stack(
      children: [
        const AppBackground(),
        Scaffold(
          backgroundColor: backgroundColor ?? Colors.transparent,
          appBar: appBar,
          body: body,
          floatingActionButton: (floatingActionButton == null)
              ? null
              : (avoidBottomBar
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: kBottomBarHeight),
                      child: floatingActionButton,
                    )
                  : floatingActionButton),
          bottomNavigationBar: bottomNavigationBar,
          drawer: drawer,
        ),
      ],
    );
  }
}
