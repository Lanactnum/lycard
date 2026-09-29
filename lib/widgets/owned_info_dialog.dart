import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../data/rate_source.dart';
import '../state/app_state.dart';
import '../l10n/l10n.dart';

/// 联网取「1 [currency] = ? CNY」（失败返回 null）。
///
/// [at] 传入库时间时，会去取**那一天**的历史汇率（frankfurter，国内直连可达）；
/// 取不到（或该币种 ECB 没收录，比如 TWD）再退回"最新汇率"（er-api）。
Future<double?> fetchRateToCny(String currency, {DateTime? at}) async {
  if (currency == 'CNY') return 1.0;

  final historical = await RateSource.fetch(currency, 'CNY', date: at);
  if (historical != null && historical > 0) return historical;

  // 兜底：最新汇率
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client
        .getUrl(Uri.parse('https://open.er-api.com/v6/latest/CNY'));
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final body = await res.transform(const Utf8Decoder()).join();
    final j = jsonDecode(body) as Map<String, dynamic>;
    final rates = j['rates'] as Map<String, dynamic>?;
    final v = (rates?[currency] as num?)?.toDouble();
    if (v == null || v == 0) return null;
    return 1 / v;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// 编辑一张卡的入库信息：金额 / 币种 / 入库时间 / 汇率 / 备注
Future<void> showOwnedInfoDialog(
  BuildContext context,
  AppState state,
  String code,
) async {
  final info = state.infoOf(code)?.copy() ?? OwnedInfo();
  final priceCtrl = TextEditingController(
      text: info.price == null ? '' : _trim(info.price!));
  final rateCtrl = TextEditingController(
      text: info.rate == null ? '' : _trim(info.rate!));
  final noteCtrl = TextEditingController(text: info.note);
  var currency = info.currency;
  var acquired = info.acquiredAt;
  var fetching = false;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(tr('入库信息 · {0}', [code]), style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                          labelText: tr('入库金额'), hintText: tr('购入价格')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: currency,
                    items: [
                      for (final c in kCurrencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setLocal(() => currency = v ?? 'JPY'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: rateCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: tr('汇率（1 {0} = ? CNY）', [currency]),
                        hintText: tr('留空用默认 {0}', [kDefaultRates[currency] ?? 1]),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: acquired == null
                        ? tr('联网获取当前汇率')
                        : '联网获取入库当天（${acquired!.year}-'
                            '${acquired!.month.toString().padLeft(2, '0')}-'
                            '${acquired!.day.toString().padLeft(2, '0')}）的汇率',
                    icon: fetching
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.cloud_download_outlined),
                    onPressed: fetching
                        ? null
                        : () async {
                            setLocal(() => fetching = true);
                            // 有入库时间就按那天取（"入库时汇率"）
                            final r = await fetchRateToCny(currency,
                                at: acquired);
                            setLocal(() {
                              fetching = false;
                              if (r != null) rateCtrl.text = _trim(r);
                            });
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                content: Text(r == null
                                    ? tr('获取汇率失败，先使用默认值')
                                    : tr('已获取：1 {0} = {1} CNY', [currency, _trim(r)])),
                                duration: const Duration(seconds: 2),
                              ));
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Builder(builder: (ctx2) {
                final a = acquired;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a == null
                      ? tr('入库时间：未填写（按默认汇率计算）')
                      : tr('入库时间：{0}', [_date(a)])),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: ctx2,
                            initialDate: acquired ?? DateTime.now(),
                            firstDate: DateTime(2005),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setLocal(() => acquired = picked);
                        },
                        child: Text(tr('选日期')),
                      ),
                      if (acquired != null)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setLocal(() => acquired = null),
                        ),
                    ],
                  ),
                );
              }),
              TextField(
                controller: noteCtrl,
                decoration: InputDecoration(
                    labelText: tr('备注'), hintText: tr('购买地点/品相等')),
              ),
              const SizedBox(height: 8),
              Text(
                tr('折合人民币：{0}', [_cny(priceCtrl.text, rateCtrl.text, currency)]),
                style: TextStyle(
                    fontSize: 12, color: Theme.of(ctx).colorScheme.primary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              state.setOwnedInfo(code, null);
              Navigator.pop(ctx);
            },
            child: Text(tr('清除')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () {
              final p = double.tryParse(priceCtrl.text.trim());
              final r = double.tryParse(rateCtrl.text.trim());
              if (p == null && r == null && noteCtrl.text.isEmpty) {
                state.setOwnedInfo(code, null);
              } else {
                state.setOwnedInfo(
                  code,
                  OwnedInfo(
                    price: p,
                    currency: currency,
                    rate: r,
                    acquiredAt: acquired,
                    note: noteCtrl.text.trim(),
                  ),
                );
              }
              Navigator.pop(ctx);
            },
            child: Text(tr('保存')),
          ),
        ],
      ),
    ),
  );

  priceCtrl.dispose();
  rateCtrl.dispose();
  noteCtrl.dispose();
}

String _trim(double v) {
  final s = v.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _cny(String price, String rate, String currency) {
  final p = double.tryParse(price.trim());
  if (p == null) return '未填金额';
  final r = double.tryParse(rate.trim()) ?? kDefaultRates[currency] ?? 1.0;
  return '¥${(p * r).toStringAsFixed(2)}';
}
