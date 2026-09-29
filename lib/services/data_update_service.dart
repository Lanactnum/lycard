import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 数据热更新。
///
/// 思路：卡表 / 翻译 / 词条 / 禁限表 / 搜索索引这几类数据都能**独立于 APK**
/// 更新。App 目录里存在热更文件时优先用热更的，否则回退内置资源。
///
/// 版本清单格式（`data_version.json`）：
/// ```json
/// {
///   "version": "2026.09.29",
///   "notes": "更新内容",
///   "files": { "cards_app.json": "sha256或省略", ... }
/// }
/// ```
class DataUpdate {
  const DataUpdate({
    required this.version,
    required this.notes,
    required this.files,
  });

  final String version;
  final String notes;
  final Map<String, String> files;
}

class DataUpdateService {
  DataUpdateService._();
  static final DataUpdateService instance = DataUpdateService._();

  /// 版本清单文件名
  static const String manifestName = 'data_version.json';

  /// 热更数据支持的逻辑文件名 → 内置资源路径
  static const Map<String, String> logicalToAsset = {
    'cards_app.json': 'assets/data/cards_app.json',
    'translations_zh.json': 'assets/data/translations_zh.json',
    'name_refs.json': 'assets/data/name_refs.json',
    'keywords.json': 'assets/data/keywords.json',
    'banlist.json': 'assets/data/banlist.json',
    'search_keys.json.gz': 'assets/data/search_keys.json.gz',
  };

  Directory? _override;

  @visibleForTesting
  void useDir(Directory? dir) => _override = dir;

