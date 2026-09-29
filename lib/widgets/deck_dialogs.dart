import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../l10n/l10n.dart';

/// 新建构筑的弹窗（底栏「构筑」页和「我的 → 构筑」页共用）
Future<void> showCreateDeckDialog(BuildContext context, AppState state) async {
  final ctrl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('新建构筑')),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(hintText: tr('构筑名，如「雪之铁槌」')),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(tr('取消')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: Text(tr('建立')),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) {
    state.createDeck(name);
  }
}
