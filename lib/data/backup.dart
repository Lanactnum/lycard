import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'storage_manager.dart';
import '../l10n/l10n.dart';

/// 备份打包/解包（要求 L15）。
///
/// 以前备份是**单个 JSON**：数据没问题，但用户自己的图片（想要/出卡的
/// 实拍图、自定义卡面、背景图、换过的字体）全都留在 App 目录里，
/// 换机恢复后只剩一堆指向不存在文件的文件名 —— 等于没备份。
///
/// 现在打成 zip：
///
///     backup.json              ← AppState.exportData() 的内容
///     assets/photos/xxx.jpg    ← 实拍图
///     assets/cards/xxx.png     ← 自定义卡面
///     assets/backgrounds/xxx.jpg
///     assets/fonts/font.ttf
///
/// 为什么不用 base64 塞进 JSON：图片是二进制，base64 会让体积涨 1/3，
/// 而且几十兆的字符串在手机上编解码很容易把内存吃爆。
///
/// 兼容：导入时看文件头 —— `PK` 走 zip，`{` 走老的 JSON 备份。
class Backup {
  Backup._();

  /// zip 里数据文件的名字
  static const String dataName = 'backup.json';

  /// zip 里资源文件的前缀
  static const String assetPrefix = 'assets/';

  /// 备份格式版本（以后结构变了靠它判断）
  static const int format = 2;

  /// 建议的文件名
  static String suggestedName([DateTime? now]) {
    final d = now ?? DateTime.now();
    final s = '${d.year}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    return 'lycard-backup-$s.zip';
  }

  /// 收集 App 目录里**用户自己的**二进制资源。
  ///
  /// 故意不包含卡图数据包（lycee_cards.pack）—— 那是官方卡图，
  /// 3.9GB，不属于"用户自定义信息"，也不该塞进备份。
  static Future<Map<String, List<int>>> _collectAssets() async {
    final sm = StorageManager.instance;
    final out = <String, List<int>>{};

    Future<void> take(Future<Directory?> Function() dir, String sub) async {
      final d = await dir();
      if (d == null || !d.existsSync()) return;
      for (final e in d.listSync()) {
        if (e is! File) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        try {
          out['$assetPrefix$sub/$name'] = await e.readAsBytes();
        } catch (_) {
          // 单个文件读不了就跳过，别让整个备份失败
        }
      }
    }

    await take(() => sm.photosDir(), 'photos');
    await take(() => sm.cardsDir(), 'cards');
    await take(() => sm.bgDir(), 'backgrounds');
    await take(() => sm.fontsDir(), 'fonts');
    return out;
  }

  /// 打包成 zip 字节
  static Future<Uint8List> pack(Map<String, dynamic> data) async {
    final assets = await _collectAssets();

    // 把资源清单也写进数据里：恢复时才知道该把背景图字段指向哪个文件
    data['assets'] = assets.keys.toList()..sort();
    data['format'] = format;
    data['packedAt'] = DateTime.now().toIso8601String();

    final ar = Archive();
    ar.addFile(ArchiveFile.string(
      dataName,
      const JsonEncoder.withIndent(' ').convert(data),
    ));
    assets.forEach((name, bytes) {
      ar.addFile(ArchiveFile.bytes(name, bytes));
    });

    return ZipEncoder().encodeBytes(ar);
  }

  /// 解开备份，返回数据部分（资源会**另外**返回，由调用方落盘）
  static BackupContent unpack(List<int> bytes) {
    // 老的 JSON 备份：还能用，只是没有图片资源
    if (bytes.length < 4 ||
        !(bytes[0] == 0x50 && bytes[1] == 0x4B)) {
      final text = utf8.decode(bytes);
      final j = jsonDecode(text) as Map<String, dynamic>;
      return BackupContent(data: j, assets: const {}, isLegacyJson: true);
    }

    final ar = ZipDecoder().decodeBytes(bytes);
    final entry = ar.findFile(dataName);
    if (entry == null) {
      throw FormatException(tr('备份文件里没有数据部分'));
    }
    final raw = entry.readBytes();
    if (raw == null) throw const FormatException('备份数据读不出来');
    final data = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;

    final assets = <String, List<int>>{};
    for (final f in ar.files) {
      if (!f.name.startsWith(assetPrefix)) continue;
      final b = f.readBytes();
      if (b != null) assets[f.name] = b;
    }
    return BackupContent(data: data, assets: assets, isLegacyJson: false);
  }

  /// 把资源写回 App 目录。返回各类资源的落地数量，用于给用户看。
  static Future<Map<String, int>> restoreAssets(
      Map<String, List<int>> assets) async {
    final sm = StorageManager.instance;
    final counts = <String, int>{'photos': 0, 'cards': 0, 'backgrounds': 0, 'fonts': 0};

    Future<void> put(
        Future<Directory?> Function({bool create}) dir, String sub) async {
      final targets = assets.entries
          .where((e) => e.key.startsWith('$assetPrefix$sub/'))
          .toList();
      if (targets.isEmpty) return;
      final d = await dir(create: true);
      if (d == null) return;
      for (final e in targets) {
        final name = e.key.split('/').last;
        try {
          await File('${d.path}/$name').writeAsBytes(e.value);
          counts[sub] = (counts[sub] ?? 0) + 1;
        } catch (_) {}
      }
    }

    await put(({bool create = false}) => sm.photosDir(create: create), 'photos');
    await put(({bool create = false}) => sm.cardsDir(create: create), 'cards');
    await put(({bool create = false}) => sm.bgDir(create: create), 'backgrounds');
    await put(({bool create = false}) => sm.fontsDir(create: create), 'fonts');
    return counts;
  }
}

class BackupContent {
  BackupContent({
    required this.data,
    required this.assets,
    required this.isLegacyJson,
  });

  final Map<String, dynamic> data;
  final Map<String, List<int>> assets;

  /// 老格式（单个 JSON，没有图片资源）
  final bool isLegacyJson;

  int get assetCount => assets.length;
}
