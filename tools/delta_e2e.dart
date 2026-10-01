// 差分更新的**端到端验证**：拿真实补丁 + 真实旧包，看能不能还原出真正的新包。
//
// 这不是模拟：用的是 tools/make_delta.py 对 dist/lycard-0.85.3-arm64.apk 与
// dist/lycard-0.85.4-arm64.apk 生成的补丁，还原结果要和新包 **SHA256 逐字节相同**。
//
// 跑法（在项目根目录）：
//     dart run tools/delta_e2e.dart [补丁路径]
//
// 缺文件时会直接说缺什么，不算失败。

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:lycee_app/services/delta_patch.dart';

Future<String> shaHex(File f) async {
  final d = await sha256.bind(f.openRead()).first;
  return '$d';
}

void log(Object? s) => stdout.writeln(s);

String mb(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MB';

/// 用法：dart run tools/delta_e2e.dart [旧包] [新包] [补丁]
/// 不带参数就用 0.85.3 → 0.85.4 那对（历史验证用）。
Future<void> main(List<String> args) async {
  final root = Directory.current;
  final oldApk = File(args.isNotEmpty
      ? args[0]
      : '${root.path}/dist/lycard-0.85.3-arm64.apk');
  final newApk = File(args.length > 1
      ? args[1]
      : '${root.path}/dist/lycard-0.85.4-arm64.apk');
  final patch = File(args.length > 2
      ? args[2]
      : 'C:/Users/Administrator/AppData/Local/hermes/profiles/1/cache/scratch/d0854.lycpatch');
  final out = File('${root.path}/dist/__delta_out.apk');

  final files = <File>[oldApk, newApk, patch];
  for (final f in files) {
    if (!f.existsSync()) {
      log('缺文件，跳过：${f.path}');
      return;
    }
  }

  final oldLen = oldApk.lengthSync();
  final newLen = newApk.lengthSync();
  final patchLen = patch.lengthSync();
  log('旧包   $oldLen 字节（${mb(oldLen)}）');
  log('新包   $newLen 字节（${mb(newLen)}）');
  log('补丁   $patchLen 字节（${mb(patchLen)}）');
  log('补丁 / 新包 = ${(patchLen / newLen * 100).toStringAsFixed(2)}%');

  final info = await DeltaPatch.readInfo(patch);
  if (info == null) {
    stderr.writeln('✗ 补丁头读不出来');
    exitCode = 1;
    return;
  }
  log('补丁声明：${info.fromSize} → ${info.toSize}');
  log('  期望哈希 ${info.toSha256}');

  final t0 = DateTime.now();
  var lastPct = -20;
  await DeltaPatch.apply(
    oldApk: oldApk,
    patch: patch,
    out: out,
    onProgress: (int done, int total) {
      final pct = done * 100 ~/ total;
      if (pct >= lastPct + 20) {
        lastPct = pct;
        log('  $pct%');
      }
    },
  );
  final ms = DateTime.now().difference(t0).inMilliseconds;
  log('应用完成，耗时 ${ms}ms（${(ms / 1000).toStringAsFixed(1)}s）');

  final a = await shaHex(newApk);
  final b = await shaHex(out);
  log('新包     $a');
  log('还原结果 $b');
  if (a == b) {
    log('✓ 逐字节一致 —— 差分还原成功');
  } else {
    stderr.writeln('✗ 不一致！');
    exitCode = 1;
  }
  if (out.existsSync()) await out.delete();
  log('（已删掉还原出来的临时文件）');
}
