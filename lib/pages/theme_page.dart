import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'look_page.dart' show showColorPickerDialog;
import '../widgets/glass.dart';
import '../data/haptics.dart';
import '../widgets/pill_switch.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 主题配色（二级菜单）——调色板样式（要求：动态取色改成调色板）
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  /// Material 3 风格的成套调色板：每个 = 一个主色 + 4 个同族色
  static const Map<String, List<Color>> palettes = {
    '琉璃蓝': [Color(0xFF3F7FBF), Color(0xFF7EB3E0), Color(0xFF1E4E7C), Color(0xFFBBD8F2), Color(0xFF0F3355)],
    '青碧': [Color(0xFF2AA198), Color(0xFF6FD3C7), Color(0xFF116B66), Color(0xFFB2E8E0), Color(0xFF064744)],
    '薄荷': [Color(0xFF4CAF86), Color(0xFF8DD9B6), Color(0xFF24714F), Color(0xFFC7EEDA), Color(0xFF104633)],
    '珊瑚': [Color(0xFFE06C75), Color(0xFFF0A0A6), Color(0xFF9E3C45), Color(0xFFF8CFD3), Color(0xFF6B2129)],
    '赤金': [Color(0xFFD08B2C), Color(0xFFE8B163), Color(0xFF8B5410), Color(0xFFF5DDB5), Color(0xFF5C3506)],
    '鹅黄': [Color(0xFFCBB23C), Color(0xFFE3D07A), Color(0xFF8A7311), Color(0xFFF3EBC0), Color(0xFF5A4A05)],
    '薰衣草': [Color(0xFF8E7CD8), Color(0xFFBBAEEA), Color(0xFF5A479E), Color(0xFFDCD4F5), Color(0xFF352765)],
    '梅子': [Color(0xFFC25C9C), Color(0xFFE08DBD), Color(0xFF8A3068), Color(0xFFF3C8DF), Color(0xFF5C1741)],
    '灰蓝': [Color(0xFF5A6B7C), Color(0xFF8B9AAB), Color(0xFF33404D), Color(0xFFC5CFD9), Color(0xFF1C252E)],
    '石板灰': [Color(0xFF6E7B7A), Color(0xFF9EAAAA), Color(0xFF465050), Color(0xFFD2DADA), Color(0xFF2A3232)],
    '焦糖': [Color(0xFF9A6B4F), Color(0xFFC39A80), Color(0xFF6B4128), Color(0xFFE3CDC0), Color(0xFF422716)],
    '墨黑': [Color(0xFF3A3F45), Color(0xFF6C737B), Color(0xFF1E2227), Color(0xFFB7BDC4), Color(0xFF0C0F12)],
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('主题配色'))),
      body: ListView(
        padding: EdgeInsets.only( bottom: 28),
        children: [
          _Head(tr('明暗')),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: PillSwitch(
              labels: [tr('跟随系统'), tr('浅色'), tr('深色')],
              icons: const [
                Icons.brightness_auto,
                Icons.light_mode,
                Icons.dark_mode,
              ],
              index: s.themeMode.index,
              onChanged: (i) => s.setThemeMode(ThemeMode.values[i]),
            ),
          ),
          const Divider(),
          _Head(tr('调色板')),
          SwitchListTile(
            secondary: const Icon(Icons.colorize),
            value: s.dynamicColor,
            onChanged: (v) { Haptics.tick(s.haptics); s.setDynamicColor(v); },
            title: Text(tr('跟随系统动态取色')),
            subtitle: Text(tr('取壁纸色（Material You）')),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(tr('点一个色系换整套配色'),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final e in palettes.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => s.setSeed(e.value.first),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: s.seed.toARGB32() == e.value.first.toARGB32()
                              ? scheme.primary
                              : scheme.outlineVariant,
                          width: s.seed.toARGB32() == e.value.first.toARGB32()
                              ? 2
                              : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(tr(e.key),
                                style: const TextStyle(fontSize: 12.5)),
                          ),
                          for (final c in e.value)
                            Expanded(
                              child: Container(
                                height: 34,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: c,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          _Head(tr('精细调色')),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(tr('调色盘')),
            subtitle: Text(tr('自选/色号/从壁纸或背景取色')),
            trailing: CircleAvatar(radius: 12, backgroundColor: s.seed),
            onTap: () async {
              final c = await showColorPickerDialog(context, s.seed, s,
                  title: tr('主题主色'));
              if (c != null) s.setSeed(c);
            },
          ),
        ],
      ),
    );
  }
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
