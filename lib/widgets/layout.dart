import 'package:flutter/widgets.dart';

/// 全 app 的版面常量。要调统一改这里。

/// 底栏是悬浮胶囊（extendBody: true），带底栏的页面滚动内容底部要留这么多，
/// 否则最下面的按钮/卡片会被底栏压住。
const double kBottomBarSpace = 132;

/// 页面左右统一内边距：胶囊、搜索框、卡片都用它，左边缘才会一致。
const double kPagePad = 10;

/// 页面内容的常规内边距
const EdgeInsets kPagePadding = EdgeInsets.fromLTRB(kPagePad, 8, kPagePad, kBottomBarSpace);

/// 悬浮底栏（胶囊 + 外边距 + 手势条）实际占掉的高度。
/// 贴在右下角的按钮/FAB 要让开这么多，否则会被底栏压住。
const double kBottomBarHeight = 100;
