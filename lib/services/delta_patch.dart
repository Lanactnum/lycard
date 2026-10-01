import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 差分更新补丁的应用器（补丁由 `tools/make_delta.py` 生成）。
///
/// 为什么值得做：APK 里 86% 的字节是内置卡图，而卡图在版本之间**从不变化**。
/// 所以每次更新只需要下「变化的那一点点」，而不是 573 MB 整包。
/// 实测 0.85.3 → 0.85.4：整包 573 MB，补丁 **12.6 MB**。
///
/// 补丁格式：
/// ```
/// [0..8]    magic  b"LYCDELTA1"
/// [9..12]   旧包大小   uint32 小端
/// [13..16]  新包大小   uint32 小端
/// [17..48]  新包 SHA256（32 字节）
/// [49..]    指令流（gzip）
/// ```
/// 指令流：`varint 0` 结束 / `varint 1` + 旧包偏移 + 长度（复制） /
/// `varint 2` + 长度 + 内容（新数据）。
///
/// 全程流式：内存只要几 MB，573 MB 的包也不会撑爆。
class DeltaPatch {
  DeltaPatch._();

  static const List<int> magic = <int>[
    0x4C, 0x59, 0x43, 0x44, 0x45, 0x4C, 0x54, 0x41, 0x31, // "LYCDELTA1"
  ];
  static const int headerSize = 49;
  static const int _chunk = 4 << 20;

  /// 只读补丁头（不应用）。用来判断这个补丁对不对得上本机的旧包。
  static Future<DeltaPatchInfo?> readInfo(File patch) async {
    RandomAccessFile? raf;
    try {
      if (await patch.length() < headerSize) return null;
      raf = await patch.open();
      final head = await raf.read(headerSize);
      if (head.length < headerSize) return null;
      for (var i = 0; i < magic.length; i++) {
        if (head[i] != magic[i]) return null;
      }
      final bd = ByteData.sublistView(head);
      return DeltaPatchInfo(
        fromSize: bd.getUint32(9, Endian.little),
        toSize: bd.getUint32(13, Endian.little),
        toSha256: head
            .sublist(17, 49)
            .map((int b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      );
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// 把 [patch] 应用到 [oldApk] 上，写出 [out]。
  ///
  /// - 成功返回 true，并且**已经核对过**输出的字节数和 SHA256
  /// - 任何一步不对（旧包大小不符、指令流坏、哈希不符）都抛异常，
  ///   调用方应该**退回整包下载**，不要把半成品拿去安装
  /// - 取消时抛 [DeltaPatchCancelled]，并删掉写了一半的输出文件
  ///   （补丁本身留着，重新应用不用再下一遍）
  static Future<bool> apply({
    required File oldApk,
    required File patch,
    required File out,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final info = await readInfo(patch);
    if (info == null) throw const FormatException('补丁文件头不对');

    final oldLen = await oldApk.length();
    if (oldLen != info.fromSize) {
      throw StateError('本机安装包大小 $oldLen 与补丁要求的 ${info.fromSize} 不符');
    }

    final src = await oldApk.open();
    final sink = out.openWrite();
    final reader = _InflatedReader(
      gzip.decoder.bind(patch.openRead(headerSize)),
    );
    var written = 0;
    var ok = false;
    try {
      while (true) {
        if (isCancelled?.call() == true) throw const DeltaPatchCancelled();
        final op = await reader.readVarint();
        if (op == _opEnd) break;
        if (op == _opCopy) {
          final oldOff = await reader.readVarint();
          final len = await reader.readVarint();
          if (oldOff < 0 || len < 0 || oldOff + len > info.fromSize) {
            throw const FormatException('复制指令越界');
          }
          await src.setPosition(oldOff);
          var left = len;
          while (left > 0) {
            if (isCancelled?.call() == true) throw const DeltaPatchCancelled();
            final n = left > _chunk ? _chunk : left;
            final b = await src.read(n);
            if (b.length != n) throw const FormatException('旧包读不够字节');
            sink.add(b);
            left -= n;
            written += n;
            onProgress?.call(written, info.toSize);
          }
        } else if (op == _opLiteral) {
          final len = await reader.readVarint();
          if (len < 0) throw const FormatException('新内容长度非法');
          var left = len;
          while (left > 0) {
            if (isCancelled?.call() == true) throw const DeltaPatchCancelled();
            final n = left > _chunk ? _chunk : left;
            sink.add(await reader.take(n));
            left -= n;
            written += n;
            onProgress?.call(written, info.toSize);
          }
        } else {
          throw FormatException('未知指令 $op');
        }
      }
      await sink.flush();
      ok = true;
    } finally {
      try {
        await sink.close();
      } catch (_) {}
      try {
        await src.close();
      } catch (_) {}
      try {
        await reader.close();
      } catch (_) {}
      if (!ok && await out.exists()) {
        try {
          await out.delete();
        } catch (_) {}
      }
    }

    if (written != info.toSize) {
      throw StateError('写出 $written 字节，应该是 ${info.toSize}');
    }
    final digest = await sha256.bind(out.openRead()).first;
    if ('$digest' != info.toSha256) {
      throw StateError('应用完的哈希不符：$digest != ${info.toSha256}');
    }
    return true;
  }

  static const int _opEnd = 0;
  static const int _opCopy = 1;
  static const int _opLiteral = 2;
}

class DeltaPatchInfo {
  const DeltaPatchInfo({
    required this.fromSize,
    required this.toSize,
    required this.toSha256,
  });

  /// 旧包（本机已装的那个）应该有多大
  final int fromSize;

  /// 应用出来的新包有多大
  final int toSize;

  /// 应用出来的新包应该是什么哈希（对不上就别装）
  final String toSha256;
}

/// 用户在应用补丁的过程中取消了
class DeltaPatchCancelled implements Exception {
  const DeltaPatchCancelled();
  @override
  String toString() => '已取消';
}

/// 把 gzip 解出来的指令流当成一个可顺序读取的字节源
class _InflatedReader {
  _InflatedReader(Stream<List<int>> stream)
      : _it = StreamIterator<List<int>>(stream);

  final StreamIterator<List<int>> _it;
  List<int> _buf = const <int>[];
  int _pos = 0;

  Future<bool> _fill() async {
    while (_pos >= _buf.length) {
      if (!await _it.moveNext()) return false;
      _buf = _it.current;
      _pos = 0;
      if (_buf.isEmpty) continue;
    }
    return true;
  }

  Future<int> _byte() async {
    if (!await _fill()) throw const FormatException('指令流提前结束');
    return _buf[_pos++];
  }

  Future<int> readVarint() async {
    var shift = 0;
    var value = 0;
    while (true) {
      final b = await _byte();
      value |= (b & 0x7F) << shift;
      if ((b & 0x80) == 0) return value;
      shift += 7;
      if (shift > 63) throw const FormatException('varint 过长');
    }
  }

  Future<Uint8List> take(int n) async {
    final out = Uint8List(n);
    var got = 0;
    while (got < n) {
      if (!await _fill()) throw const FormatException('指令流提前结束');
      final avail = _buf.length - _pos;
      final need = n - got;
      final use = avail < need ? avail : need;
      out.setRange(got, got + use, _buf, _pos);
      _pos += use;
      got += use;
    }
    return out;
  }

  Future<void> close() async {
    try {
      await _it.cancel();
    } catch (_) {}
  }
}
