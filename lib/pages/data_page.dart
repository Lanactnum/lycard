import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/backup.dart';
import '../data/card_pack.dart';
import '../data/storage_manager.dart';
import '../services/data_update_service.dart';
import '../state/app_state.dart';
import '../widgets/glass.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 数据与备份（二级菜单）：备份导出/导入 + 卡图数据包
class DataPage extends StatefulWidget {
  const DataPage({super.key});

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  bool _importing = false;
  double _progress = 0;

  /// 当前生效的热更数据版本（null = 用的内置数据）
  String? _hotVersion;
  String? _hotNotes;
  bool _dataBusy = false;

  @override
  void initState() {
    super.initState();
    _loadHotVersion();
  }

  Future<void> _loadHotVersion() async {
    final u = await DataUpdateService.instance.current();
    if (!mounted) return;
    setState(() {
      _hotVersion = (u?.version.isEmpty ?? true) ? null : u!.version;
      _hotNotes = (u?.notes.isEmpty ?? true) ? null : u!.notes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pack = CardPack.instance;

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('数据与备份'))),
      body: ListView(
        padding: EdgeInsets.only( bottom: 28),
        children: [
          _Head(tr('备份与恢复')),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(tr('导出备份')),
            subtitle: Text(tr('构筑/收藏/想要出卡/实拍图/卡面/背景/字体/设置')),
            onTap: () => _export(context, s),
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: Text(tr('导入备份')),
            subtitle: Text(tr('含图片资源；会覆盖现有数据')),
            onTap: () => _import(context, s),
          ),
          const Divider(),
          _Head(tr('卡图数据包')),
          ListTile(
            leading: Icon(
              pack.ready ? Icons.check_circle : Icons.folder_off_outlined,
              color: pack.ready ? Colors.green : null,
            ),
            title: Text(pack.ready
                ? tr('已挂载 {0} 张图', [pack.count])
                : tr('还未挂载数据包')),
            subtitle: Text(
              pack.ready
                  ? tr('位置：{0}\\n读图命中 {1} 次', [pack.dir, pack.hits])
                  : tr('将 {0} 放至\\n/sdcard/Android/data/com.lycard.app/files/\\n或选择「从文件管理器选择数据包」', [CardPack.packName]),
            ),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(tr('从文件管理器选择数据包')),
            subtitle: _importing
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(value: _progress),
                  )
                : Text(tr('选择lycee_cards.pack，导入到App目录后自动挂载')),
            onTap: _importing ? null : _importPack,
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(tr('重新扫描数据包')),
            onTap: () async {
              final ok = await CardPack.instance.autoOpen();
              if (!context.mounted) return;
              _toast(context,
                  ok ? tr('数据包已挂载：{0} 张图', [CardPack.instance.count]) : tr('未发现数据包，检查路径和文件名'));
            },
          ),
          const Divider(),
          _Head(tr('卡表数据热更新')),
          ListTile(
            leading: Icon(
              _hotVersion == null
                  ? Icons.inventory_2_outlined
                  : Icons.check_circle_outline,
              color: _hotVersion == null ? null : Colors.green,
            ),
            title: Text(_hotVersion == null
                ? tr('正在使用内置数据')
                : tr('已应用热更数据 {0}', [_hotVersion!])),
            subtitle: Text(_hotNotes ??
                tr('可热更：卡表、中文翻译、卡名词条、禁限卡表、搜索索引。卡图仍走内置压缩图 / 外挂原图包。')),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.system_update_alt),
            title: Text(tr('从文件选择数据包')),
            subtitle: _dataBusy
                ? const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: LinearProgressIndicator(),
                  )
                : Text(tr('选 .zip 数据包，或单个数据文件；应用后要重启才生效')),
            onTap: _dataBusy ? null : _importDataUpdate,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: Text(tr('回退到内置数据')),
            enabled: _hotVersion != null && !_dataBusy,
            onTap: _hotVersion == null || _dataBusy ? null : _clearDataUpdate,
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context, AppState state) async {
    try {
      // 打成 zip：数据 + 实拍图 / 自定义卡面 / 背景图 / 字体
      // （要求 L15：备份要含实拍图等所有自定义信息与背景图片）
      final bytes = await Backup.pack(state.exportData());
      if (!context.mounted) return;
      final path = await FilePicker.platform.saveFile(
        fileName: Backup.suggestedName(),
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (!context.mounted) return;
      if (path == null) {
        _toast(context, tr('已取消导出'));
      } else {
        final mb = (bytes.length / 1048576).toStringAsFixed(1);
        _toast(context, tr('已导出（{0} MB）：{1}', [mb, path]));
      }
    } catch (e) {
      if (context.mounted) _toast(context, tr('导出失败：{0}', [e]));
    }
  }

  Future<void> _import(BuildContext context, AppState state) async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final f = res?.files.single;
      if (f == null) return;
      final bytes = f.bytes ?? await File(f.path!).readAsBytes();
      final content = Backup.unpack(bytes);
      final j = content.data;
      final decks = (j['decks'] as List? ?? const []).length;
      final owned = (j['owned'] as List? ?? const []).length;
      final wish = (j['wish'] as List? ?? const []).length;
      if (!context.mounted) return;

      final srcDesc = content.isLegacyJson
          ? tr('（旧版备份，不含实拍图等图片）')
          : tr('含图片资源 {0} 个', [content.assetCount]);
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(tr('导入备份')),
          content: Text(
              tr('备份中：构筑 {0} 套 · 已收集 {1} 张 · 想要/出卡 {2} 条\\n{3}\\n\\n导入会覆盖现在的数据，确定吗？', [decks, owned, wish, srcDesc])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
            FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('覆盖导入'))),
          ],
        ),
      );
      if (ok != true) return;

      // 先落图片资源，再写数据 —— 这样数据里记的文件名才有对应文件
      final counts = content.isLegacyJson
          ? const <String, int>{}
          : await Backup.restoreAssets(content.assets);

      final msg = state.importData(j);

      if (content.isLegacyJson) {
        // 旧版备份：背景图是 base64 塞在数据里的
        final bgData = j['bgImageData'];
        if (bgData is String && bgData.isNotEmpty) {
          final ext = '${j['bgImageExt'] ?? 'jpg'}';
          final name = await StorageManager.instance
              .saveBg(base64Decode(bgData), ext);
          if (name != null) state.setBg(image: name);
        }
      } else if (state.bgImage.isNotEmpty) {
        // 新格式：背景图文件已经落盘，重新解一次位图
        await state.resolveBgPath();
      }

      if (!context.mounted) return;
      final pics = counts.values.fold(0, (a, b) => a + b);
      _toast(context, pics > 0 ? tr('已恢复：{0} · 图片 {1} 个', [msg, pics]) : tr('已恢复：{0}', [msg]));
    } catch (e) {
      if (context.mounted) _toast(context, tr('导入失败：{0}', [e]));
    }
  }

  /// 从文件管理器选一个数据包 → 复制进 App 专属目录 → 自动挂载
  Future<void> _importPack() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      if (res == null || res.files.isEmpty) return;
      final picked = res.files.first;
      final src = picked.path;
      if (src == null || src.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(tr('读取文件路径失败，换个文件管理器试试'))),
        );
        return;
      }
      final dir = await CardPack.instance.targetDir();
      if (dir == null) {
        messenger.showSnackBar(SnackBar(content: Text(tr('找不到可写目录'))));
        return;
      }
      setState(() {
        _importing = true;
        _progress = 0;
      });
      final dstName =
          src.toLowerCase().endsWith('.pack') ? CardPack.packName : picked.name;
      final dst = await CardPack.copyInto(
        src,
        dir,
        dstName: dstName,
        onProgress: (done, total) {
          if (total > 0 && mounted) setState(() => _progress = done / total);
        },
      );
      // 文件管理器给的多半是缓存的临时副本，导完删掉省空间
      if (src.contains('/cache/') || src.contains('/tmp/')) {
        try {
          await File(src).delete();
        } catch (_) {}
      }
      final ok = await CardPack.instance.openFile(dst);
      if (mounted) setState(() => _importing = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok
              ? tr('数据包已导入并挂载：{0} 张原图', [CardPack.instance.count])
              : tr('文件复制成功，但不是有效的数据包')),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _importing = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('导入失败：{0}', [e]))));
    }
  }

  /// 从文件管理器选一份卡表数据包 → 装进热更目录
  ///
  /// 数据只在启动时载入一次，所以装完必须重启才生效 —— 这里如实告诉用户，
  /// 不假装已经生效。
  Future<void> _importDataUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final f = res?.files.single;
      if (f == null) return;

      var path = f.path;
      // 有的文件管理器只给字节流，先落到缓存目录再当文件读
      if (path == null || path.isEmpty) {
        final bytes = f.bytes;
        if (bytes == null) {
          messenger.showSnackBar(
              SnackBar(content: Text(tr('读取文件失败，换个文件管理器试试'))));
          return;
        }
        final cache = await StorageManager.instance.cacheDir();
        if (cache == null) {
          messenger.showSnackBar(SnackBar(content: Text(tr('找不到可写目录'))));
          return;
        }
        path = '${cache.path}/${f.name}';
        await File(path).writeAsBytes(bytes);
      }

      setState(() => _dataBusy = true);
      final r = await DataUpdateService.instance.installFromFile(path);
      if (mounted) setState(() => _dataBusy = false);

      if (!r.ok) {
        messenger.showSnackBar(
            SnackBar(content: Text(tr('应用失败：{0}', [r.error ?? '未知原因']))));
        return;
      }
      await _loadHotVersion();
      messenger.showSnackBar(SnackBar(
        content: Text(tr('已应用 {0} 个数据文件（版本 {1}），重启 App 后生效',
            ['${r.files}', r.version ?? ''])),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (mounted) setState(() => _dataBusy = false);
      messenger.showSnackBar(SnackBar(content: Text(tr('应用失败：{0}', [e]))));
    }
  }

  Future<void> _clearDataUpdate() async {
    final messenger = ScaffoldMessenger.of(context);
    await DataUpdateService.instance.clear();
    await _loadHotVersion();
    messenger.showSnackBar(
        SnackBar(content: Text(tr('已回退到内置数据，重启 App 后生效'))));
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