  Future<Directory?> dataDir({bool create = false}) async {
    final override = _override;
    if (override != null) return override;
    try {
      Directory? base;
      try {
        base = await getExternalStorageDirectory();
      } catch (_) {}
      base ??= await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/data_update');
      if (create && !d.existsSync()) d.createSync(recursive: true);
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 读取当前热更版本清单（没有就返回 null）
  Future<DataUpdate?> current() async {
    final dir = await dataDir();
    if (dir == null) return null;
    final f = File('${dir.path}/data_version.json');
    if (!f.existsSync()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return DataUpdate(
        version: '${j['version'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
        files: ((j['files'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', '$v')),
      );
    } catch (_) {
      return null;
    }
  }

  /// 读取某个逻辑数据文件：热更优先，其次内置资源
  Future<String?> readString(String logical, Future<String> Function() asset) async {
    final dir = await dataDir();
    if (dir != null) {
      final f = File('${dir.path}/$logical');
      if (f.existsSync()) {
        try {
          return await f.readAsString();
        } catch (_) {
          // 热更文件坏了就退回内置
        }
      }
    }
    try {
      return await asset();
    } catch (_) {
      return null;
    }
  }

  /// 读取二进制数据文件（搜索索引是 gz）
  Future<Uint8List?> readBytes(String logical, Future<Uint8List> Function() asset) async {
    final dir = await dataDir();
    if (dir != null) {
      final f = File('${dir.path}/$logical');
      if (f.existsSync()) {
        try {
          return await f.readAsBytes();
        } catch (_) {}
      }
    }
    try {
      return await asset();
    } catch (_) {
      return null;
    }
  }

  /// 应用一份热更清单（调用方负责已经把文件放进 dataDir）
  Future<void> writeManifest(DataUpdate update) async {
    final dir = await dataDir(create: true);
    if (dir == null) return;
    final f = File('${dir.path}/data_version.json');
    await f.writeAsString(jsonEncode({
      'version': update.version,
      'notes': update.notes,
      'files': update.files,
    }));
  }

  /// 回退到内置数据（删掉热更文件）
  Future<void> clear() async {
    final dir = await dataDir();
    if (dir == null || !dir.existsSync()) return;
    for (final e in dir.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 从用户选的文件安装一份数据更新。
  ///
  /// 两种输入都吃：
  /// · `.zip` 数据包 —— 里面放 [logicalToAsset] 里的文件（放子目录里也行，
  ///   按文件名匹配），可选再放一个 `data_version.json` 提供版本号和说明。
  /// · 单个数据文件本身（例如只更新 `banlist.json`）。
  ///
  /// 只接受白名单里的文件名：数据包里混进别的东西（图片、apk）会被忽略，
  /// 不会往 App 目录里乱塞。
  Future<({bool ok, String? error, String? version, int files})>
      installFromFile(String path) async {
    final dir = await dataDir(create: true);
    if (dir == null) return (ok: false, error: '找不到可写目录', version: null, files: 0);

    final List<int> bytes;
    try {
      bytes = await File(path).readAsBytes();
    } catch (e) {
      return (ok: false, error: '读不到文件：$e', version: null, files: 0);
    }
    if (bytes.isEmpty) {
      return (ok: false, error: '文件是空的', version: null, files: 0);
    }

    final isZip = bytes.length > 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B; // "PK"

    // 待写入的内容：逻辑名 → 字节
    final incoming = <String, List<int>>{};

    // 数据包自带的清单（可选，不写进数据目录，只用来取版本号/说明）
    List<int>? manifestBytes;

    if (isZip) {
      List<ArchiveFile> entries;
      try {
        entries = ZipDecoder().decodeBytes(bytes).files;
      } catch (e) {
        return (ok: false, error: '压缩包打不开：$e', version: null, files: 0);
      }
      for (final f in entries) {
        if (f.isFile == false) continue;
        // 允许放在子目录里，按最后一段文件名匹配
        final base = f.name.split('/').last.split('\\').last;
        if (base == manifestName) {
          manifestBytes ??= f.readBytes();
          continue;
        }
        if (!logicalToAsset.containsKey(base)) continue;
        final b = f.readBytes();
        if (b != null && b.isNotEmpty) incoming[base] = b;
      }
      if (incoming.isEmpty) {
        return (
          ok: false,
          error: '数据包里没有可识别的数据文件',
          version: null,
          files: 0
        );
      }
    } else {
      final base = path.split('/').last.split('\\').last;
      if (!logicalToAsset.containsKey(base)) {
        return (
          ok: false,
          error: '这个文件名不认识（只支持卡表/翻译/词条/禁限表/搜索索引）',
          version: null,
          files: 0
        );
      }
      incoming[base] = bytes;
    }

    // 版本号：优先数据包里的 data_version.json，其次文件自带字段，最后用日期
    var version = '';
    var notes = '';
    if (manifestBytes != null) {
      try {
        final j = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
        version = '${j['version'] ?? ''}';
        notes = '${j['notes'] ?? ''}';
      } catch (_) {}
    }
    if (version.isEmpty) {
      version = _guessVersion(incoming);
    }

    // 落盘：逐个写，写完再写清单（清单最后写，保证半途失败时旧数据仍可用）
    var written = 0;
    for (final e in incoming.entries) {
      try {
        await File('${dir.path}/${e.key}').writeAsBytes(e.value);
        written++;
      } catch (_) {}
    }
    if (written == 0) {
      return (ok: false, error: '写入失败，检查存储权限', version: null, files: 0);
    }
    await writeManifest(DataUpdate(
      version: version,
      notes: notes,
      files: {
        for (final k in incoming.keys) k: '${incoming[k]!.length}',
      },
    ));
    return (ok: true, error: null, version: version, files: written);
  }

  /// 猜一个版本号：禁限表用 updatedAt，其它用今天日期
  String _guessVersion(Map<String, List<int>> incoming) {
    final ban = incoming['banlist.json'];
    if (ban != null) {
      try {
        final j = jsonDecode(utf8.decode(ban)) as Map<String, dynamic>;
        final v = '${j['updatedAt'] ?? j['fetchedAt'] ?? ''}';
        if (v.isNotEmpty) return v;
      } catch (_) {}
    }
    final now = DateTime.now();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '${now.year}.$m.$d';
  }
}
