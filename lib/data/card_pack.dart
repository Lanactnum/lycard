import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 卡图数据包读取器。
///
/// **单文件格式** `lycee_cards.pack`：
/// ```
/// [0..7]      magic  b"LYCPACK1"
/// [8..11]     索引长度 N（uint32 小端）
/// [12..12+N)  索引 JSON：{"卡号": [相对偏移, 字节数], ...}
/// [12+N..]    所有 PNG 原图首尾拼接
/// ```
/// App 只做 seek + read，不解压、不复制，读一张 372x520 原图约 1 毫秒。
///
/// 同时兼容早期的两文件布局：`lycee_cards.dat` + `lycee_cards.index.json`。
class CardPack {
  CardPack._();
  static final CardPack instance = CardPack._();

  static const String packName = 'lycee_cards.pack';
  static const String datName = 'lycee_cards.dat';
  static const String idxName = 'lycee_cards.index.json';
  static const List<int> magic = [0x4C, 0x59, 0x43, 0x50, 0x41, 0x43, 0x4B, 0x31]; // LYCPACK1

  RandomAccessFile? _raf;
  Map<String, List<int>> _index = const {};
  int _base = 0; // 图片数据的起点
  String? _path;
  int _hits = 0;
  int _miss = 0;

  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  static const int _cacheMax = 160;

  /// 文件句柄是共用的，setPosition + read 是两步，
  /// 多个图同时加载会互相插队读串数据（症状：只有第一张显示得出来）。
  /// 所以读操作必须串行化。
  ///
  /// [_serializeReads] 关掉就能复现那个 bug，测试里用它做对照。
  static const bool _serializeReads = true;

