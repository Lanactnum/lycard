import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/font_manager.dart';
import '../data/storage_manager.dart';
import '../state/app_state.dart';
import '../widgets/glass.dart';
import '../data/haptics.dart';
import '../widgets/haptic_nav.dart';
import '../widgets/tags.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/bg_crop_page.dart';
import '../l10n/l10n.dart';

/// 外观设置（要求 L99 悬浮页面 / L101 透明效果 / L117 背景更改）
class LookPage extends StatefulWidget {
  const LookPage({super.key});

  @override
  State<LookPage> createState() => _LookPageState();
}

class _LookPageState extends State<LookPage> {


  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('外观'))),
      body: ListView(
        padding: EdgeInsets.only( bottom: 28),
        children: [
          _Head(tr('透明/模糊')),
          _Slider(
            label: tr('模糊强度'),
            value: s.glassBlur,
            min: 0,
            max: 30,
            text: s.glassBlur.toStringAsFixed(0),
            onChanged: s.setGlassBlur,
          ),
          _Slider(
            label: tr('玻璃不透明度'),
            value: s.glassOpacity,
            min: 0.02,
            max: 1,
            text: '${(s.glassOpacity * 100).round()}%',
            onChanged: s.setGlassOpacity,
          ),
          const Divider(),
          _Head(tr('顶栏与胶囊')),
          _Slider(
            label: tr('模糊强度'),
            value: s.barBlur,
            min: 0,
            max: 40,
            text: s.barBlur.toStringAsFixed(0),
            onChanged: s.setBarBlur,
          ),
          _Slider(
            label: tr('不透明度'),
            value: s.barOpacity,
            min: 0.02,
            max: 1,
            text: '${(s.barOpacity * 100).round()}%',
            onChanged: s.setBarOpacity,
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: Text(tr('恢复跟随全局')),
            subtitle: Text(tr('顶栏/底栏/搜索-筛选胶囊 同时调整')),
            onTap: s.resetBarLook,
          ),
          const Divider(),
          _Head(tr('圆角')),
          _Slider(
            label: tr('自定义圆角'),
            value: s.cornerRadiusValue,
            min: 0,
            max: 28,
            text: '${s.cornerRadiusValue.round()} dp',
            onChanged: (v) { Haptics.tick(s.haptics); s.setCornerRadiusValue(v); },
          ),
          const Divider(),
          _Head(tr('软件背景')),
          if (!s.hasBg)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('还没设背景'), style: TextStyle(fontSize: 12)),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => _pickBg(context, s),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(s.hasBg ? tr('换一张背景') : tr('选择背景图')),
                ),
                const SizedBox(width: 10),
                if (s.hasBg)
                  OutlinedButton(
                    onPressed: s.clearBg,
                    child: Text(tr('去掉背景')),
                  ),
              ],
            ),
          ),
          if (s.hasBg) ...[
            _Slider(
              label: tr('亮度'),
              value: s.bgBrightness,
              min: 0.4,
              max: 1.6,
              text: '${(s.bgBrightness * 100).round()}%',
              onChanged: (v) => s.setBgEdit(brightness: v),
            ),
            _Slider(
              label: tr('模糊'),
              value: s.bgBlur,
              min: 0,
              max: 20,
              text: s.bgBlur.toStringAsFixed(0),
              onChanged: (v) => s.setBgEdit(blur: v),
            ),
            _Slider(
              label: tr('缩放'),
              value: s.bgZoom,
              min: 1,
              max: 2,
              text: '${s.bgZoom.toStringAsFixed(2)}×',
              onChanged: (v) => s.setBgEdit(zoom: v),
            ),
            ListTile(
              leading: const Icon(Icons.rotate_90_degrees_cw_outlined),
              title: Text(tr('旋转')),
              subtitle: Text('${s.bgRotation}°'),
              trailing: TextButton(
                onPressed: () => s.setBgEdit(rotation: s.bgRotation + 90),
                child: Text(tr('旋转 90°')),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.crop),
              title: Text(tr('裁剪')),
              subtitle: Text(tr('框选要保留的区域，去掉多余部分')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _cropBg(context, s),
            ),
            _Slider(
              label: tr('遮罩不透明度'),
              value: s.bgMaskOpacity,
              min: 0,
              max: 0.9,
              text: '${(s.bgMaskOpacity * 100).round()}%',
              onChanged: (v) => s.setBgEdit(maskOpacity: v),
            ),
            ListTile(
              leading: const Icon(Icons.format_color_fill),
              title: Text(tr('遮罩颜色')),
              subtitle: Text(
                  '#${s.bgMaskColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'),
              trailing: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: s.bgMaskColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.outlineVariant),
                ),
              ),
              onTap: () async {
                final c = await showColorPickerDialog(
                    context, s.bgMaskColor, s, title: tr('遮罩颜色'));
                if (c != null) s.setBgEdit(maskColor: c.toARGB32());
              },
            ),
          ],
          const Divider(),
          _Head(tr('字体与文字')),
          ListTile(
            leading: const Icon(Icons.font_download_outlined),
            title: Text(tr('选择字体文件')),
            subtitle: Text(s.hasFont
                ? tr('当前：{0}（点此更换）', [s.fontFile])
                : tr('支持 ttf/otf')),
            onTap: () => _pickFont(context, s),
          ),
          ListTile(
            leading: const Icon(Icons.format_color_text),
            title: Text(tr('字体颜色')),
            subtitle: Text(s.fontColor == null
                ? tr('跟随主题')
                : '#${s.fontColor!.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (s.fontColor != null)
                  IconButton(
                    tooltip: tr('恢复跟随主题'),
                    icon: const Icon(Icons.restart_alt),
                    onPressed: () => s.setFontColor(null),
                  ),
                CircleAvatar(
                  radius: 12,
                  backgroundColor: s.fontColor ?? Theme.of(context).colorScheme.primary,
                ),
                IconButton(
                  tooltip: tr('调色盘'),
                  icon: const Icon(Icons.palette_outlined),
                  onPressed: () async {
                    final c = await showColorPickerDialog(
                        context, s.fontColor ?? s.seed, s, title: tr('字体颜色'));
                    if (c != null) s.setFontColor(c);
                  },
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.line_weight),
            value: s.dynWeight,
            onChanged: (v) { Haptics.tick(s.haptics); s.setDynWeight(v); },
            title: Text(tr('动态字重（可变字体）')),
            subtitle: Text(tr('滑动/选中时字重连续变化')),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: Text(tr('恢复默认字体')),
            
            onTap: () async {
              final dir = await StorageManager.instance.fontsDir();
              if (dir != null && dir.existsSync()) {
                for (final e in dir.listSync()) {
                  if (e is File) {
                    try {
                      e.deleteSync();
                    } catch (_) {}
                  }
                }
              }
              FontManager.loadedFile = '';
              s.setFont('');
              if (context.mounted) await suggestRestart(context, tr('恢复默认字体'));

            },
          ),
          const Divider(),
        ],
      ),
    );
  }

  /// 选字体文件（要求 L105）
  Future<void> _pickFont(BuildContext context, AppState s) async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf', 'ttc'],
    );
    final f = r?.files.single;
    if (f == null || f.path == null) return;
    final name = await StorageManager.instance.saveFont(
      await File(f.path!).readAsBytes(),
      f.extension ?? 'ttf',
    );
    if (name == null) return;
    final p = await StorageManager.instance.fontPath(name);
    var ok = false;
    if (p != null) ok = await FontManager.load(p);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('这个字体加载不了（ttc 常见），换 ttf/otf 试试'))),
      );
      return;
    }
    s.setFont(name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('字体已换成 {0}', [f.name]))),
    );
  }

  Future<void> _pickBg(BuildContext context, AppState s) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = res?.files.single;
    if (f == null) return;
    final bytes =
        f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
    if (bytes == null) return;
    final name = await StorageManager.instance
        .saveBg(bytes, (f.extension ?? 'jpg').toLowerCase());
    if (name == null) return;
    s.setBg(image: name);
    await s.resolveBgPath();
  }

  /// 裁剪背景（要求 L117）。
  ///
  /// 裁剪结果**替换**掉当前背景文件，并把旋转归零 ——
  /// 因为裁剪时已经把旋转烘焙进像素了，不归零会被再转一次。
  Future<void> _cropBg(BuildContext context, AppState s) async {
    final path = s.bgPath;
    if (path.isEmpty) return;
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => BgCropPage(imagePath: path, rotation: s.bgRotation),
      ),
    );
    if (bytes == null) return;
    final name = await StorageManager.instance.saveBg(bytes, 'png');
    if (name == null) return;
    s.setBg(image: name);
    await s.resolveBgPath();
    s.setBgEdit(rotation: 0);
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String text;
  final void Function(double) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(
          children: [
            SizedBox(
                width: 84,
                child: Text(label, style: const TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                label: text,
                onChanged: onChanged,
              ),
            ),
            SizedBox(
                width: 54,
                child: Text(text,
                    style: const TextStyle(fontSize: 11),
                    textAlign: TextAlign.right)),
          ],
        ),
      );
}

