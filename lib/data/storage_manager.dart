import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/l10n.dart';

/// 一类可以清理的数据
class CleanCategory {
  CleanCategory({
    required this.id,
    required this.label,
    required this.desc,
    required this.files,
    required this.bytes,
  });

  final String id;
  final String label;
  final String desc;
  final List<File> files;
  final int bytes;

  int get count => files.length;

  String get sizeText => humanSize(bytes);

  bool get isEmpty => files.isEmpty;
}

/// 垃圾桶里的一条记录
class TrashEntry {
  TrashEntry({
    required this.id,
    required this.label,
    required this.deletedAt,
    required this.bytes,
    required this.fileCount,
  });

  final String id;
  final String label;
  final DateTime deletedAt;
  final int bytes;
  final int fileCount;

  static const int keepDays = 15;

  /// 还剩几天可撤销（<=0 表示已过期）
  int get daysLeft =>
      keepDays - DateTime.now().difference(deletedAt).inDays;

  bool get expired => daysLeft <= 0;

  String get sizeText => humanSize(bytes);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'deletedAt': deletedAt.toIso8601String(),
        'bytes': bytes,
        'fileCount': fileCount,
      };

  static TrashEntry fromJson(Map<String, dynamic> j) => TrashEntry(
        id: '${j['id']}',
        label: '${j['label']}',
        deletedAt:
            DateTime.tryParse('${j['deletedAt']}') ?? DateTime.now(),
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        fileCount: (j['fileCount'] as num?)?.toInt() ?? 0,
      );
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// 存储管理：分类扫描 App 自己产生的额外数据 → 清理进「垃圾桶」→ 15 天内可撤销。
///
/// 注意：清理的是**数据**不是**设置**；设置项不会被碰到。
class StorageManager {
  StorageManager._();

  static final StorageManager instance = StorageManager._();

  Directory? _filesOverride;
  Directory? _cacheOverride;

  /// 测试用：指定目录，避免依赖 path_provider 的平台通道
  @visibleForTesting
  void useDirs({Directory? files, Directory? cache}) {
    _filesOverride = files;
    _cacheOverride = cache;
  }

  Future<Directory?> filesDir() async {
    if (_filesOverride != null) return _filesOverride;
    try {
      final d = await getExternalStorageDirectory();
      if (d != null) return d;
    } catch (_) {}
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> cacheDir() async {
    if (_cacheOverride != null) return _cacheOverride;
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return null;
    }
  }

