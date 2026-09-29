import 'package:flutter/material.dart';

/// 自适应列数：竖屏手机 2 列，平板/横屏自动变多；用户也可以手动锁定列数。
int resolveColumns(BuildContext context, int manual) {
  if (manual > 0) return manual;
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return 2; // 手机竖屏
  if (w < 900) return 3; // 小平板 / 手机横屏
  if (w < 1280) return 4; // 平板横屏
  return 6;
}

/// 2x3 比例的网格间距（按屏宽自适应）
double resolveGap(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w < 600) return 8;
  if (w < 1280) return 12;
  return 16;
}

/// 是否为「宽屏」布局（平板 / 横屏）
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;