/// 调色盘（要求 L109）：预设色 + 填色号 + 从系统主题取色 + 从自定义背景取色
Future<Color?> showColorPickerDialog(
  BuildContext context,
  Color initial,
  AppState state, {
  String? title,
}) async {
  // 默认值不能是函数调用（Dart 要求编译期常量），所以在函数体里补
  final titleText = title ?? tr('选颜色');
  final ctrl = TextEditingController(
      text: initial
          .toARGB32()
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2)
          .toUpperCase());
  final picked = ValueNotifier<Color>(initial);

  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titleText),
      content: SizedBox(
        width: 320,
        child: ValueListenableBuilder<Color>(
          valueListenable: picked,
          builder: (c, col, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final pc in kPaintPalette)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        picked.value = pc;
                        ctrl.text = pc
                            .toARGB32()
                            .toRadixString(16)
                            .padLeft(8, '0')
                            .substring(2)
                            .toUpperCase();
                      },
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: pc,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: col.toARGB32() == pc.toARGB32()
                                ? Theme.of(c).colorScheme.primary
                                : Theme.of(c).colorScheme.outlineVariant,
                            width: col.toARGB32() == pc.toARGB32() ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: col,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(c).colorScheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      decoration: InputDecoration(
                        labelText: tr('颜色代码（#RRGGBB）'),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (t) {
                        final hex = t.replaceAll('#', '').trim();
                        if (hex.length == 6) {
                          final v = int.tryParse(hex, radix: 16);
                          if (v != null) picked.value = Color(0xFF000000 | v);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in kPalette)
                    InkWell(
                      onTap: () {
                        picked.value = p;
                        ctrl.text = p
                            .toARGB32()
                            .toRadixString(16)
                            .padLeft(8, '0')
                            .substring(2)
                            .toUpperCase();
                      },
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: p,
                          shape: BoxShape.circle,
                          border: Border.all(
                            width: col.toARGB32() == p.toARGB32() ? 3 : 1,
                            color: col.toARGB32() == p.toARGB32()
                                ? Theme.of(c).colorScheme.primary
                                : Theme.of(c).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  LyTag(
                    icon: Icons.palette_outlined,
                    label: tr('从系统主题取色'),
                    dense: true,
                    onTap: () {
                      final dyn = Theme.of(c).colorScheme.primary;
                      picked.value = dyn;
                      ctrl.text = dyn
                          .toARGB32()
                          .toRadixString(16)
                          .padLeft(8, '0')
                          .substring(2)
                          .toUpperCase();
                    },
                  ),
                  LyTag(
                    icon: Icons.wallpaper,
                    label: state.hasBg ? tr('从背景图取色') : tr('从背景图取色'),
                    dense: true,
                    onTap: !state.hasBg
                        ? null
                        : () async {
                            final bgc = await state.colorFromBackground();
                            if (bgc == null) return;
                            picked.value = bgc;
                            ctrl.text = bgc
                                .toARGB32()
                                .toRadixString(16)
                                .padLeft(8, '0')
                                .substring(2)
                                .toUpperCase();
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: Text(tr('确定'))),
      ],
    ),
  );
  if (ok != true) return null;
  return picked.value;
}

const List<Color> kPalette = [
  Color(0xFF3F7FBF), Color(0xFF2196F3), Color(0xFF00ACC1), Color(0xFF26A69A),
  Color(0xFF4CAF50), Color(0xFF7CB342), Color(0xFFCDDC39), Color(0xFFFFCA28),
  Color(0xFFFFA726), Color(0xFFFF7043), Color(0xFFEF5350), Color(0xFFEC407A),
  Color(0xFFAB47BC), Color(0xFF7E57C2), Color(0xFF5C6BC0), Color(0xFF8D6E63),
  Color(0xFF9E9E9E), Color(0xFF607D8B), Color(0xFF000000), Color(0xFFFFFFFF),
];

/// 统一的调色板（要求：颜色选择都用调色板形式，不要只给固定几个）
const List<Color> kPaintPalette = [
  Color(0xFFF44336), Color(0xFFE91E63), Color(0xFF9C27B0), Color(0xFF673AB7),
  Color(0xFF3F51B5), Color(0xFF2196F3), Color(0xFF03A9F4), Color(0xFF00BCD4),
  Color(0xFF009688), Color(0xFF4CAF50), Color(0xFF8BC34A), Color(0xFFCDDC39),
  Color(0xFFFFEB3B), Color(0xFFFFC107), Color(0xFFFF9800), Color(0xFFFF5722),
  Color(0xFF795548), Color(0xFF9E9E9E), Color(0xFF607D8B), Color(0xFF000000),
  Color(0xFF37474F), Color(0xFF546E7A), Color(0xFFD32F2F), Color(0xFFFFFFFF),
];

