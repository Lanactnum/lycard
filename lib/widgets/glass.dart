import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../l10n/l10n.dart';

/// 透明效果（要求 L101）：两种风格二选一，不合并
///   1 = 高斯模糊：真·磨砂玻璃，背景内容被糊掉
///   2 = 柔光玻璃：不糊背景，只叠一层柔光膜 + 高光边
/// 建立对「外观相关字段」的**窄依赖**，然后返回 AppState 供读取。
///
/// 玻璃面板遍布顶栏/底栏/各种浮层（十几二十个），以前它们直接
/// `context.watch<AppState>()` —— 于是收藏一张卡、在检索页打一个字，
/// 这些面板全都要重建一遍，纯属白费。真正影响它们长相的只有
/// 圆角 / 模糊 / 不透明度这几个值，收窄到这里。
AppState _watchAppearance(BuildContext context) {
  context.select<AppState, int>((a) => Object.hash(
        a.cornerRadius,
        a.glassBlur,
        a.glassOpacity,
        a.barBlur,
        a.barOpacity,
      ));
  return context.read<AppState>();
}

class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius,
    this.margin,
    this.padding,
    this.blurScale = 1.0,
    this.framed = false,
    this.pill = false,
    this.blur,
    this.opacity,
  });

  final Widget child;

  /// 不传就跟随「自定义圆角」设置
  final double? radius;
  final EdgeInsets? margin;
  final EdgeInsets? padding;
  final double blurScale;

  /// 没开透明效果、但开了「悬浮页面」时，也给个圆角 + 投影的实体底座
  final bool framed;

  /// true = 胶囊（圆角拉满），不受「自定义圆角」影响
  final bool pill;

  /// 单独指定模糊 / 不透明度（不填就跟随全局设置）
  final double? blur;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final s = _watchAppearance(context);
    final scheme = Theme.of(context).colorScheme;
    // 圆角：优先用调用方给的，其次跟随「自定义圆角」
    final shape = BorderRadius.circular(
      pill ? 999 : (radius ?? s.cornerRadius),
    );
    final blurV = blur ?? s.glassBlur;
    final opaV = opacity ?? s.glassOpacity;
    const mode = 1;

    // 浅色模式下 surface 是白色：面板和背景同为浅色 → 边界糊掉、
    // 玻璃看着像"没生效"。所以浅色时给面板掺一点点前景色（变灰），
    // 并适当提高不透明度，让面板从背景里浮出来。深色维持原样。
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark
        ? scheme.surface.withValues(alpha: opaV)
        : Color.lerp(scheme.surface, scheme.onSurface, 0.07)!
            .withValues(alpha: (opaV * 1.4).clamp(0.0, 0.95));

    final core = Padding(
      padding: padding ?? EdgeInsets.zero,
      child: child,
    );

    Widget body;
    if (mode == 1) {
      // 高斯模糊
      body = ClipRRect(
        borderRadius: shape,
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: blurV * blurScale,
            sigmaY: blurV * blurScale,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: tint, borderRadius: shape),
            child: core,
          ),
        ),
      );
    } else if (mode == 2) {
      // 柔光玻璃：不糊背景，靠一层半透明白 + 顶部高光
      body = ClipRRect(
        borderRadius: shape,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.20 * opaV + 0.06),
                scheme.surface.withValues(alpha: opaV * 0.9),
                Colors.white.withValues(alpha: 0.06),
              ],
              stops: const [0, 0.55, 1],
            ),
            borderRadius: shape,
          ),
          child: core,
        ),
      );
    } else {
      // 透明效果关着：悬浮底座就用主题色实底
      body = framed
          ? ClipRRect(
              borderRadius: shape,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: shape,
                ),
                child: core,
              ),
            )
          : core;
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: shape,
      ),
      child: body,
    );
  }
}