  Future<void> _ioChain = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    if (!_serializeReads) return action();
    final prev = _ioChain;
    final gate = Completer<void>();
    _ioChain = gate.future;
    return prev.then((_) => action()).whenComplete(gate.complete);
  }

  bool get ready => _raf != null && _index.isNotEmpty;
  int get count => _index.length;
  String? get path => _path;
  String? get dir => _path == null ? null : File(_path!).parent.path;
  int get hits => _hits;
  int get miss => _miss;

  /// App 自己的外部专属目录（不需要任何权限）
  Future<String?> targetDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext.path;
    } catch (_) {}
    return '/sdcard/Android/data/com.lycard.app/files';
  }

  /// 可能放数据包的地方（按优先级）
  Future<List<String>> candidateDirs() async {
    final list = <String>[];
    final t = await targetDir();
    if (t != null) {
      list.add(t);
      list.add('$t/pack');
    }
    list.add('/sdcard/Android/data/com.lycard.app/files');
    list.add('/sdcard/Download');
    list.add('/sdcard/Download/lycee_pack');
    try {
      final doc = await getApplicationDocumentsDirectory();
      list.add(doc.path);
      list.add('${doc.path}/pack');
    } catch (_) {}
    return list;
  }

  Future<bool> autoOpen() async {
    for (final d in await candidateDirs()) {
      if (await open(d)) return true;
    }
    return false;
  }

  /// 在指定目录里找数据包并打开
  Future<bool> open(String dirPath) async {
    await close();
    // 1) 单文件 .pack
    if (await _openPack(File('$dirPath/$packName'))) return true;
    // 2) 老的两文件布局
    if (await _openPair(File('$dirPath/$datName'), File('$dirPath/$idxName'))) {
      return true;
    }
    return false;
  }

  /// 直接打开某个具体文件（用户从文件管理器选的）
  Future<bool> openFile(String filePath) async {
    await close();
    final f = File(filePath);
    if (filePath.toLowerCase().endsWith('.json')) return false;
    if (await _openPack(f)) return true;
    // 选的是 .dat，就找同目录的 index.json
    final dir = f.parent.path;
    return _openPair(f, File('$dir/$idxName'));
  }

  Future<bool> _openPack(File f) async {
    try {
      if (!await f.exists() || await f.length() < 64) return false;
      final raf = await f.open(mode: FileMode.read);
      final head = await raf.read(12);
      if (head.length < 12) {
        await raf.close();
        return false;
      }
      for (var i = 0; i < 8; i++) {
        if (head[i] != magic[i]) {
          await raf.close();
          return false;
        }
      }
      final n = ByteData.sublistView(head).getUint32(8, Endian.little);
      if (n <= 0 || n > 64 * 1024 * 1024) {
        await raf.close();
        return false;
      }
      final idxBytes = await raf.read(n);
      final map = _decodeIndex(jsonDecode(utf8.decode(idxBytes)));
      if (map.isEmpty) {
        await raf.close();
        return false;
      }
      _raf = raf;
      _index = map;
      _base = 12 + n;
      _path = f.path;
      _cache.clear();
      debugPrint('卡图数据包已挂载：${map.length} 张原图 <- ${f.path}');
      return true;
    } catch (e) {
      debugPrint('打开 .pack 失败: $e');
      return false;
    }
  }

  Future<bool> _openPair(File dat, File idx) async {
    try {
      if (!await dat.exists() || !await idx.exists()) return false;
      final map = _decodeIndex(jsonDecode(await idx.readAsString()));
      if (map.isEmpty) return false;
      _raf = await dat.open(mode: FileMode.read);
      _index = map;
      _base = 0;
      _path = dat.path;
      _cache.clear();
      return true;
    } catch (e) {
      debugPrint('打开数据包失败: $e');
      return false;
    }
  }

  Map<String, List<int>> _decodeIndex(dynamic raw) {
    final map = <String, List<int>>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is List && v.length >= 2) {
          map['$k'] = [(v[0] as num).toInt(), (v[1] as num).toInt()];
        }
      });
    }
    return map;
  }

  Future<void> close() async {
    try {
      await _raf?.close();
    } catch (_) {}
    _raf = null;
    _index = const {};
    _base = 0;
    _path = null;
    _cache.clear();
  }

  bool has(String code) => _raf != null && _index.containsKey(code);

  /// 读一张卡图的原始字节
  Future<Uint8List?> bytes(String code) async {
    final raf = _raf;
    final ent = _index[code];
    if (raf == null || ent == null) {
      _miss++;
      return null;
    }
    final cached = _cache.remove(code);
    if (cached != null) {
      _cache[code] = cached; // 挪到队尾
      _hits++;
      return cached;
    }
    // 并发保护：定位 + 读取必须一口气做完
    return _locked(() async {
      // 排队期间可能已经被别的调用读进缓存了
      final again = _cache[code];
      if (again != null) {
        _hits++;
        return again;
      }
      final current = _raf;
      if (current == null) {
        _miss++;
        return null;
      }
      try {
        await current.setPosition(_base + ent[0]);
        final data = await current.read(ent[1]);
        if (data.length != ent[1]) {
          debugPrint('读卡图长度不符 $code: ${data.length} != ${ent[1]}');
          _miss++;
          return null;
        }
        _cache[code] = data;
        if (_cache.length > _cacheMax) {
          _cache.remove(_cache.keys.first);
        }
        _hits++;
        return data;
      } catch (e) {
        debugPrint('读卡图失败 $code: $e');
        _miss++;
        return null;
      }
    });
  }

  /// 把一个外部文件复制进 App 专属目录（供"从文件管理器导入"用）
  ///
  /// [onProgress] 回调 (已复制字节, 总字节)
  static Future<String> copyInto(
    String srcPath,
    String dstDir, {
    String? dstName,
    void Function(int done, int total)? onProgress,
  }) async {
    final src = File(srcPath);
    final name = dstName ?? src.uri.pathSegments.last;
    final dir = Directory(dstDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final dst = File('$dstDir/$name');
    // 已经在目标位置就直接返回
    if (src.absolute.path == dst.absolute.path) return dst.path;

    final total = await src.length();
    final raf = await dst.open(mode: FileMode.write);
    var done = 0;
    try {
      final stream = src.openRead();
      await for (final chunk in stream) {
        await raf.writeFrom(chunk);
        done += chunk.length;
        onProgress?.call(done, total);
      }
    } finally {
      await raf.close();
    }
    return dst.path;
  }
}
