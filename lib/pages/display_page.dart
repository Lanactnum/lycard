import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../widgets/glass.dart';
import '../data/haptics.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 显示与检索（二级菜单）
class DisplayPage extends StatelessWidget {
  const DisplayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('显示与检索'))),
      body: ListView(
        padding: EdgeInsets.only( bottom: 28),
        children: [
          _Head(tr('剪贴板')),
          SwitchListTile(
            secondary: const Icon(Icons.content_paste_go),
            value: s.clipboardWatch,
            onChanged: s.setClipboardWatch,
            title: Text(tr('剪贴板监听')),
            subtitle: Text(tr('复制卡号或分享码后，回到App时自动识别')),
          ),
          const Divider(),
          _Head(tr('界面')),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(tr('界面语言')),
            subtitle: Text(s.lang.label),
            onTap: () => pickLang(context, s),
          ),
          ListTile(
            leading: const Icon(Icons.zoom_in),
            title: Text(tr('界面缩放（DPI）')),
            subtitle: Text('${(s.dpiScale * 100).round()}%'),
          ),
          Slider(
            value: s.dpiScale,
            min: 0.8,
            max: 1.4,
            divisions: 12,
            label: '${(s.dpiScale * 100).round()}%',
            onChanged: (v) { Haptics.tick(s.haptics); s.setDpiScale(v); },
          ),
          ListTile(
            title: Text(tr('每行卡片数')),
            subtitle: Text(s.gridColumns == 0
                ? tr('自动')
                : tr('{0} 列', [s.gridColumns])),
            trailing: DropdownButton<int>(
              value: s.gridColumns,
              onChanged: (v) => s.setGridColumns(v ?? 0),
              items: [
                for (final n in [0, 2, 3, 4, 5, 6, 8])
                  DropdownMenuItem(value: n, child: Text(n == 0 ? tr('自动') : tr('{0} 列', [n]))),
              ],
            ),
          ),
          Divider(),
          _Head(tr('启动与默认')),
          ListTile(
            title: Text(tr('进入App默认显示')),
            subtitle: Text(
                [tr('检索'), tr('计算器'), tr('构筑'), tr('我的')][s.startTab.clamp(0, 3)]),
            trailing: DropdownButton<int>(
              value: s.startTab.clamp(0, 3),
              onChanged: (v) => s.setStartTab(v ?? 0),
              items: [
                DropdownMenuItem(value: 0, child: Text(tr('检索'))),
                DropdownMenuItem(value: 1, child: Text(tr('计算器'))),
                DropdownMenuItem(value: 2, child: Text(tr('构筑'))),
                DropdownMenuItem(value: 3, child: Text(tr('我的'))),
              ],
            ),
          ),
          SwitchListTile(
            value: s.useZh,
            onChanged: (v) { Haptics.tick(s.haptics); s.setUseZh(v); },
            title: Text(tr('默认显示中文')),
            
          ),
          SwitchListTile(
            title: Text(tr('列表里显示效果文字')),
            value: s.showEffectInGrid,
            onChanged: (v) { Haptics.tick(s.haptics); s.setShowEffectInGrid(v); },
          ),
          const Divider(),
          _Head(tr('检索与手感')),
          SwitchListTile(
            title: Text(tr('搜索框默认数字键盘')),
            subtitle: Text(tr('默认弹数字键盘')),
            value: s.searchNumberPad,
            onChanged: (v) { Haptics.tick(s.haptics); s.setSearchNumberPad(v); },
          ),
          SwitchListTile(
            title: Text(tr('震动反馈')),
            subtitle: Text(tr('加卡/删卡/报错')),
            value: s.haptics,
            onChanged: (v) { Haptics.tick(s.haptics); s.setHaptics(v); },
          ),
        ],
      ),
    );
  }
}

/// 选界面语言（要求 L103）。只影响 App 本体文案 ——
/// 卡名与效果文本属于卡数据，不随界面语言变。
Future<void> pickLang(BuildContext context, AppState state) async {
  final picked = await showGlassSheet<AppLang>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tr('界面语言'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            subtitle: Text(tr('卡名与效果文本不随此设置变化'),
                style: TextStyle(fontSize: 11)),
          ),
          for (final l in AppLang.values)
            ListTile(
              title: Text(l.label),
              trailing: state.lang == l
                  ? Icon(Icons.check, color: Theme.of(c).colorScheme.primary)
                  : null,
              onTap: () => Navigator.pop(c, l),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (picked != null) state.setLang(picked);
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );
}
