import 'dart:convert';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'dart:ffi' show Abi;
import 'dart:io' show Directory, File, FileMode, IOSink, Platform;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const kUpdateRepository = 'Lanactnum/lycard-updates';
const kUpdateApi = 'https://api.github.com/repos/$kUpdateRepository/releases/latest';

class AppUpdate {
  const AppUpdate({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.apkName,
    required this.downloadSize,
    required this.notes,
    required this.publishedAt,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final Uri? downloadUrl;

  /// 安装包文件名（取自 Release 附件名，不是从下载地址里猜的 ——
  /// 地址可能是 CDN 的短名，猜出来的名字会不对）
  final String apkName;

  /// 安装包字节数（GitHub 给的）。用来判断「下完了没」和算进度。
  final int? downloadSize;
  final String notes;
  final DateTime? publishedAt;

  bool get isNewer => _compareVersions(latestVersion, currentVersion) > 0;

}

class UpdateCheckResult {
  const UpdateCheckResult({this.update, this.message});

  final AppUpdate? update;
  final String? message;

  bool get hasUpdate => update?.isNewer == true;
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  /// [client] / [abiToken] 只给测试用：默认走真网络、按本机架构挑包。
  Future<UpdateCheckResult> check({http.Client? client, String? abiToken}) async {
    final info = await PackageInfo.fromPlatform();
    final c = client ?? http.Client();
    final response = await c
        .get(
          Uri.parse(kUpdateApi),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (client == null) c.close();
    if (response.statusCode == 404) {
      return const UpdateCheckResult(message: '暂无可用更新');
    }
    if (response.statusCode != 200) {
      throw Exception('GitHub HTTP ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = '${json['tag_name'] ?? ''}'.replaceFirst(RegExp(r'^v'), '');
    final assets = (json['assets'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();
    final apk = pickApk(assets, abiToken: abiToken);
    final published = DateTime.tryParse('${json['published_at'] ?? ''}');
    final update = AppUpdate(
      currentVersion: info.version,
      latestVersion: tag,
      releaseUrl: Uri.parse('${json['html_url']}'),
      downloadUrl: apk['browser_download_url'] == null
          ? null
          : Uri.parse('${apk['browser_download_url']}'),
      apkName: '${apk['name'] ?? ''}',
      downloadSize: apk['size'] is int ? apk['size'] as int : null,
      notes: '${json['body'] ?? ''}'.trim(),
      publishedAt: published,
    );
    return UpdateCheckResult(update: update);
  }
}

/// 从 Release 附件里挑一个**本机装得上**的 APK。
///
/// 不能只取「第一个 .apk」：同一个版本可能同时挂 arm64 版和全架构版，而 GitHub 是
/// 按**文件名排序**返回附件的 —— 排在前面的未必适合当前设备（实测
/// `...-universal.apk` 会排在 `....apk` 前面，因为 `-`(0x2D) < `.`(0x2E)）。
/// 所以先按本机架构找带对应标记的包，找不到再退回第一个 .apk。
///
/// [abiToken] 只给测试用；默认按当前设备架构推断。
Map<String, dynamic> pickApk(
  Iterable<Map<String, dynamic>> assets, {
  String? abiToken,
  bool defaultToDeviceAbi = true,
}) {
  final apks = assets
      .where((a) => '${a['name']}'.toLowerCase().endsWith('.apk'))
      .toList();
  if (apks.isEmpty) return <String, dynamic>{};
  final want = abiToken ?? (defaultToDeviceAbi ? _abiToken() : null);
  if (want != null) {
    for (final a in apks) {
      if ('${a['name']}'.toLowerCase().contains(want)) return a;
    }
  }
  return apks.first;
}

/// 本机合适的包名标记；非 Android 或架构取不到时返回 null（那就用第一个）。
String? _abiToken() {
  if (!Platform.isAndroid) return null;
  try {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'arm64';
    if (abi == Abi.androidArm || abi == Abi.androidX64) return 'universal';
  } catch (_) {
    // 取不到就当没这回事，退回第一个 .apk
  }
  return null;
}

int _compareVersions(String a, String b) {
  final aa = _parts(a);
  final bb = _parts(b);
  for (var i = 0; i < (aa.length > bb.length ? aa.length : bb.length); i++) {
    final x = i < aa.length ? aa[i] : 0;
    final y = i < bb.length ? bb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

List<int> _parts(String value) => value
    .replaceFirst(RegExp(r'^v'), '')
    .split(RegExp(r'[.+-]'))
    .map((s) => int.tryParse(s) ?? 0)
    .toList();

/// 一次下载的进度快照。
class DownloadProgress {
  const DownloadProgress({
    required this.received,
    required this.total,
    required this.resumedFrom,
  });

  /// 文件当前总字节（含续传前已有的那一段）。
  final int received;

  /// 服务端报的总大小；0 = 没报（进度条只能转圈）。
  final int total;

  /// 这次的续传起点（0 = 从头下的）。
  final int resumedFrom;

  double? get fraction =>
      total > 0 ? (received / total).clamp(0.0, 1.0).toDouble() : null;

  bool get isComplete => total > 0 && received >= total;
}

/// 更新包放哪：`/sdcard/Android/data/<包名>/files/update/`。
///
/// 跟卡图数据包同一个大目录下面 —— 卸载 App 会一起清掉，也不会跑进相册或「下载」。
Future<Directory> updateDir() async {
  final base =
      await getExternalStorageDirectory() ?? await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/update');
  if (!dir.existsSync()) await dir.create(recursive: true);
  return dir;
}

/// **应用内**下载安装包，支持**断点续传**：目标文件已经有一截就从断点接着下。
///
/// - 返回 `null` = 用户取消（已下的那部分**保留在磁盘上**，下次接着下）
/// - 服务端不支持续传（回了 200 而不是 206）时自动从头下，不会把内容拼坏
/// - 下完校验字节数对不对，短了直接抛错，免得拿半个包装
Future<File?> downloadApk({
  required Uri url,
  required File target,
  void Function(DownloadProgress progress)? onProgress,
  bool Function()? isCancelled,
  http.Client? client,
}) async {
  final ownClient = client == null;
  final c = client ?? http.Client();
  IOSink? sink;
  try {
    await target.parent.create(recursive: true);
    var startAt = target.existsSync() ? target.lengthSync() : 0;
    final req = http.Request('GET', url)
      ..headers['Accept'] = 'application/octet-stream';
    if (startAt > 0) req.headers['Range'] = 'bytes=$startAt-';
    final res = await c.send(req);
    if (res.statusCode == 416) {
      // 服务端认为这段区间不存在 —— 当成已经下全了
      final p = DownloadProgress(
        received: startAt,
        total: startAt,
        resumedFrom: startAt,
      );
      onProgress?.call(p);
      return target;
    }
    if (res.statusCode != 200 && res.statusCode != 206) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final resumed = res.statusCode == 206 && startAt > 0;
    if (!resumed) startAt = 0;
    final total = startAt + (res.contentLength ?? 0);
    sink = target.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    var got = startAt;
    var lastTick = got;
    onProgress?.call(
      DownloadProgress(received: got, total: total, resumedFrom: startAt),
    );
    await for (final chunk in res.stream) {
      if (isCancelled?.call() == true) break;
      sink.add(chunk);
      got += chunk.length;
      // 每 256 KB 报一次进度，别把界面刷爆
      if (got - lastTick >= 1 << 18) {
        lastTick = got;
        onProgress?.call(
          DownloadProgress(received: got, total: total, resumedFrom: startAt),
        );
      }
    }
    await sink.flush();
    await sink.close();
    sink = null;
    onProgress?.call(
      DownloadProgress(received: got, total: total, resumedFrom: startAt),
    );
    if (isCancelled?.call() == true) return null;
    if (total > 0 && got < total) {
      throw Exception('只下到 $got/$total 字节');
    }
    return target;
  } finally {
    try {
      await sink?.close();
    } catch (_) {
      // 关不上就算了，文件已经在磁盘上
    }
    if (ownClient) c.close();
  }
}

/// 全局的「当前更新下载」。
///
/// 面板关了也接着下（进度存在这里），重开面板能接着看 —— 顺手也挡住了
/// 「面板关了又开、再点一次开始」把同一个文件写坏的情况。
class UpdateDownload {
  UpdateDownload._();
  static final UpdateDownload instance = UpdateDownload._();

  /// 最新进度（null = 还没开始过）
  final ValueNotifier<DownloadProgress?> progress =
      ValueNotifier<DownloadProgress?>(null);

  /// 是否正在下
  final ValueNotifier<bool> running = ValueNotifier<bool>(false);

  /// 下载速度（字节/秒）—— 拿两次进度回调的时间差算，刚开始时是 null
  final ValueNotifier<double?> speed = ValueNotifier<double?>(null);
  DateTime? _lastAt;
  int? _lastBytes;

  /// 出错信息（下次开始下载时清空）
  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  /// 当前下的是哪个文件
  File? target;

  bool _cancel = false;

  /// 开始 / 继续下载。[expectedSize] 是 GitHub 报的包大小（拿来判断下完了没）。
  Future<File?> start({
    required Uri url,
    required File file,
    int? expectedSize,
  }) async {
    if (running.value) return null;
    target = file;
    _cancel = false;
    error.value = null;
    speed.value = null;
    _lastAt = null;
    _lastBytes = null;
    final have = file.existsSync() ? file.lengthSync() : 0;
    progress.value = DownloadProgress(
      received: have,
      total: expectedSize ?? 0,
      resumedFrom: 0,
    );
    running.value = true;
    try {
      final out = await downloadApk(
        url: url,
        target: file,
        isCancelled: () => _cancel,
        onProgress: (p) {
          final now = DateTime.now();
          if (_lastAt != null && _lastBytes != null) {
            final ms = now.difference(_lastAt!).inMilliseconds;
            // 太密的回调算出来的速度会乱跳，300ms 一次就够
            if (ms > 300) {
              speed.value = (p.received - _lastBytes!) * 1000 / ms;
              _lastAt = now;
              _lastBytes = p.received;
            }
          } else {
            _lastAt = now;
            _lastBytes = p.received;
          }
          progress.value = p;
        },
      );
      return out;
    } catch (e) {
      error.value = '$e';
      return null;
    } finally {
      running.value = false;
    }
  }

  /// 暂停（已下的部分保留，下次接着下）
  void cancel() {
    if (running.value) _cancel = true;
  }
}
