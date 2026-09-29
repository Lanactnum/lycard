import 'package:flutter/services.dart';

/// 震动反馈（要求 L119）
///
/// 调用点直接把「设置里开关的状态」传进来，省得再读一次 Provider。
/// - 加卡片：轻微点按
/// - 删卡片：双击轻震
/// - 构筑合法性报错：短促强震
class Haptics {
  Haptics._();

  /// 加卡片 / 一般点按
  static void tap(bool on) {
    if (!on) return;
    HapticFeedback.lightImpact();
  }

  /// 删卡片：先一下轻点，再一下中等（双击轻震）
  static Future<void> doubleTap(bool on) async {
    if (!on) return;
    HapticFeedback.selectionClick();
    await Future.delayed(const Duration(milliseconds: 90));
    HapticFeedback.mediumImpact();
  }

  /// 构筑不合规：短促强震
  static void strong(bool on) {
    if (!on) return;
    HapticFeedback.heavyImpact();
  }

  /// 开关 / 选中
  static void tick(bool on) {
    if (!on) return;
    HapticFeedback.selectionClick();
  }
}