/// 顶栏（AppBar）也吃透明/模糊
///
/// 注意：**不是**卡片式。就是一条通栏顶栏，只是底色半透明 + 底下内容被糊掉。
/// 用法：把页面里的 `AppBar(` 换成 `GlassAppBar(`，参数完全一致。
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.centerTitle,
    this.bottomHeight = 0,
  });

  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final bool? centerTitle;
  final double bottomHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? bottomHeight));

  @override
  Widget build(BuildContext context) {
    final s = _watchAppearance(context);
    final scheme = Theme.of(context).colorScheme;

    if (s.glassMode == 0 && !s.floatingChrome) {
      return AppBar(
        title: title,
        actions: actions,
        leading: leading,
        bottom: bottom,
        automaticallyImplyLeading: automaticallyImplyLeading,
        centerTitle: centerTitle,
      );
    }

    final bar = AppBar(
      title: title,
      actions: actions,
      leading: leading,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      centerTitle: centerTitle,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      // 通栏：一点外边距和圆角都不加
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    );

    // 通栏的玻璃层：整条宽度，不含圆角/投影
    return ClipRect(
      child: BackdropFilter.grouped(
        filter: ImageFilter.blur(
          sigmaX: s.barBlur * 0.65,
          sigmaY: s.barBlur * 0.65,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: s.barOpacity),
          ),
          child: bar,
        ),
      ),
    );
  }
}

