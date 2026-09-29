import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/card_edit.dart';
import '../models/lycee_card.dart';
import 'card_filter.dart';
import 'search_index.dart';
import '../l10n/l10n.dart';
import '../services/data_update_service.dart';

/// 一个「作品（系列）」的汇总
class SeriesGroup {
  SeriesGroup(this.name, this.brand, this.cards);

  final String name; // 作品名，如 ニトロオリジン 1.0
  final String brand; // 会社/品牌标记，如 NIT
  final List<LyceeCard> cards;

  int get total => cards.length;
}

/// 卡池：一次性把卡表读进内存（约 1 万张），之后所有检索都在本地做。
class CardRepository {
  CardRepository._();
  static final CardRepository instance = CardRepository._();

  List<LyceeCard> _all = const [];
  Map<String, LyceeCard> _byCode = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;
  List<LyceeCard> get all => _all;
  int get count => _all.length;

  Future<void> load() async {
    if (_loaded) return;
    // 热更优先：App 目录里有热更数据就用热更的，否则回退内置资源。
    final upd = DataUpdateService.instance;
    try {
      final s = await upd.readString(
          'cards_app.json',
          () => rootBundle.loadString('assets/data/cards_app.json'));
      _ingest(s == null ? <LyceeCard>[] : LyceeCard.listFromJsonString(s));
    } catch (_) {
      _ingest(<LyceeCard>[]);
    }
    try {
      final s = await upd.readString('translations_zh.json',
          () => rootBundle.loadString('assets/data/translations_zh.json'));
      if (s != null) _applyTranslations(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      // 还没有翻译表也算正常
    }
    // 效果文本里引用过的名字 → 卡号（构建时预计算，见 tools/build_name_refs.py）。
    // 效果里常只写角色名（「御坂美琴」）而卡名是「超电磁炮 御坂美琴」，
    // 或者引用用日文汉字（「大藏遊星」）而卡名是简体（「大藏游星」），
    // 靠按 ／ 和空格拆分凑不齐，所以构建时算好直接查表。
    try {
      final s = await upd.readString('name_refs.json',
          () => rootBundle.loadString('assets/data/name_refs.json'));
      if (s != null) {
        final j = jsonDecode(s) as Map<String, dynamic>;
        _nameRefs = j.map((k, v) => MapEntry(k, (v as List).cast<String>()));
      }
    } catch (_) {
      _nameRefs = const {};
    }
    // name_refs 是最后加载的。名字索引是懒加载（第一次 scanCardNames 才建），
    // 万一在它加载前有人调过 scanCardNames，索引就已经建好且不含引用名了 ——
    // 这里主动作废一次，保证索引一定包含 name_refs。
    _nameIndex = null;
    _byFirst.clear();
    _loaded = true;
  }

  void _ingest(List<LyceeCard> list) {
    _base = list;
    _rebuildAll();
  }

  /// 官方原始数据（翻译后）
  List<LyceeCard> _base = const [];

  /// 用户自定义（覆盖字段 / 新建的卡）
  Map<String, CardOverride> _edits = const {};

  /// 搜索用的**小写缓存**。
  ///
  /// `query()` 会对每张卡的 5 个字段做 `toLowerCase()` —— 9952 张
  /// 就是每次搜索约 5 万次字符串分配。这些值只在卡池变化时才变，
  /// 预计算一次即可。
  Map<String, List<String>> _lower = const {};

  /// 「会社 → 作品」分组的缓存。
  ///
  /// 这个分组要遍历全部 9952 张卡、还要给每个会社的作品排序，
  /// 而它以前是在 MinePage 的 build() 里直接调的 —— 于是**每次重建**
  /// （包括在别的 tab 打字导致的 AppState 通知）都要重算一遍。
  /// 卡池只在 setEdits 时变，缓存起来即可。
  Map<String, List<SeriesGroup>>? _brandSeriesCache;

  /// 设置用户自定义并立刻重建索引
  void setEdits(Map<String, CardOverride> edits) {
    _edits = Map<String, CardOverride>.from(edits);
    _rebuildAll();
  }

  /// 有没有被用户改过
  bool isEdited(String code) => _edits.containsKey(code);

  /// 这张卡的自定义（没有就 null）
  CardOverride? editOf(String code) => _edits[code];

  /// 把所有自定义套到原始数据上，重建 _all / _byCode
  /// 重建小写缓存：每张卡存 [code, nameJp, nameZh, effectZh, effectJp]
  void _rebuildLower() {
    final m = <String, List<String>>{};
    for (final c in _all) {
      m[c.code] = [
        c.code.toLowerCase(),
        c.nameJp.toLowerCase(),
        (c.nameZh ?? '').toLowerCase(),
        (c.effectZh ?? '').toLowerCase(),
        (c.effectJp ?? '').toLowerCase(),
      ];
    }
    _lower = m;
  }

  void _rebuildAll() {
    _brandSeriesCache = null; // 卡池变了，分组缓存作废
    final out = <LyceeCard>[];
    for (final c in _base) {
      final e = _edits[c.code];
      out.add(e == null ? c : _applied(c, e));
    }
    // 用户新建的卡
    for (final e in _edits.values) {
      if (!e.isNew) continue;
      if (out.any((c) => c.code == e.code)) continue;
      out.add(_applied(_blank(e.code), e));
    }
    _all = out;
    _byCode = {for (final c in out) c.code: c};
    // ⚠ 必须在 _all 赋值**之后**：小写缓存是照着 _all 建的，
    // 放前面会缓存到旧数据（首次加载时就是空）。
    _rebuildLower();
    // 名字索引依赖 _all（和 _nameRefs 里的系列），卡池一变就得重建 ——
    // 否则用户改了卡名 / 新建了卡，效果里的引用还按旧名字识别。
    _nameIndex = null;
    _byFirst.clear();
  }

  static LyceeCard _blank(String code) =>
      LyceeCard(code: code, nameJp: code, nameZh: code);

  static LyceeCard _applied(LyceeCard c, CardOverride e) => c.copyWith(
        nameJp: e.nameJp,
        nameZh: e.nameZh,
        effectZh: e.effectZh,
        color: e.color,
        cost: e.cost,
        ex: e.ex,
        ap: e.ap,
        dp: e.dp,
        sp: e.sp,
        dmg: e.dmg,
        kind: e.kind,
        cardType: e.cardType,
        series: e.series,
        illustrator: e.illust,
        rarity: e.rarity,
      );

  /// 取第一个"有内容"的字符串。
  ///
  /// 专门用来替代 `a ?? b`：那个只对 null 兜底，遇到空串会原样返回，
  /// 于是界面上什么都不显示。译文表和卡表两份数据来源不一致时
  /// （一边写 null、一边写 ''）就会踩到。
  static String? _firstNonEmpty(List<String?> xs) {
    for (final x in xs) {
      if (x != null && x.trim().isNotEmpty) return x;
    }
    return null;
  }

  void _applyTranslations(Map<String, dynamic> map) {
    final out = <LyceeCard>[];
    for (final c in _all) {
      final t = map[c.code];
      if (t is Map) {
        out.add(LyceeCard(
          code: c.code,
          nameJp: c.nameJp,
          // ⚠ 不能用 `??` 兜底：`??` 只对 null 生效，数据里出现**空串**
          // 时会原样采用，结果是卡详情里「效果」栏一片空白、看着像汉化丢了
          // （实际数据没问题）。取第一个非空的。
          nameZh: _firstNonEmpty([t['name'] as String?, c.nameZh]),
          effectZh: _firstNonEmpty([t['effect'] as String?, c.effectZh]),
          effectJp: c.effectJp,
          color: c.color,
          cost: c.cost,
          ex: c.ex,
          ap: c.ap,
          dp: c.dp,
          sp: c.sp,
          dmg: c.dmg,
          cardType: c.cardType,
          kind: c.kind,
          limit: c.limit,
          series: c.series,
          illustrator: c.illustrator,
          rarity: c.rarity,
          releaseInfo: c.releaseInfo,
          titleJp: c.titleJp,
          isLeader: c.isLeader,
          deckRestriction: c.deckRestriction,
        ));
      } else {
        out.add(c);
      }
    }
    _ingest(out);
  }

  LyceeCard? byCode(String code) => _byCode[code];

  /// 快速检索：卡号 / 中文名 / 日文名 / 效果文本
  List<LyceeCard> search(String q, {int limit = 120}) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return const [];
    final out = <LyceeCard>[];
    for (final c in _all) {
      if (c.code.toLowerCase().contains(t) ||
          c.nameJp.toLowerCase().contains(t) ||
          (c.nameZh?.toLowerCase().contains(t) ?? false) ||
          (c.effectZh?.toLowerCase().contains(t) ?? false)) {
        out.add(c);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// 检索 + 组合筛选（不分页，调用方自己切片；上限 3000 条防意外）
  List<LyceeCard> query(String text, CardFilter? filter,
      {int cap = 20000, bool allowAll = false}) {
    final t = text.trim().toLowerCase();
    final f = (filter == null || filter.isEmpty) ? null : filter;
    if (t.isEmpty && f == null && !allowAll) return const [];
    // 模糊搜索：归一化索引圈出命中集合（简繁中日混输、罗马字、拼音都能命中）
    final fuzzy = t.isEmpty ? null : SearchIndex.instance.match(t);
    final out = <LyceeCard>[];
    for (final c in _all) {
      if (f != null && !f.matches(c)) continue;
      if (t.isNotEmpty) {
        // 命中索引就是最快的路径，先看它
        var ok = fuzzy != null && fuzzy.contains(c.code);
        if (!ok) {
          // 退回逐字段匹配（卡号、以及索引覆盖不到的短词）。
          // 用预计算的小写值，避免每次搜索都重新分配字符串。
          final lo = _lower[c.code];
          if (lo != null) {
            ok = lo[0].contains(t) ||
                lo[1].contains(t) ||
                lo[2].contains(t) ||
                lo[3].contains(t) ||
                // 索引没就绪时退回原来的行为；就绪后日文效果也由索引覆盖
                (fuzzy == null && lo[4].contains(t));
          } else {
            ok = c.code.toLowerCase().contains(t) ||
                c.nameJp.toLowerCase().contains(t);
          }
        }
        if (!ok) continue;
      }
      out.add(c);
      if (out.length >= cap) break;
    }
    return out;
  }

  /// 卡名 → 它出现过的系列集合（懒加载）。
  ///
  /// 用来判断「这张卡的名字是不是跨了多个系列」：数据里 154 个卡名
  /// 分布在不同的弹里（「セイバー／アルトリア・ペンドラゴン」在
  /// Fate/Grand Order 1.0 / 2.0 / 3.0 各有一张）。列表里光看卡名
  /// 分不清是哪一张，所以要给这些卡额外标注系列名。
  Map<String, Set<String>>? _nameSeries;

  void _ensureNameSeries() {
    if (_nameSeries != null) return;
    final m = <String, Set<String>>{};
    for (final c in _all) {
      final n = c.nameJp;
      if (n.isEmpty) continue;
      (m[n] ??= <String>{}).add(c.seriesName);
    }
    _nameSeries = m;
  }

  /// 这个名字是否跨多个系列（跨了才需要在列表里标系列名）
  bool nameSpansSeries(String nameJp) {
    if (nameJp.isEmpty) return false;
    _ensureNameSeries();
    return (_nameSeries![nameJp]?.length ?? 0) > 1;
  }

  /// 筛选面板要用的候选项
  List<String> get allColors => _distinct((c) => c.color);
  List<String> get allKinds => _distinct((c) => c.kind);
  List<String> get allTypes => _distinct((c) => c.cardType);
  List<String> get allRarities => _distinct((c) => c.rarity);

  List<String> _distinct(String? Function(LyceeCard) pick) {
    final s = <String>{};
    for (final c in _all) {
      final v = pick(c);
      if (v != null && v.trim().isNotEmpty && v != '-') s.add(v.trim());
    }
    return s.toList()..sort();
  }

  /// 按「作品（系列）」分组 —— 这就是构筑限制里说的那个系列
  Map<String, List<LyceeCard>> groupBySeries() {
    final m = <String, List<LyceeCard>>{};
    for (final c in _all) {
      (m[c.seriesName] ??= <LyceeCard>[]).add(c);
    }
    return m;
  }

  /// 两级分组：会社/品牌 → 作品（系列）→ 卡
  ///
  /// 卡片的构筑限制通常是「只能使用某个作品/会社的卡」，
  /// 所以收藏页按这个层级来看才用得上。
  Map<String, List<SeriesGroup>> groupByBrandThenSeries() {
    final cached = _brandSeriesCache;
    if (cached != null) return cached;
    final tmp = <String, Map<String, List<LyceeCard>>>{};
    for (final c in _all) {
      final brand = c.brandTag;
      final series = c.seriesName;
      ((tmp[brand] ??= {})[series] ??= <LyceeCard>[]).add(c);
    }
    final out = <String, List<SeriesGroup>>{};
    tmp.forEach((brand, seriesMap) {
      final list = seriesMap.entries
          .map((e) => SeriesGroup(e.key, brand, e.value))
          .toList()
        ..sort((a, b) {
          final byCount = b.total.compareTo(a.total);
          return byCount != 0 ? byCount : a.name.compareTo(b.name);
        });
      out[brand] = list;
    });
    return _brandSeriesCache = out;
  }

  /// 某个作品的全部卡（用于构筑限制提示）
  List<LyceeCard> bySeries(String seriesName) =>
      groupBySeries()[seriesName] ?? const [];

  // ───────────────────────── 卡名跳转索引 ─────────────────────────

  List<_NameEntry>? _nameIndex;
  final Map<String, List<_NameEntry>> _byFirst = {};

  /// 效果文本里引用过的名字 → 卡号（构建时预计算，见 tools/build_name_refs.py）
  Map<String, List<String>> _nameRefs = const {};

  void _ensureNameIndex() {
    if (_nameIndex != null) return;
    final list = <_NameEntry>[];
    final seenPart = <String, int>{};
    final partOwner = <String, String>{};
    for (final c in _all) {
      final series = c.series ?? '';
      // 整张卡的完整名字：2 字也收 —— 「言霊」这种卡名就是两个字，
      // 以前门槛写 3 就直接漏了，效果里提到它也不会标蓝/可跳转。
      final jp = _norm(c.nameJp);
      if (jp.length >= 2) list.add(_NameEntry(jp, c.code, series));
      final zh = _norm(c.nameZh ?? '');
      if (zh.length >= 2) list.add(_NameEntry(zh, c.code, series));
      // 「セイバー／アルトリア・ペンドラゴン」这种，前半段也单独登记（唯一时）。
      // 片段仍要求 ≥3 字：2 字的片段太容易误伤普通词。
      for (final part in c.nameJp.split(RegExp(r'[／/]'))) {
        final p = _norm(part);
        if (p.length < 3) continue;
        seenPart[p] = (seenPart[p] ?? 0) + 1;
        partOwner[p] = c.code;
      }
    }
    seenPart.forEach((p, n) {
      if (n == 1) list.add(_NameEntry(p, partOwner[p]!, ''));
    });

    // 效果文本里引用过的名字。这些名字往往只是卡名的一部分
    // （「超电磁炮 御坂美琴」→「御坂美琴」），或者和卡名有繁简差异
    // （「大藏遊星」vs「大藏游星」），按 ／ 和空格拆分凑不齐，
    // 所以由 tools/build_name_refs.py 在构建时算好、这里直接并入索引。
    // 一个名字可能对应多张卡（同名不同版本），全部登记，
    // 让下面 scanCardNames 的「同名多候选」逻辑去排序/让用户选。
    _nameRefs.forEach((name, codes) {
      final n = _norm(name);
      if (n.length < 2) return;
      for (final c in codes) {
        list.add(_NameEntry(n, c, _byCode[c]?.series ?? ''));
      }
    });

    _nameIndex = list;
    for (final e in list) {
      final f = e.name[0];
      (_byFirst[f] ??= <_NameEntry>[]).add(e);
    }
  }

  /// 候选与"当前卡系列"的接近程度，越小越优先。
  /// 0 = 同一系列（如都属 パープルソフトウェア 1.0(PUR)）
  /// 1 = 同一作品会社（括号里的 PUR / WP 这种）
  /// 2 = 其他
  static int _seriesRank(String cand, String self) {
    if (self.isEmpty || cand.isEmpty) return 2;
    if (cand == self) return 0;
    // 同一系列在数据里写法很杂：可能带会社后缀也可能不带，
    // 版本号/副标题也不总一致（"ガールズ＆パンツァー最終章 1.0(GUP)"
    // vs "ガールズ＆パンツァー戦車道大作戦！ 1.0"）。所以分三层比：
    //   ① 去掉 (XXX) 后缀完全相同
    //   ② 会社码相同
    //   ③ 作品名主干（去掉版本号等）有足够长的共同前缀
    if (_baseSeries(cand) == _baseSeries(self)) return 0;
    final a = _brandOf(cand);
    final b = _brandOf(self);
    if (a.isNotEmpty && a == b) return 1;
    if (_sameWork(cand, self)) return 1;
    return 2;
  }

  /// 去掉系列名末尾的会社后缀："xxx 1.0(GUP)" → "xxx 1.0"
  static String _baseSeries(String series) =>
      series.replaceAll(RegExp(r'\s*\([A-Za-z]{2,6}\)\s*$'), '').trim();

  /// 判断两个系列名是不是同一部作品。
  /// 取"去掉版本号/数字/英文尾缀"后的主干，看共同前缀够不够长。
  static bool _sameWork(String x, String y) {
    String stem(String v) {
      var t = v.replaceAll(RegExp(r'\s*\([A-Za-z]{2,6}\)\s*$'), '');
      t = t.replaceAll(RegExp(r'[\s　0-9．.]+$'), ''); // 去尾巴上的版本号
      return t.trim();
    }

    final a = stem(x);
    final b = stem(y);
    if (a.length < 3 || b.length < 3) return false;
    var n = 0;
    final m = a.length < b.length ? a.length : b.length;
    while (n < m && a[n] == b[n]) {
      n++;
    }
    // 共同前缀够长，且至少覆盖较短那个的六成 —— 避免只对上
    // 「×××」这种通用开头就误判成同一作品。
    // 阈值取 4：日文作品名本来就短（「オーガスト」5 字），
    // 用 6 会把「オーガスト 1.0」和「オーガスト DX1(AUG)」判成两回事。
    return n >= 4 && n >= (m * 0.6);
  }

  /// 从系列名里取括号中的会社码，例如 "パープルソフトウェア 1.0(PUR)" → "PUR"
  static String _brandOf(String series) {
    final m = RegExp(r'\(([A-Za-z]{2,6})\)').firstMatch(series);
    return m?.group(1)?.toUpperCase() ?? '';
  }
  static String _norm(String s) =>
      s.replaceAll(RegExp(r'[\s　・·]'), '').trim();

  /// 主循环里"跳过起点"用的字符集
  static bool _isSkip(String ch) =>
      RegExp(r'[\s　、。，,．\.！!？?「」『』（）()\[\]［］：:；;—\-–~～]').hasMatch(ch);

  /// 匹配过程中允许"跨过"的字符。**只留空白和「・」** ——
  /// 那才是卡名里会被 [_norm] 吃掉的东西。标点符号一律不许跨：
  /// 跨过它们会拼出「ア！」キ」「ジ][オーダー」这种根本不存在的卡名，
  /// 框出来的文本也是错的。
  static bool _isSkipInMatch(String ch) =>
      RegExp(r'[\s　・·]').hasMatch(ch);

  /// 片假名字符（长音符算在内；「・」是分隔符，不算）
  static bool _isKatakanaChar(int r) =>
      (r >= 0x30A1 && r <= 0x30FA) || r == 0x30FC;

  /// 全片假名的名字
  static bool _isKatakanaName(String s) {
    if (s.isEmpty) return false;
    for (final r in s.runes) {
      if (!_isKatakanaChar(r)) return false;
    }
    return true;
  }

  /// 名字是不是被夹在更长的片假名词里。
  ///
  /// 片假名词组没有空格，边界就是片假名本身，所以两侧紧邻片假名即可判定。
  static bool _insideKatakanaRun(String text, int start, int end) {
    if (start > 0 && _isKatakanaChar(text.codeUnitAt(start - 1))) return true;
    if (end < text.length && _isKatakanaChar(text.codeUnitAt(end))) return true;
    return false;
  }

  /// 在文案里找出提到的卡名，返回命中位置。
  ///
  /// [selfSeries] 是**当前这张卡**所属的系列：同名卡往往分布在不同的
  /// 弹数里（比如「言霊」在 パープルソフトウェア 1.0 和 2.0 各有一张），
  /// 用它把同系列的候选排到最前面，跳转就不会跑到别的弹去。
  List<NameHit> scanCardNames(String text, {String selfSeries = ''}) {
    _ensureNameIndex();
    final out = <NameHit>[];
    var i = 0;
    while (i < text.length) {
      if (_isSkip(text[i])) {
        i++;
        continue;
      }
      final cands = _byFirst[text[i]];
      if (cands != null) {
        _NameEntry? best;
        var bestEnd = -1;
        for (final e in cands) {
          final end = _matchAt(text, i, e.name);
          if (end > bestEnd) {
            bestEnd = end;
            best = e;
          }
        }
        // ⚠ 片假名名字被夹在更长的片假名词里 → 那是别的词的片段，不是卡名引用。
        // 典型：「ナル」是规则词「ペナルティ」的中间两个字（ペ-ナル-ティ），
        // 实测 541 张卡／563 处效果因此凭空多出一处指向别作品的假跳转；
        // 「ソル」撞「ソルティレージュ」也是同一类。
        // 汉字没有这种天然边界（「言霊」可能真是复合词的一部分），
        // 所以只对全片假名名字做这个判断。
        if (best != null &&
            bestEnd > i &&
            !(_isKatakanaName(best.name) &&
                _insideKatakanaRun(text, i, bestEnd))) {
          // 收集同名同长度的所有候选（同名不同编号）
          final hits = <_NameEntry>[];
          for (final e in cands) {
            if (e.name.length != best.name.length) continue;
            if (_matchAt(text, i, e.name) == bestEnd &&
                !hits.any((h) => h.code == e.code)) {
              hits.add(e);
            }
          }
          if (hits.isEmpty) hits.add(best);
          // 同系列的排最前：这样唯一的"最优候选"就是玩家真正要的那张
          hits.sort((a, b) {
            final sa = _seriesRank(a.series, selfSeries);
            final sb = _seriesRank(b.series, selfSeries);
            if (sa != sb) return sa.compareTo(sb);
            return a.code.compareTo(b.code); // 稳定：同档按卡号
          });
          final codes = hits.map((h) => h.code).toList();
          out.add(NameHit(i, bestEnd, codes.first, codes: codes));
          i = bestEnd;
          continue;
        }
      }
      i++;
    }
    return out;
  }

  /// 从 [start] 开始匹配 [name]（两边都忽略空白），返回结束下标；失败返回 -1
  static int _matchAt(String text, int start, String name) {
    var i = start;
    var k = 0;
    while (k < name.length) {
      while (i < text.length && _isSkipInMatch(text[i])) {
        i++;
      }
      if (i >= text.length) return -1;
      if (text[i] != name[k]) return -1;
      i++;
      k++;
    }
    return i;
  }

  /// 复制用的纯文本
  static String exportText(LyceeCard c) {
    final b = StringBuffer();
    b.writeln(c.displayName);
    if (c.nameJp != c.displayName) b.writeln(c.nameJp);
    b.writeln(c.code);
    if ((c.titleJp ?? '').isNotEmpty) b.writeln(tr('称号：{0}', [c.titleJp]));
    final stats = <String>[
      if ((c.color ?? '').isNotEmpty) tr('属性 {0}', [c.color]),
      if (c.cost != null) tr('费用 {0}', [c.cost]),
      if (c.ap != null) 'AP ${c.ap}',
      if (c.dp != null) 'DP ${c.dp}',
      if (c.sp != null) 'SP ${c.sp}',
      if (c.dmg != null) 'DMG ${c.dmg}',
    ];
    if (stats.isNotEmpty) b.writeln(stats.join('　'));
    if ((c.cardType ?? '').isNotEmpty) b.writeln(tr('类型：{0}', [c.cardType]));
    if ((c.effectZh ?? '').isNotEmpty) {
      b.writeln();
      b.writeln(c.effectZh);
    }
    b.writeln();
    b.writeln(tr('系列：{0}　会社：{1}', [c.seriesName, c.brandTag]));
    if ((c.illustrator ?? '').isNotEmpty) b.writeln(tr('画家：{0}', [c.illustrator]));
    if ((c.rarity ?? '').isNotEmpty) b.writeln(tr('稀有度：{0}', [c.rarity]));
    if (c.isLeader) b.writeln(tr('★ 含「领导者」，一套卡组最多 1 张'));
    b.write(tr('数据：lycee-tcg.com（官方）｜ 中文：lycard 自译'));
    return b.toString();
  }
}

class _NameEntry {
  _NameEntry(this.name, this.code, this.series);
  final String name;
  final String code;

  /// 所属系列，用于同名候选排序（同系列的优先）
  final String series;
}

class NameHit {
  NameHit(this.start, this.end, this.code, {List<String>? codes})
      : codes = codes ?? <String>[code];

  final int start;
  final int end;
  final String code;

  /// 同名同长度的**全部**卡号（至少 1 个）。
  /// 以前这里只存一个 code，于是「同一张卡名有多个编号」时
  /// 点进去的总不是玩家想的那张 —— 现在把候选都带出去，
  /// 由点击方决定是直接进还是让用户挑。
  final List<String> codes;
}
