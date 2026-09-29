import 'dart:convert';

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
    final apk = assets.firstWhere(
      (a) => '${a['name']}'.toLowerCase().endsWith('.apk'),
      orElse: () => <String, dynamic>{},
    );
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
