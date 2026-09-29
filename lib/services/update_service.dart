import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const kUpdateRepository = 'Lanactnum/lycard-updates';
const kUpdateApi = 'https://api.github.com/repos/$kUpdateRepository/releases/latest';

class AppUpdate {
  const AppUpdate({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.downloadUrl,
    required this.notes,
    required this.publishedAt,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUrl;
  final Uri? downloadUrl;
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

  Future<UpdateCheckResult> check() async {
    final info = await PackageInfo.fromPlatform();
    final response = await http.get(
      Uri.parse(kUpdateApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    ).timeout(const Duration(seconds: 15));
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
    final apk = _pickApk(assets);
    final published = DateTime.tryParse('${json['published_at'] ?? ''}');
    final update = AppUpdate(
      currentVersion: info.version,
      latestVersion: tag,
      releaseUrl: Uri.parse('${json['html_url']}'),
      downloadUrl: apk['browser_download_url'] == null
          ? null
          : Uri.parse('${apk['browser_download_url']}'),
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
Map<String, dynamic> _pickApk(Iterable<Map<String, dynamic>> assets) {
  final apks = assets
      .where((a) => '${a['name']}'.toLowerCase().endsWith('.apk'))
      .toList();
  if (apks.isEmpty) return <String, dynamic>{};
  final want = _abiToken();
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
