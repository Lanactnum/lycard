import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';

/// 全量体检：效果文本里的卡名跳转
/// 不是只看一两张卡 —— 9952 张全跑一遍，统计漏的、错的、可疑的。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('全量：效果文本里的卡名识别 + 同名排序体检', () async {
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    final all = repo.all;

    var withEffect = 0;
    var hitsTotal = 0;
    var short2 = 0;        // 2 字卡名被认出来的次数
    var multiCand = 0;     // 同名多候选
    var sameSeriesTop = 0; // 多候选里"同系列排第一"的
    var multiNoSame = 0;   // 多候选但没有同系列可选的
    final missShort = <String, List<String>>{}; // 疑似漏掉的 2 字卡名
    final wrongTop = <String>[];

    // 全部卡名（含 2 字），拿来对照"哪些名字出现在效果里但没被识别"
    final nameToCodes = <String, List<String>>{};
    for (final c in all) {
      final zh = (c.nameZh ?? '').replaceAll(RegExp(r'[\s　・·]'), '');
      final jp = c.nameJp.replaceAll(RegExp(r'[\s　・·]'), '');
      for (final n in [zh, jp]) {
        if (n.length >= 2) (nameToCodes[n] ??= []).add(c.code);
      }
    }
    final shortNames = nameToCodes.keys.where((k) => k.length == 2).toSet();

    for (final c in all) {
      final text = c.effectJp ?? '';
      if (text.isEmpty) continue;
      withEffect++;

      final hits = repo.scanCardNames(text, selfSeries: c.series ?? '');
      for (final h in hits) {
        hitsTotal++;
        final label = text.substring(h.start, h.end);
        if (label.runes.length == 2) short2++;
        if (h.codes.length > 1) {
          multiCand++;
          final self = c.series ?? '';
          final top = repo.byCode(h.codes.first)?.series ?? '';
          // 和产品代码保持一致的三层判定
          String base(String x) =>
              x.replaceAll(RegExp(r'\s*\([A-Za-z]{2,6}\)\s*$'), '').trim();
          String brand(String x) =>
              RegExp(r'\(([A-Za-z]{2,6})\)').firstMatch(x)?.group(1) ?? '';
          String stem(String v) {
            var t = v.replaceAll(RegExp(r'\s*\([A-Za-z]{2,6}\)\s*$'), '');
            return t.replaceAll(RegExp(r'[\s　0-9．.]+$'), '').trim();
          }

          bool sameWork(String x, String y) {
            final a = stem(x), b = stem(y);
            if (a.length < 3 || b.length < 3) return false;
            var n = 0;
            final m = a.length < b.length ? a.length : b.length;
            while (n < m && a[n] == b[n]) {
              n++;
            }
            return n >= 4 && n >= (m * 0.6);
          }

          final same = self.isNotEmpty &&
              (top == self ||
                  base(top) == base(self) ||
                  sameWork(top, self));
          final sameBrand = brand(self).isNotEmpty && brand(self) == brand(top);
          if (same || sameBrand) {
            sameSeriesTop++;
          } else if (self.isNotEmpty) {
            multiNoSame++;
            if (wrongTop.length < 12) {
              wrongTop.add('${c.code}(效果提到 $label) → 首选 ${h.codes.first}'
                  '  [本卡 $self / 首选 $top]');
            }
          }
        }
      }

      // 漏检：效果里出现了 2 字卡名，却没被识别出来。
      // 但要注意 —— 如果这个名字只是某个更长卡名的一部分
      //（「エア」藏在「けもの道☆ガーリッシュスクエア」里），
      // 被最长匹配吃掉是**正确行为**，不能算漏。
      for (final n in shortNames) {
        if (n == c.nameJp || n == c.nameZh) continue;
        var idx = text.indexOf(n);
        var realMiss = false;
        while (idx >= 0) {
          final covered =
              hits.any((h) => h.start <= idx && h.end >= idx + n.length);
          if (!covered) {
            // 检查它是不是某个更长卡名的片段
            final inLonger = nameToCodes.keys.any((k) =>
                k.length > n.length && k.contains(n) && text.contains(k));
            // ⚠ 判定必须和产品代码同源：产品代码里，**片假名名字没占满整个
            // 片假名词组就不算引用**（「ナル」在「ペナルティ」里、「レオ」在
            // 「レオンハルト」里、「ソル」在「ソルティレージュ」里）。
            // 少了这一条，这里会把产品代码本来正确的行为误报成「漏掉」。
            bool kat(int r) => (r >= 0x30A1 && r <= 0x30FA) || r == 0x30FC;
            final nKat = n.runes.every(kat);
            var a = idx, b = idx + n.length;
            while (a > 0 && kat(text.codeUnitAt(a - 1))) {
              a--;
            }
            while (b < text.length && kat(text.codeUnitAt(b))) {
              b++;
            }
            final inKatWord = nKat && (b - a) > n.length;
            if (!inLonger && !inKatWord) {
              realMiss = true;
              break;
            }
          }
          idx = text.indexOf(n, idx + 1);
        }
        if (realMiss) {
          (missShort[n] ??= []).add(c.code);
        }
      }
    }

    debugPrint('===== 全量体检 =====');
    debugPrint('有日文效果的卡           : $withEffect');
    debugPrint('识别到的卡名引用总数     : $hitsTotal');
    debugPrint('其中 2 字卡名            : $short2');
    debugPrint('同名多候选的引用         : $multiCand');
    debugPrint('  ├ 首选是同系列/同会社  : $sameSeriesTop');
    debugPrint('  └ 首选不是同系/同会社  : $multiNoSame');
    debugPrint('疑似漏掉的 2 字卡名      : ${missShort.length} 种');

    final topMiss = (missShort.entries.toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length)))
        .take(15);
    for (final e in topMiss) {
      debugPrint('   「${e.key}」出现 ${e.value.length} 次未被识别'
          '  例: ${e.value.take(3).join(", ")}');
    }
    if (wrongTop.isNotEmpty) {
      debugPrint('首选可疑（<12 条抽样）:');
      for (final w in wrongTop) {
        debugPrint('   $w');
      }
    }

    expect(withEffect, greaterThan(9000));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
