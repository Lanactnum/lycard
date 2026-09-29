import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../l10n/l10n.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/glass.dart';
import '../widgets/layout.dart';

/// 对战教程（入口：关于 → 对战教程）。
///
/// 内容和「对战规则」页分工不同：规则页是速查表（一条条列出来），
/// 这里是从零上手的分步教程 —— 先讲赢的条件，再讲开局、场地、
/// 回合、战斗，最后是卡面读法和新手容易踩的坑。
///
/// 正文全部来自 assets/data/tutorial.json，依据 LYCEE OVERTURE
/// 官方规则页（lycee-tcg.com/rule/）整理并自译中文。**内容不参与
/// 界面多语言**（教程是中文的），要改教程直接改那个 JSON。
class TutorialPage extends StatefulWidget {
  const TutorialPage({super.key});

  @override
  State<TutorialPage> createState() => _TutorialPageState();
}

class _TutorialPageState extends State<TutorialPage> {
  List<_Chapter> _chapters = const [];
  String _source = '';
  bool _loading = true;
  bool _failed = false;

  /// 每章一个 key，用于目录跳转
  final Map<int, GlobalKey> _keys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await rootBundle.loadString('assets/data/tutorial.json');
      final j = jsonDecode(s) as Map<String, dynamic>;
      final raw = (j['chapters'] as List?) ?? const [];
      final list = raw
          .map((e) => _Chapter.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
      for (var i = 0; i < list.length; i++) {
        _keys[i] = GlobalKey();
      }
      if (!mounted) return;
      setState(() {
        _chapters = list;
        _source = '${j['source'] ?? ''}';
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _jumpTo(int i) {
    final k = _keys[i];
    final ctx = k?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      alignment: 0.02,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BgScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('对战教程'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Text(tr('教程内容加载失败'),
                      style: TextStyle(color: scheme.onSurfaceVariant)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(
                      left: 16, right: 16, top: 8, bottom: kBottomBarSpace),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('从零开始的一局。内容依据官方规则整理。'),
                        style: TextStyle(
                            fontSize: 11.5, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      _Toc(chapters: _chapters, onTap: _jumpTo),
                      const SizedBox(height: 6),
                      for (var i = 0; i < _chapters.length; i++)
                        _ChapterView(
                          key: _keys[i],
                          index: i + 1,
                          chapter: _chapters[i],
                        ),
                      const SizedBox(height: 18),
                      Text(
                        '${tr('来源')}：$_source',
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tr('以上为规则整理，细节以官方规则书为准。'),
                        style: TextStyle(
                            fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
    );
  }
}

/// 目录：点一下滚到那一章
class _Toc extends StatelessWidget {
  const _Toc({required this.chapters, required this.onTap});

  final List<_Chapter> chapters;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('目录'),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (var i = 0; i < chapters.length; i++)
                GestureDetector(
                  onTap: () => onTap(i),
                  child: Text(
                    '${i + 1}. ${chapters[i].title}',
                    style: TextStyle(fontSize: 12, color: scheme.primary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChapterView extends StatelessWidget {
  const _ChapterView({
    super.key,
    required this.index,
    required this.chapter,
  });

  final int index;
  final _Chapter chapter;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconFor(chapter.icon), size: 17, color: scheme.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '$index. ${chapter.title}',
                  style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final b in chapter.blocks) _BlockView(b: b),
        ],
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.b});

  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = '${b['t'] ?? 'p'}';

    switch (t) {
      case 'head':
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 5),
          child: Text(
            '${b['x'] ?? ''}',
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant),
          ),
        );

      case 'key':
        // 最重要的一句话，单独拎出来
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '${b['x'] ?? ''}',
            style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                fontWeight: FontWeight.w700,
                color: scheme.primary),
          ),
        );

      case 'note':
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 6),
                child: Icon(Icons.info_outline,
                    size: 14, color: scheme.onSurfaceVariant),
              ),
              Expanded(
                child: Text(
                  '${b['x'] ?? ''}',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.55,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        );

      case 'steps':
        final items = _strList(b['x']);
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < items.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 序号用画出来的圆 + 数字，不依赖字体的圈号字形
                      Container(
                        width: 18,
                        height: 18,
                        margin: const EdgeInsets.only(top: 1.5, right: 8),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.16),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary),
                        ),
                      ),
                      Expanded(
                        child: Text(items[i],
                            style: const TextStyle(
                                fontSize: 12.5, height: 1.55)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );

      case 'bullets':
        final items = _strList(b['x']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final s in items)
              Padding(
                padding: const EdgeInsets.only(top: 3, bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6.5, right: 8),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(s,
                          style: const TextStyle(
                              fontSize: 12.5, height: 1.55)),
                    ),
                  ],
                ),
              ),
          ],
        );

      case 'table':
        return _TableView(b: b);

      default: // p
        return Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 3),
          child: Text(
            '${b['x'] ?? ''}',
            style: const TextStyle(fontSize: 12.5, height: 1.6),
          ),
        );
    }
  }
}

/// 表格。手机屏幕窄，所以不画线、也不硬做多列：
/// 两列就左右排（左窄右宽），三列及以上改成「每条一个小块」，
/// 第一列当标题、后面几列竖着列出来 —— 比硬挤成三列好读得多。
class _TableView extends StatelessWidget {
  const _TableView({required this.b});

  final Map<String, dynamic> b;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final head = _strList(b['head']);
    final rows = (b['rows'] as List? ?? const [])
        .map((r) => _strList(r))
        .toList(growable: false);

    if (head.length <= 2) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.only(top: 5, bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 74,
                    child: Text(
                      r.isNotEmpty ? r[0] : '',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: scheme.primary),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      r.length > 1 ? r[1] : '',
                      style: const TextStyle(fontSize: 12.5, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    // 三列及以上：每条一个小块
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(top: 7, bottom: 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.isNotEmpty ? r[0] : '',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary),
                ),
                if (r.length > 1 && r[1].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      r[1],
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (r.length > 2 && r[2].isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(r[2],
                        style:
                            const TextStyle(fontSize: 12.5, height: 1.55)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

List<String> _strList(Object? v) {
  if (v is List) return v.map((e) => '$e').toList(growable: false);
  if (v is String) return [v];
  return const [];
}

IconData _iconFor(String name) {
  const m = <String, IconData>{
    'flag': Icons.flag_outlined,
    'casino': Icons.casino_outlined,
    'grid_view': Icons.grid_view_outlined,
    'autorenew': Icons.autorenew_outlined,
    'paid': Icons.paid_outlined,
    'swords': Icons.sports_martial_arts,
    'style': Icons.style_outlined,
    'bolt': Icons.bolt_outlined,
    'info': Icons.info_outline,
    'build': Icons.build_outlined,
    'phone_iphone': Icons.phone_iphone_outlined,
  };
  return m[name] ?? Icons.article_outlined;
}

class _Chapter {
  const _Chapter({
    required this.title,
    required this.icon,
    required this.blocks,
  });

  final String title;
  final String icon;
  final List<Map<String, dynamic>> blocks;

  factory _Chapter.fromJson(Map<String, dynamic> j) => _Chapter(
        title: '${j['title'] ?? ''}',
        icon: '${j['icon'] ?? ''}',
        blocks: ((j['blocks'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(growable: false),
      );
}
