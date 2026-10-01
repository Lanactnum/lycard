import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import 'data/card_pack.dart';
import 'data/card_repository.dart';
import 'data/keyword_db.dart';
import 'data/storage_manager.dart';
import 'data/haptics.dart';
import 'data/font_manager.dart';
import 'widgets/glass.dart';
import 'widgets/haptic_nav.dart';
import 'widgets/motion.dart';
import 'pages/calc_page.dart';
import 'pages/card_detail_page.dart';
import 'pages/construct_page.dart';
import 'pages/mine_page.dart';
import 'pages/search_page.dart';
import 'state/app_state.dart';
import 'theme.dart';
import 'pages/look_page.dart';
import 'data/search_index.dart';
import 'data/clipboard_watch.dart';
import 'widgets/clipboard_sheet.dart';
import 'widgets/deck_import_dialog.dart';
import 'widgets/card_route.dart';
import 'l10n/l10n.dart';
import 'services/update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';

Future<void> main() async {
  // 诊断用：--dart-define=FRAME_LOG=1 时把慢帧（>32ms）打到 logcat，
  // 用来分清是 build（Dart 侧）慢还是 raster（GPU 侧）慢。
  if (const String.fromEnvironment('FRAME_LOG').isNotEmpty) {
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        final total = t.totalSpan.inMilliseconds;
        if (total > 32) {
          debugPrint('[FRAME] total=${total}ms '
              'build=${t.buildDuration.inMilliseconds}ms '
              'raster=${t.rasterDuration.inMilliseconds}ms '
              'vsync=${t.vsyncOverhead.inMilliseconds}ms');
        }
      }
    });
  }

  WidgetsFlutterBinding.ensureInitialized();
  // 有数据包就直接挂上（找不到也不影响，图片会联网取）
  await CardPack.instance.autoOpen();
  final appState = await AppState.create();
  // 自定义字体（要求 L105）：启动时先挂上，主题才能用
  if (appState.hasFont) {
    final p = await StorageManager.instance.fontPath(appState.fontFile);
    if (p != null) await FontManager.load(p);
  }
  // 背景图路径启动时解析一次（要求：切页面不卡）
  await appState.resolveBgPath();
  // 模糊搜索索引：异步加载，不挡住首屏
  SearchIndex.instance.load();
  await CardRepository.instance.load();
  await KeywordDb.instance.load();
  await appState.initBanList(); // 官方禁限卡表（要求 L83-84）
  // 把用户自定义（改卡信息 / 新建卡）套到卡池上
  CardRepository.instance.setEdits(appState.cardEdits);
  // 垃圾桶里超过 15 天的自动销毁（不阻塞启动）
  StorageManager.instance.purgeExpired();
  // 更新包用完就清（不阻塞启动）
  _cleanUpdateArtifacts();
  runApp(LyceeApp(appState: appState));
}

/// 清掉已经用不上的更新包（用户明确要求：**更新完记得清理更新包**）。
///
/// 装上的版本（文件里版本号 <= 当前版本）和躺太久的残包都删掉 ——
/// 一个更新包 573 MB，留着纯属白占。失败了也不影响启动。
void _cleanUpdateArtifacts() {
  PackageInfo.fromPlatform().then((info) {
    cleanUpdateDir(currentVersion: info.version).then((int freed) {
      if (freed > 0) {
        debugPrint(
            '清掉用不上的更新包：${(freed / 1048576).toStringAsFixed(1)} MB');
      }
    });
  }).catchError((Object _) {
    // 清不了就算了，绝不能因为清理影响启动
  });
}

/// 调试用：`--dart-define=START_CARD=LO-0575` 时启动直接进入那张卡的详情页。
/// （MuMu / 实机的 adb 输入注入不稳，靠这个能稳定截图验证）
const String _startCard = String.fromEnvironment('START_CARD');

/// 诊断用：`--dart-define=LAYOUT_LOG=1` 启动时把底栏实际占用的高度、
/// 系统安全区、界面缩放打出来。底栏「多出一块空白」这类问题靠猜改不出结果 ——
/// 必须分清空白来自系统安全区、NavigationBar 内部补白，还是胶囊外边距。
const String _layoutLog = String.fromEnvironment('LAYOUT_LOG');