/// 自定义背景层（要求 L117）
///
/// 路径在启动时解析好（[AppState.bgPath]），这里直接同步读文件，
/// 切换页面不会再去异步查目录 → 不会卡一下才出图。
/// 默认背景：跟随主题的柔和双色渐变（深浅色模式各自成立）。
/// 存在的意义是让「没设自定义背景」的页面也有自己的底，
/// 避免切页面时露出 MaterialApp 的纯色底而闪一下。
class _DefaultBg extends StatelessWidget {
  const _DefaultBg();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scheme = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    // 统一成「上亮下暗」：模拟光从上方来，两种模式方向一致。
    // 之前掺 primary 是斜向渐变，暗色下变成下亮上暗、亮色下又反过来，
    // 看着很别扭。
    final top = dark
        ? Color.lerp(scheme.surface, Colors.white, 0.055)!
        : scheme.surface;
    final bottom = dark
        ? scheme.surface
        : Color.lerp(scheme.surface, scheme.onSurface, 0.055)!;
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, Color.lerp(top, bottom, 0.45)!, bottom],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key});

  @override
  Widget build(BuildContext context) {
    // 只监听"背景相关"的字段：切页面、卡池变动、搜索输入等
    // 都不会再让背景层重建（以前用 watch 每次都重建 → 每进一个新页面都重画背景 = 卡一下）
    context.select<AppState, int>((a) => Object.hash(
          a.bgPath,
          a.bgRaw,
          a.bgZoom,
          a.bgRotation,
          a.bgBlur,
          a.bgBrightness,
          a.bgMaskColor,
          a.bgMaskOpacity,
        ));
    final s = context.read<AppState>();
    final raw = s.bgRaw;
    final provider = s.bgProvider;
    // 没设背景图时**不能**什么都不画：页面本身就是透明的
    //（Scaffold backgroundColor: transparent），一空就会在切页面时
    // 露出 MaterialApp 的纯色底 → 看着像闪一下。给一层跟随主题的
    // 默认渐变，每页就都有自己的底了。
    if (raw == null && provider == null) return const _DefaultBg();

    // 预解码好的位图：1:1 贴图（cover），low 质量，并让光栅结果被缓存住
    Widget img = raw != null
        ? CustomPaint(
            isComplex: true,
            willChange: false,
            painter: _BgImagePainter(raw),
            child: const SizedBox.expand(),
          )
        : Image(
            image: provider!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (c, e, st) => const SizedBox.shrink(),
          );

    // 缩放（裁剪）→ 旋转 → 模糊 → 亮度
    if (s.bgZoom != 1.0) {
      img = Transform.scale(scale: s.bgZoom, child: img);
    }
    if (s.bgRotation != 0) {
      img = Transform.rotate(angle: s.bgRotation * math.pi / 180, child: img);
    }
    if (s.bgBlur > 0) {
      img = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: s.bgBlur, sigmaY: s.bgBlur),
        child: img,
      );
    }
    if (s.bgBrightness != 1.0) {
      final b = s.bgBrightness;
      img = ColorFiltered(
        colorFilter: ColorFilter.matrix(<double>[
          b, 0, 0, 0, 0,
          0, b, 0, 0, 0,
          0, 0, b, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: img,
      );
    }

    return Positioned.fill(
      child: RepaintBoundary(
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              img,
              if (s.bgMaskOpacity > 0)
                ColoredBox(
                  color: s.bgMaskColor.withValues(alpha: s.bgMaskOpacity),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 直接把预解码位图按 cover 画上去：没有缩放重采样以外的任何开销
class _BgImagePainter extends CustomPainter {
  _BgImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || image.width == 0 || image.height == 0) return;
    final iw = image.width.toDouble();
    final ih = image.height.toDouble();
    final sc = math.max(size.width / iw, size.height / ih);
    final dw = iw * sc;
    final dh = ih * sc;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, iw, ih),
      Rect.fromLTWH((size.width - dw) / 2, (size.height - dh) / 2, dw, dh),
      Paint()
        ..filterQuality = FilterQuality.low
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(_BgImagePainter old) => old.image != image;
}

class BottomGlassBar extends StatelessWidget {
  const BottomGlassBar({
    super.key,
    required this.child,
    this.pill = true,
  });

  final Widget child;

  /// true = 悬浮胶囊（圆角 + 外边距 + 投影），false = 通栏
  final bool pill;

  @override
  Widget build(BuildContext context) {
    final s = _watchAppearance(context);
    final scheme = Theme.of(context).colorScheme;
    if (s.glassMode == 0 && !s.floatingChrome) return child;

    // 底栏胶囊也跟随「自定义圆角」；模糊/不透明度用「顶栏与胶囊」那一组
    final blurV = s.barBlur;
    final opaV = s.barOpacity;
    final shape = BorderRadius.circular(pill ? s.cornerRadius : 0);

    // ⚠ 系统手势安全区（viewPadding.bottom，本机 20dp）**不能留在胶囊里**。
    //
    // NavigationBar 内部套了一层 SafeArea，会把 padding.bottom 加在自己的
    // 高度**下面**（主题里 height=68 → 实际变成 88）。胶囊又是浮起来的、
    // 本来就留了底部外边距，于是这 20dp 空白被玻璃一起包住 ——
    // 视觉上就是「文字下面多出一块空白、胶囊还贴得离屏幕边很近」。
    //
    // 结构上的正解：安全区归安全区、胶囊归胶囊。悬浮胶囊把那段安全区
    // 算进**自己的底部外边距**，同时让内部的 NavigationBar 不再重复让位。
    // 这样图标/文字在屏幕上的位置**完全不变**（下方让位总量仍是 20+14），
    // 只是玻璃不再多包一层空白。通栏模式不悬浮，安全区就该留在里面。
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      margin: pill
          ? EdgeInsets.fromLTRB(12, 0, 12, 14 + bottomInset)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        borderRadius: shape,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter.grouped(
          filter: ImageFilter.blur(
            sigmaX: blurV * 0.65,
            sigmaY: blurV * 0.65,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: opaV),
              borderRadius: shape,
            ),
            child: pill
                ? MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: child,
                  )
                : child,
          ),
        ),
      ),
    );
  }
}

/// 顶栏是通栏 + extendBodyBehindAppBar，滚动区要自己让开的顶部高度
double topInset(BuildContext c, {double extra = 0}) =>
    MediaQuery.paddingOf(c).top + kToolbarHeight + extra;

/// 所有弹出面板（菜单 / 选择器 / 编辑框）统一用这层玻璃
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = false,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    builder: (c) => Glass(
      radius: 26,
      margin: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDragHandle)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 2),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(c)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Flexible(child: builder(c)),
        ],
      ),
    ),
  );
}


