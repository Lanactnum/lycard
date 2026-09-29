import 'package:flutter/material.dart';

import '../data/haptics.dart';
import '../l10n/l10n.dart';

/// 返回手势也震一下（要求 L119：返回 / 开关 / 添加 / 删除 / 报错 都要适配）
class HapticNavigatorObserver extends NavigatorObserver {
  HapticNavigatorObserver(this.enabled);

  final bool Function() enabled;

  @override
  void didPop(Route route, Route? previousRoute) {
    Haptics.tick(enabled());
    super.didPop(route, previousRoute);
  }
}

/// 「改完要重启才生效」的统一提示（要求：改设置尽量立即生效，非要重启就问一声）
Future<void> suggestRestart(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('需要重启')),
      content: Text(tr('{0} 要重启 App 才完全生效。现在重启吗？', [what])),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false), child: Text(tr('稍后'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: Text(tr('立即重启'))),
      ],
    ),
  );
  if (ok == true) {
    // 桌面端/调试环境下直接退出进程由系统重开
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // ignore: avoid_print
    debugPrint('lycard-重启请求：$what');
  }
}
