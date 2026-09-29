import 'package:flutter/material.dart';
import 'widgets/soft_route.dart';

ThemeData buildLyceeTheme({
  required Color seed,
  required Brightness brightness,
  ColorScheme? dynamicScheme,
  bool expressive = false,
  double cornerRadius = 16,
  bool transparentSurface = false,
  String? fontFamily,
  Color? fontColor,
  bool glassOn = false,
  double glassOpacity = 0.32,
}) {
  ColorScheme scheme = dynamicScheme ??
      ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  if (glassOn) {
    // 这些 container 色是各种"小标签/小块"的底：统一调透，
    // 不然自绘的那些 chip 永远是不透明的
    scheme = scheme.copyWith(
      surfaceContainerHigh:
          scheme.surfaceContainerHigh.withValues(alpha: 0.30),
      surfaceContainerHighest:
          scheme.surfaceContainerHighest.withValues(alpha: 0.26),
      surfaceContainer: scheme.surfaceContainer.withValues(alpha: 0.30),
      surfaceContainerLow:
          scheme.surfaceContainerLow.withValues(alpha: 0.30),
      secondaryContainer:
          scheme.secondaryContainer.withValues(alpha: 0.28),
      primaryContainer: scheme.primaryContainer.withValues(alpha: 0.26),
      tertiaryContainer:
          scheme.tertiaryContainer.withValues(alpha: 0.26),
      errorContainer: scheme.errorContainer.withValues(alpha: 0.26),
    );
  }

  if (expressive) {
    scheme = scheme.copyWith(
      primaryContainer: scheme.primary.withValues(alpha: 0.28),
      secondaryContainer: scheme.secondary.withValues(alpha: 0.24),
      tertiaryContainer: scheme.tertiary.withValues(alpha: 0.24),
    );
  }

  // 圆角风格：精简 6 / 常规 12 / 夸张 20（要求 L97）
  final base = cornerRadius.clamp(4.0, 26.0);
  final radius = expressive ? (base + 6) : base;

  var t = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontFamily,
    // 页面过渡：Android 用官方的预测性返回（手势跟手 + 普通 push 走 FadeForwards），
    // iOS 用原生右滑，其它平台用自家的纯位移过渡。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: QuickPredictiveBackTransitionsBuilder(),
        TargetPlatform.iOS: SoftPageTransitionsBuilder(),
        TargetPlatform.windows: SoftPageTransitionsBuilder(),
        TargetPlatform.macOS: SoftPageTransitionsBuilder(),
        TargetPlatform.linux: SoftPageTransitionsBuilder(),
      },
    ),
    scaffoldBackgroundColor:
        transparentSurface ? Colors.transparent : scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      clipBehavior: Clip.antiAlias,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: scheme.surfaceContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(expressive ? 20 : 12),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
    ),
  );
  if (glassOn) {
    final glassCard = scheme.surface.withValues(alpha: glassOpacity);
    t = t.copyWith(
      tabBarTheme: t.tabBarTheme.copyWith(dividerColor: Colors.transparent),
      dividerTheme: t.dividerTheme.copyWith(
        color: scheme.outlineVariant.withValues(alpha: 0.22),
        thickness: 0.6,
        space: 12,
      ),
      cardTheme: t.cardTheme.copyWith(
        color: glassCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      dialogTheme: t.dialogTheme.copyWith(
        backgroundColor: scheme.surface.withValues(alpha: (glassOpacity + 0.35).clamp(0.0, 1.0)),
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: t.bottomSheetTheme.copyWith(
        backgroundColor: scheme.surface.withValues(alpha: (glassOpacity + 0.25).clamp(0.0, 1.0)),
        modalBackgroundColor: scheme.surface.withValues(alpha: (glassOpacity + 0.25).clamp(0.0, 1.0)),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      // ── 带字按钮一类：全部玻璃化（只留很淡的底色，跟背景融在一起）──
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(
            scheme.primary.withValues(alpha: 0.12),
          ),
          foregroundColor: WidgetStatePropertyAll(scheme.primary),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.primary.withValues(alpha: 0.22)),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(
            scheme.surface.withValues(alpha: glassOpacity),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(
            scheme.surface.withValues(alpha: glassOpacity),
          ),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          side: WidgetStatePropertyAll(
            BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          // 图标按钮本来就没底，别再给它加一块（会和胶囊边缘打架）
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          side: const WidgetStatePropertyAll(BorderSide.none),
          elevation: const WidgetStatePropertyAll(0),
          // 选中态也用胶囊圆角，不然和外面胶囊边界对不上
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          ),
        ),
      ),
      // 筛选面板里那些小标签（FilterChip）也玻璃化
      // 小标签一律不要底（用户明确要求"能融就融"）
      chipTheme: t.chipTheme.copyWith(
        backgroundColor: Colors.transparent,
        selectedColor: scheme.primary.withValues(alpha: 0.25),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
      // 输入框也别再铺那层不透明底（否则会和玻璃层叠成两层）
      inputDecorationTheme:
          t.inputDecorationTheme.copyWith(fillColor: Colors.transparent),
      // 列表行完全透明（文字直接叠在背景图上），不要色块
      listTileTheme: t.listTileTheme.copyWith(tileColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface.withValues(alpha: 0.88),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius + 6),
        ),
      ),
      snackBarTheme: t.snackBarTheme.copyWith(
        backgroundColor: scheme.surface.withValues(alpha: 0.90),
      ),
    );
  }
  return t.applyFont(fontFamily: fontFamily, fontColor: fontColor);
}

/// 字体 / 文字颜色的统一落地（要求 L105）
extension _ThemeFont on ThemeData {
  ThemeData applyFont({String? fontFamily, Color? fontColor}) {
    var t = this;
    if (fontFamily != null) {
      t = t.copyWith(textTheme: t.textTheme.apply(fontFamily: fontFamily));
    }
    if (fontColor != null) {
      // 页面里大量写的是 colorScheme.onSurface / onSurfaceVariant，
      // 只改 textTheme 是没用的，得把这些一起换掉才「真的生效」
      final cs = t.colorScheme.copyWith(
        onSurface: fontColor,
        onSurfaceVariant: fontColor,
      );
      t = t.copyWith(
        colorScheme: cs,
        textTheme: t.textTheme.apply(bodyColor: fontColor, displayColor: fontColor),
        iconTheme: t.iconTheme.copyWith(color: fontColor),
      );
    }
    return t;
  }
}