class LyceeApp extends StatelessWidget {
  const LyceeApp({super.key, required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          return DynamicColorBuilder(
            builder: (lightDynamic, darkDynamic) {
              final useDyn = state.dynamicColor;
              return MaterialApp(
                title: 'Lycard',
                debugShowCheckedModeBanner: false,
                // 界面语言（要求 L103）：自绘文案走 L10n.tr，
                // 系统自带控件（日期选择、文本选择菜单等）靠这几个 delegate
                locale: state.lang.locale,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales:
                    AppLang.values.map((l) => l.locale).toList(),
                themeMode: state.themeMode,
                // 列表弹性回弹（要求 L125）：全 app 统一用可回弹的物理效果，
      // 并关掉安卓默认的"拉伸/发光"边缘效果
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        overscroll: false,
      ),
      theme: buildLyceeTheme(
                  seed: state.seed,
                  brightness: Brightness.light,
                  dynamicScheme: useDyn ? lightDynamic : null,
                  expressive: false,
                  cornerRadius: state.cornerRadius,
                  transparentSurface: state.hasBg,
                  glassOn: state.glassMode != 0,
                  glassOpacity: state.glassOpacity,
                  fontFamily: FontManager.ready ? FontManager.family : null,
                  fontColor: state.fontColor,
                ),
                darkTheme: buildLyceeTheme(
                  seed: state.seed,
                  brightness: Brightness.dark,
                  dynamicScheme: useDyn ? darkDynamic : null,
                  expressive: false,
                  cornerRadius: state.cornerRadius,
                  transparentSurface: state.hasBg,
                  glassOn: state.glassMode != 0,
                  glassOpacity: state.glassOpacity,
                  fontFamily: FontManager.ready ? FontManager.family : null,
                  fontColor: state.fontColor,
                ),
                // 自定义背景层（要求 L117）垫在所有内容下面。
                //
                // BackdropGroup：让所有 BackdropFilter.grouped 共用**一次**
                // 背景采集。这个 App 里顶栏、底栏、各种玻璃面板都有模糊，
                // 不分组的话每个都要自己 saveLayer + 重采样一遍背景，
                // 滚动时尤其贵。分组后只做一次。
                builder: (context, child) => BackdropGroup(
                  child: Stack(
                    children: [
                      // RepaintBoundary：背景自成一个图层、被光栅缓存。
                      // 不包的话它和上面的 UI 共用一个图层，上面任何
                      // 重绘都会把整张背景跟着重画一遍。
                      const Positioned.fill(
                        child: RepaintBoundary(child: AppBackground()),
                      ),
                      if (child != null) child,
                    ],
                  ),
                ),
                navigatorObservers: [
                  HapticNavigatorObserver(() => appState.haptics),
                  appRouteObserver,
                ],
                home: _startCard.isEmpty
                    ? Builder(
                        builder: (ctx) {
                          final mq = MediaQuery.of(ctx);
                          // DPI / 界面缩放：0.8~1.4（要求 L107）
                          return MediaQuery(
                            data: mq.copyWith(
                              textScaler: TextScaler.linear(
                                  mq.textScaler.scale(1.0) * state.dpiScale),
                            ),
                            child: const HomeShell(),
                          );
                        },
                      )
                    : CardDetailPage(code: _startCard),
              );
            },
          );
        },
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with WidgetsBindingObserver {
  // 剪贴板监听（要求 L73）
  int _index = 0;

  /// 底栏尺寸诊断（只有 --dart-define=LAYOUT_LOG=1 时才打印，且只打一次）
  static final GlobalKey _navSlotKey = GlobalKey();
  static final GlobalKey _navBarKey = GlobalKey();
  bool _layoutLogged = false;

  void _logLayoutOnce() {
    if (_layoutLog.isEmpty || _layoutLogged) return;
    _layoutLogged = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      double? h(GlobalKey k) {
        final b = k.currentContext?.findRenderObject() as RenderBox?;
        return b != null && b.hasSize ? b.size.height : null;
      }

      final mq = MediaQuery.of(context);
      final slot = h(_navSlotKey);
      final nav = h(_navBarKey);
      debugPrint('[LAYOUT] slot=${slot?.toStringAsFixed(1)} '
          'navBar=${nav?.toStringAsFixed(1)} '
          'screen=${mq.size.height.toStringAsFixed(1)} '
          'dpr=${mq.devicePixelRatio.toStringAsFixed(3)} '
          'viewPaddingBottom=${mq.viewPadding.bottom.toStringAsFixed(1)} '
          'paddingBottom=${mq.padding.bottom.toStringAsFixed(1)} '
          'viewInsetsBottom=${mq.viewInsets.bottom.toStringAsFixed(1)} '
          'textScale=${(mq.textScaler.scale(10) / 10).toStringAsFixed(3)}');
    });
  }

  @override
  void initState() {
    super.initState();
    // 调试用：--dart-define=START_TAB=1 直接进构筑页（实机 adb 点不动，靠这个截图）
    WidgetsBinding.instance.addObserver(this);
    // 启动后也检查一次剪贴板
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkClipboard());
    final forced = int.tryParse(const String.fromEnvironment('START_TAB'));
    if (forced != null && forced >= 0 && forced <= 3) {
      _index = forced;
    } else {
      _index = context.read<AppState>().startTab.clamp(0, 3);
    }
    // 诊断用：--dart-define=AUTO_PUSH=1 启动 3 秒后自动进设置页（录屏/帧日志定位过渡问题）
    if (const String.fromEnvironment('AUTO_PUSH').isNotEmpty) {
      debugPrint('[AUTO_PUSH] armed');
      Future.delayed(const Duration(milliseconds: 3000), () {
        if (!mounted) {
          debugPrint('[AUTO_PUSH] not mounted');
          return;
        }
        try {
          debugPrint('[AUTO_PUSH] pushing SettingsPage now');
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const LookPage()),
          );
        } catch (e) {
          debugPrint('[AUTO_PUSH] failed: $e');
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时看一眼剪贴板
    if (state == AppLifecycleState.resumed) _checkClipboard();
  }

  /// 剪贴板监听：分享码 → 问要不要导入；一串卡号 → 浮窗列出来
  Future<void> _checkClipboard() async {
    if (!mounted) return;
    final s = context.read<AppState>();
    final hit = await ClipboardWatch.check(enabled: s.clipboardWatch);
    if (hit == null || !mounted) return;
    if (hit.kind == HitKind.deckShare) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('发现构筑分享码')),
          content: Text(tr('剪贴板里有一段构筑分享码，导入成新卡组吗？')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(tr('不用'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('导入'))),
          ],
        ),
      );
      if (ok == true && mounted) {
        await importDeckFromText(context, s, hit.text);
      }
    } else {
      await showCardCodesSheet(context, s, hit.codes);
    }
  }

  static const _pages = [
    SearchPage(),
    CalcPage(),
    ConstructPage(),
    MinePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // 不再让内容钻到顶栏/底栏下面：Scaffold 自己会让位，
    // 顶栏底栏照样是半透明 + 模糊（糊的是背后的背景图），但绝不遮挡内容。
    // 返回键：不在「检索」页时先回检索页，而不是直接退出 App。
    // 底栏三个页面是同级的，用户在构筑/我的里按返回，预期是"回到主页面"，
    // 直接退出太粗暴（也很容易误触退出）。
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          Haptics.tick(context.read<AppState>().haptics);
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
        backgroundColor: Colors.transparent,
        // 内容从底栏胶囊下面穿过去（这才是"悬浮在内容上"）
        extendBody: true,
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar:
            KeyedSubtree(key: _navSlotKey, child: _navBar(context)),
      ),
    );
  }

  /// 底栏（要求 L99：开了「悬浮页面」就浮起来；配合 L101 玻璃效果）
  Widget _navBar(BuildContext context) {
    _logLayoutOnce();
    // ⚠ 这里以前是 context.watch<AppState>() —— 整个 AppState 一变
    // （比如在检索页打字、开关任意设置）都会让**整个 Scaffold 连同三个
    // 页面一起重建**。底栏真正依赖的只有这两个开关，收窄成 select。
    final chromeKey = context.select<AppState, int>(
        (a) => Object.hash(a.floatingChrome, a.glassEffect));
    final bar = NavigationBar(
      // ★ 关键：NavigationBar 自己默认带不透明底色，会直接把玻璃糊住
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      indicatorColor: Theme.of(context)
          .colorScheme
          .primary
          .withValues(alpha: 0.22),
      selectedIndex: _index,
      onDestinationSelected: (i) {
        // 用 read：这里只需要拿值，不该建立依赖
        Haptics.tick(context.read<AppState>().haptics);
        setState(() => _index = i);
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.search_outlined),
          selectedIcon:
              NavSpring(selected: _index == 0, child: const Icon(Icons.search)),
          label: tr('检索'),
        ),
        // ⚠ 这里的顺序必须和 _pages 一一对应：
        //     [SearchPage, CalcPage, ConstructPage, MinePage]
        //     = 检索(0) / 计算器(1) / 构筑(2) / 我的(3)
        // 之前写反了 —— 下标 1 挂着「构筑」的标签却指向计算器页，
        // 表现就是「点构筑出来的是计算器、点计算器出来的是构筑」。
        NavigationDestination(
          icon: const Icon(Icons.calculate_outlined),
          selectedIcon: NavSpring(
              selected: _index == 1, child: const Icon(Icons.calculate)),
          label: tr('计算器'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.dashboard_customize_outlined),
          selectedIcon: NavSpring(
              selected: _index == 2,
              child: const Icon(Icons.dashboard_customize)),
          label: tr('构筑'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.person_outline),
          selectedIcon:
              NavSpring(selected: _index == 3, child: const Icon(Icons.person)),
          label: tr('我的'),
        ),
      ],
    );
    // 诊断用：量的是 NavigationBar 本体的高度（不含胶囊外边距）
    final boxed = KeyedSubtree(key: _navBarKey, child: bar);
    // chromeKey 只用来触发重建；具体判断还是读实时值
    if (chromeKey == 0) return boxed;
    final s = context.read<AppState>();
    if (!s.floatingChrome && !s.glassEffect) return boxed;
    // 和顶栏共用同一套：通栏 + 同模糊 + 同不透明度
    return BottomGlassBar(child: boxed);
  }
}
