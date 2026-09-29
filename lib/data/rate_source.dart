import 'dart:convert';
import 'dart:io';

/// 联网汇率源。
///
/// 用 frankfurter.dev：免费、无需 API key、**支持历史日期** ——
/// 正好满足"按入库时间取当时的汇率"。
/// 国内直连可达（已实测），失败就返回 null，让用户手填。
class RateSource {
  RateSource._();

  static const _host = 'api.frankfurter.dev';

  /// 取汇率：[from] → [to]。
  ///
  /// [date] 为空或晚于今天 → 取最新；否则取那一天的收盘汇率（入库时汇率）。
  /// 返回 null 表示取不到（网络不通 / 该日期没有数据 / 币种不支持）。
  static Future<double?> fetch(
    String from,
    String to, {
    DateTime? date,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final now = DateTime.now();
      final d = (date == null || date.isAfter(now)) ? null : date;
      final path = d == null
          ? '/v1/latest'
          : '/v1/${d.year.toString().padLeft(4, '0')}'
              '-${d.month.toString().padLeft(2, '0')}'
              '-${d.day.toString().padLeft(2, '0')}';
      final uri = Uri.https(_host, path, {'base': from, 'symbols': to});
      final res = await (await client.getUrl(uri)).close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final v = (j['rates'] as Map<String, dynamic>?)?[to];
      return v is num ? v.toDouble() : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