  Future<Directory?> trashDir({bool create = false}) async {
    final f = await filesDir();
    if (f == null) return null;
    final d = Directory('${f.path}/.trash');
    if (create && !d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 想要/出卡的实拍图存放目录
  Future<Directory?> photosDir({bool create = false}) async {
    final f = await filesDir();
    if (f == null) return null;
    final d = Directory('${f.path}/photos');
    if (create && !d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 背景图目录（要求 L117）
  Future<Directory?> bgDir({bool create = false}) async {
    final f = await filesDir();
    if (f == null) return null;
    final d = Directory('${f.path}/backgrounds');
    if (create && !d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<String?> saveBg(List<int> bytes, String ext) async {
    final dir = await bgDir(create: true);
    if (dir == null) return null;
    final name = 'bg${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      // 换新背景时把旧的删掉，别囤垃圾
      for (final e in dir.listSync()) {
        if (e is File) {
          try {
            e.deleteSync();
          } catch (_) {}
        }
      }
      File('${dir.path}/$name').writeAsBytesSync(bytes);
      return name;
    } catch (_) {
      return null;
    }
  }

  Future<String?> bgPath(String name) async {
    final dir = await bgDir();
    if (dir == null) return null;
    final p = '${dir.path}/$name';
    return File(p).existsSync() ? p : null;
  }

  /// 自定义字体目录（要求 L105）
  Future<Directory?> fontsDir({bool create = false}) async {
    final f = await filesDir();
    if (f == null) return null;
    final d = Directory('${f.path}/fonts');
    if (create && !d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<String?> saveFont(List<int> bytes, String ext) async {
    final dir = await fontsDir(create: true);
    if (dir == null) return null;
    for (final e in dir.listSync()) {
      if (e is File) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
    final name = 'font.${ext.toLowerCase()}';
    try {
      File('${dir.path}/$name').writeAsBytesSync(bytes);
      return name;
    } catch (_) {
      return null;
    }
  }

  Future<String?> fontPath(String name) async {
    final dir = await fontsDir();
    if (dir == null) return null;
    final p = '${dir.path}/$name';
    return File(p).existsSync() ? p : null;
  }

  /// 换卡面用的图片目录
  Future<Directory?> cardsDir({bool create = false}) async {
    final f = await filesDir();
    if (f == null) return null;
    final d = Directory('${f.path}/cards');
    if (create && !d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 存一张自定义卡面，返回文件名
  Future<String?> saveCardImage(List<int> bytes, String ext) async {
    final dir = await cardsDir(create: true);
    if (dir == null) return null;
    final name = 'c${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      File('${dir.path}/$name').writeAsBytesSync(bytes);
      return name;
    } catch (_) {
      return null;
    }
  }

  /// 自定义卡面的完整路径
  Future<String?> cardImagePath(String name) async {
    final dir = await cardsDir();
    if (dir == null) return null;
    final p = '${dir.path}/$name';
    return File(p).existsSync() ? p : null;
  }

  /// 把一张实拍图存进 App 目录，返回文件名
  Future<String?> savePhoto(List<int> bytes, String ext) async {
    final dir = await photosDir(create: true);
    if (dir == null) return null;
    final name = 'p${DateTime.now().microsecondsSinceEpoch}.$ext';
    try {
      File('${dir.path}/$name').writeAsBytesSync(bytes);
      return name;
    } catch (_) {
      return null;
    }
  }

  /// 照片的完整路径（读不到就返回 null）
  Future<String?> photoPath(String name) async {
    final dir = await photosDir();
    if (dir == null) return null;
    final p = '${dir.path}/$name';
    return File(p).existsSync() ? p : null;
  }

  // ---------------------------------------------------------------- 扫描

  Future<List<CleanCategory>> scan() async {
    final out = <CleanCategory>[];
    final files = await filesDir();
    final cache = await cacheDir();

    if (files != null && files.existsSync()) {
      out.add(_pick(
        id: 'pack',
        label: tr('卡图数据包'),
        desc: tr('离线原图包'),
        files: _list(files).where((f) {
          final n = _name(f).toLowerCase();
          return n.endsWith('.pack') ||
              n.endsWith('.pack.part') ||
              n.endsWith('.pack.tmp');
        }).toList(),
      ));

      final backupDir = Directory('${files.path}/backups');
      out.add(_pick(
        id: 'backup',
        label: tr('导出的备份文件'),
        desc: tr('导出的构筑/收藏备份'),
        files: backupDir.existsSync() ? _list(backupDir) : const [],
      ));

      final photoDir = Directory('${files.path}/photos');
      out.add(_pick(
        id: 'photos',
        label: tr('实拍图'),
        desc: tr('想要/出卡里添加的实拍照片'),
        files: photoDir.existsSync() ? _list(photoDir) : const [],
      ));

      final bgDir = Directory('${files.path}/backgrounds');
      out.add(_pick(
        id: 'bg',
        label: tr('自定义背景图'),
        desc: tr('软件背景'),
        files: bgDir.existsSync() ? _list(bgDir) : const [],
      ));

      final artDir = Directory('${files.path}/cards');
      out.add(_pick(
        id: 'art',
        label: tr('换过的卡面'),
        desc: tr('自定义卡面图片'),
        files: artDir.existsSync() ? _list(artDir) : const [],
      ));
    }

    if (cache != null && cache.existsSync()) {
      out.add(_pick(
        id: 'temp',
        label: tr('临时缓存'),
        desc: tr('临时文件'),
        files: _list(cache),
      ));
    }

    // 垃圾桶本身也列出来，方便一口气倒掉
    final trash = await trashDir();
    if (trash != null && trash.existsSync()) {
      out.add(_pick(
        id: 'trash',
        label: tr('垃圾桶'),
        desc: tr('清空后不可再撤销'),
        files: _list(trash),
      ));
    }

    return out;
  }

  List<File> _list(Directory d) {
    try {
      return d
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  String _name(File f) => f.uri.pathSegments.isEmpty
      ? f.path
      : f.uri.pathSegments.last;

  CleanCategory _pick({
    required String id,
    required String label,
    required String desc,
    required List<File> files,
  }) {
    var bytes = 0;
    for (final f in files) {
      try {
        bytes += f.lengthSync();
      } catch (_) {}
    }
    return CleanCategory(
        id: id, label: label, desc: desc, files: files, bytes: bytes);
  }

  // ------------------------------------------------------------ 清理/撤销

  /// 把这几类数据移进垃圾桶（可撤销）。返回放进垃圾桶的字节数。
  Future<int> clean(List<String> ids) async {
    if (ids.contains('trash')) {
      // 垃圾桶自己 = 直接销毁
      await emptyTrash();
    }
    final cats =
        (await scan()).where((c) => ids.contains(c.id) && c.id != 'trash');
    final trash = await trashDir(create: true);
    if (trash == null) return 0;

    var total = 0;
    for (final c in cats) {
      if (c.files.isEmpty) continue;
      final id = 't${DateTime.now().millisecondsSinceEpoch}'
          '${c.id.hashCode.abs() % 1000}';
      final box = Directory('${trash.path}/$id');
      box.createSync(recursive: true);

      final moved = <Map<String, String>>[];
      var n = 0;
      var bytes = 0;
      for (final f in c.files) {
        try {
          final size = f.lengthSync();
          final dest = '${box.path}/${moved.length}__${_name(f)}';
          f.renameSync(dest);
          moved.add({'from': f.path, 'as': dest});
          bytes += size;
          total += size;
          n++;
        } catch (_) {
          // 单个文件失败就跳过，不影响其它
        }
      }
      File('${box.path}/manifest.json').writeAsStringSync(jsonEncode({
        'id': id,
        'label': c.label,
        'deletedAt': DateTime.now().toIso8601String(),
        'bytes': bytes,
        'fileCount': n,
        'files': moved,
      }));
    }
    return total;
  }

  Future<List<TrashEntry>> trash() async {
    final dir = await trashDir();
    if (dir == null || !dir.existsSync()) return const [];
    final out = <TrashEntry>[];
    for (final e in dir.listSync()) {
      if (e is! Directory) continue;
      final m = File('${e.path}/manifest.json');
      if (!m.existsSync()) continue;
      try {
        out.add(TrashEntry.fromJson(
            jsonDecode(m.readAsStringSync()) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return out;
  }

  /// 撤销：把文件搬回原位
  Future<bool> restore(String id) async {
    final dir = await trashDir();
    if (dir == null) return false;
    final box = Directory('${dir.path}/$id');
    final m = File('${box.path}/manifest.json');
    if (!m.existsSync()) return false;
    final j = jsonDecode(m.readAsStringSync()) as Map<String, dynamic>;
    var ok = true;
    for (final e in (j['files'] as List? ?? const [])) {
      final from = '${(e as Map)['as']}';
      final to = '${e['from']}';
      try {
        final f = File(from);
        if (!f.existsSync()) continue;
        Directory(File(to).parent.path).createSync(recursive: true);
        f.renameSync(to);
      } catch (_) {
        ok = false;
      }
    }
    if (ok) {
      try {
        box.deleteSync(recursive: true);
      } catch (_) {}
    }
    return ok;
  }

  /// 彻底销毁垃圾桶里的某一条 / 全部
  Future<void> purge(String id) async {
    final dir = await trashDir();
    if (dir == null) return;
    try {
      Directory('${dir.path}/$id').deleteSync(recursive: true);
    } catch (_) {}
  }

  Future<void> emptyTrash() async {
    final dir = await trashDir();
    if (dir == null || !dir.existsSync()) return;
    for (final e in dir.listSync()) {
      try {
        e.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  /// 超过 15 天的自动销毁，返回销毁的条目数
  Future<int> purgeExpired() async {
    var n = 0;
    for (final t in await trash()) {
      if (t.expired) {
        await purge(t.id);
        n++;
      }
    }
    return n;
  }
}