/// 玻璃风格的确认框（是 / 否）。
/// 不用 AlertDialog —— 它自带不透明 surface 底，跟这套玻璃 UI 打架。
Future<bool?> showGlassConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmText,
  String? cancelText,
}) {
  // 默认值不能是函数调用（Dart 要求编译期常量）
  final okText = confirmText ?? tr('确定');
  final noText = cancelText ?? tr('取消');
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('关闭'),
    barrierColor: Colors.black.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (c, a, sa) => Center(
      child: Material(
        type: MaterialType.transparency,
        child: Glass(
          radius: 20,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (message != null) ...[
                  const SizedBox(height: 6),
                  Text(message,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: Theme.of(c).colorScheme.onSurfaceVariant)),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(c).pop(false),
                      child: Text(noText),
                    ),
                    const SizedBox(width: 6),
                    FilledButton(
                      onPressed: () => Navigator.of(c).pop(true),
                      child: Text(okText),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 居中悬浮浮层 —— 用于「词条解释」「同名卡选择」这类看一眼就走的临时内容。
///
/// 和 [Glass] 系列的区别：**没有卡片底**。整个屏幕背景被模糊掉，
/// 内容直接浮在中间，看起来是"文字悬在模糊的背景上"而不是"弹出一个卡片"。
///
/// 模糊强度是**固定值**（满档 30 的 20%），刻意不跟随
/// 「外观 → 模糊强度」设置：那个滑杆是给顶栏/底栏/面板用的，
/// 用户把它拉到 0 时这个浮层会失去层次感，拉到 30 又糊成一团。
Future<T?> showFloatingLayer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? barrierLabel,
}) {
  // 默认值不能写成 tr('关闭')：Dart 要求默认参数是编译期常量，
  // 调函数会报 const_eval_method_invocation。在函数体里兜底。
  final label = barrierLabel ?? tr('关闭');
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: label,
    // 压暗/模糊都在下面那层按进度做，这里保持透明
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (c, a, sa) => _FloatingLayer(
      animation: a,
      child: builder(c),
    ),
    transitionBuilder: (c, a, sa, child) => child,
  );
}

/// 全屏模糊 + 内容居中。
///
/// **模糊强度跟着出现进度一起增长** —— 一开始写成固定 sigma 放在
/// pageBuilder 里，结果是「文字先淡入完，模糊才"啪"地一下出现」，
/// 两个动作不同步，看着很突兀。现在整层的出现节奏统一交给
/// [animation]：模糊、压暗、文字的透明度/缩放全部由同一个值驱动。
class _FloatingLayer extends StatelessWidget {
  const _FloatingLayer({required this.child, required this.animation});

  final Widget child;

  /// 弹出进度 0→1
  final Animation<double> animation;

  /// 完全出现时的模糊强度：满档 30 的 20%。
  /// 刻意不读 AppState —— 那个滑杆是给顶栏/底栏/面板用的，
  /// 拉到 0 这层就没层次、拉到 30 又糊成一团。
  static const double _maxSigma = 6;

  /// 完全出现时的压暗（保证文字在任何壁纸上都看得清）
  static const double _maxDim = 0.12;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: animation,
              builder: (c, _) {
                // 直接对进度套曲线：不用 CurvedAnimation 对象，
                // 那个需要 dispose，而这里是 StatelessWidget。
                final t = Curves.easeOut.transform(animation.value);
                // sigma 为 0 时不套 BackdropFilter：那层会把整屏都走一遍
                // 模糊采样，白付一次代价。
                if (t <= 0.001) {
                  return const SizedBox.shrink();
                }
                return BackdropFilter.grouped(
                  filter: ImageFilter.blur(
                    sigmaX: _maxSigma * t,
                    sigmaY: _maxSigma * t,
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: _maxDim * t),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (c, inner) {
                    // 文字的出现节奏和模糊用**同一条曲线**，
                    // 这样"背景变糊"和"文字浮现"是同一个动作的两面。
                    final t = Curves.easeOut.transform(animation.value);
                    return Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: 0.94 + 0.06 * t,
                        child: inner,
                      ),
                    );
                  },
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
