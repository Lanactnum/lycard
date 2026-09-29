import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../data/card_filter.dart';
import '../data/card_repository.dart';
import '../data/card_saver.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/image_quality_dialog.dart';
import '../widgets/filter_panel.dart';
import '../widgets/motion.dart';
import '../widgets/glass.dart';
import '../widgets/quick_add.dart';
import '../widgets/responsive.dart';
import '../widgets/card_route.dart';
import '../widgets/pill_switch.dart';
import '../widgets/tags.dart';
import '../widgets/layout.dart';
import '../widgets/bg_scaffold.dart';
import 'scan_page.dart';
import '../widgets/deck_import_dialog.dart';
import '../l10n/l10n.dart';

enum _Mode { text, filter }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  // 搜索 / 筛选 两套结果各自独立，互不影响
  List<LyceeCard> _searchHits = const []; // 只由关键词决定
  List<LyceeCard> _filterHits = const []; // 只由筛选条件决定
  List<LyceeCard> get _results =>
      _mode == _Mode.text ? _searchHits : _filterHits;
  String _q = '';

  // 组合筛选 + 分页
  final CardFilter _filter = CardFilter();
  int _shown = _pageSize;
  static const int _pageSize = 40;

  int get _visibleCount => _shown < _results.length ? _shown : _results.length;

  // 多选保存模式
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _saving = false;
  String _saveMsg = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Timer? _debounce;

  /// 输入防抖：连续打字只搜最后一次
  void _onType(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () => _runSearch(q));
  }

  /// 搜索模式：**只看关键词**，不带任何筛选条件
  void _runSearch(String q) {
    final hadFocus = _focus.hasFocus;
    setState(() {
      _q = q;
      _shown = _pageSize;
      if (q.trim().isEmpty) {
        _searchHits = const [];
      } else {
        _searchHits = CardRepository.instance.query(
          q,
          CardFilter(),
          allowAll: false,
        );
      }
    });
    // 搜完别把键盘/焦点丢掉（否则点一下就弹不出来）
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_focus.hasFocus) _focus.requestFocus();
      });
    }
    debugPrint('lycard-检索 [搜索] q="$q" → ${_searchHits.length} 张');
  }

  /// 筛选模式：**只看条件**，不看关键词
  void _runFilter() {
    setState(() {
      _shown = _pageSize;
      _filterHits = CardRepository.instance.query('', _filter, allowAll: true);
    });
    debugPrint(
      'lycard-检索 [筛选] 条件=${_filter.activeCount} → ${_filterHits.length} 张',
    );
  }

  /// 返回键：先退掉「搜索/筛选」的状态，而不是直接退出 App
  bool get _hasTransientState =>
      _selecting || _mode == _Mode.filter || _q.isNotEmpty;

  void _stepBack() {
    if (_selecting) {
      setState(() {
        _selecting = false;
        _selected.clear();
      });
      return;
    }
    if (_mode == _Mode.filter) {
      setState(() {
        _filter.clear();
        _mode = _Mode.text;
      });
      _runFilter();
      return;
    }
    if (_q.isNotEmpty) {
      _ctrl.clear();
      _runSearch('');
    }
  }

  _Mode _mode = _Mode.text;
  String get modeName => _mode == _Mode.text ? tr('搜索') : tr('筛选');

  void _switchMode(_Mode m) {
    setState(() => _mode = m);
    // 各自的结果都已经算好了；首次进筛选模式时补算一次
    if (m == _Mode.filter && _filterHits.isEmpty) _runFilter();
  }

  @override
  void initState() {
    super.initState();
    // 调试：--dart-define=START_FILTER=color:雪;kind:キャラクター;costMax:1
    final spec = const String.fromEnvironment('START_FILTER');
    if (spec.isNotEmpty) {
      for (final part in spec.split(';')) {
        final kv = part.split(':');
        if (kv.length != 2) continue;
        final k = kv[0].trim();
        final v = kv[1].trim();
        switch (k) {
          case 'color':
            _filter.colors.add(v);
          case 'kind':
            _filter.kinds.add(v);
          case 'type':
            _filter.types.add(v);
          case 'rarity':
            _filter.rarities.add(v);
          case 'kw':
            _filter.keywords.add(v);
          case 'costMin':
            _filter.costMin = int.tryParse(v);
          case 'costMax':
            _filter.costMax = int.tryParse(v);
          case 'apMin':
            _filter.apMin = int.tryParse(v);
          case 'apMax':
            _filter.apMax = int.tryParse(v);
          case 'dmgMin':
            _filter.dmgMin = int.tryParse(v);
          case 'dmgMax':
            _filter.dmgMax = int.tryParse(v);
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _mode = _Mode.filter);
        _runFilter();
      });
    }
  }

  /// 「筛选」栏：条件面板在上，结果实时跟在下面
  Widget _filterView(BuildContext context, int cols, double gap) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 8, 4),
            child: FilterPanel(filter: _filter, onChanged: _runFilter),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
            child: Text(
              _results.isEmpty
                  ? tr('没有符合条件的卡')
                  : '命中 ${_results.length} 张'
                        '${_filter.isEmpty ? '' : '（已选 ${_filter.activeCount} 个条件）'}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(gap, 0, gap, kBottomBarSpace),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: gap,
              crossAxisSpacing: gap,
              childAspectRatio: 2 / 3,
            ),
            itemCount: _visibleCount,
            itemBuilder: (c, i) => _tile(context, _results[i]),
          ),
        ),
        if (_visibleCount < _results.length)
          SliverToBoxAdapter(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _shown = _visibleCount + _pageSize),
                  icon: const Icon(Icons.expand_more),
                  label: Text(
                    tr('加载更多（还有 {0} 张）', [_results.length - _visibleCount]),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 一张卡（搜索/筛选两种模式共用）
  Widget _tile(BuildContext context, LyceeCard card) {
    final state = context.read<AppState>();
    final checked = _selected.contains(card.code);
    return CardTile(
      card: card,
      owned: state.isOwned(card.code),
      favorite: state.isFavorite(card.code),
      selected: _selecting && checked,
      onTap: () {
        if (_selecting) {
          setState(() {
            checked ? _selected.remove(card.code) : _selected.add(card.code);
          });
        } else {
          openCardDetail(context, card.code, scope: 'list');
        }
      },
      onLongPress: () => setState(() {
        _selecting = true;
        _selected.add(card.code);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = CardRepository.instance;
    final cols = resolveColumns(context, state.gridColumns);
    final gap = resolveGap(context);

    return PopScope(
      // 有搜索词 / 开着筛选 / 多选中时，返回键先退状态，不退出 App
      canPop: !_hasTransientState,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stepBack();
      },
      child: BgScaffold(
        // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
        backgroundColor: Colors.transparent,
        appBar: _selecting
            ? GlassAppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
                ),
                title: Text(tr('已选 {0} 张', [_selected.length])),
                actions: [
                  TextButton(
                    onPressed: () => setState(() {
                      if (_selected.length == _results.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(_results.map((e) => e.code));
                      }
                    }),
                    child: Text(
                      _selected.length == _results.length
                          ? tr('取消全选')
                          : tr('全选'),
                    ),
                  ),
                  IconButton(
                    tooltip: tr('复制所选卡名'),
                    icon: const Icon(Icons.copy),
                    onPressed: _selected.isEmpty ? null : _copySelected,
                  ),
                  IconButton(
                    tooltip: tr('加进构筑（每张 +1）'),
                    icon: const Icon(Icons.library_add_outlined),
                    onPressed: _selected.isEmpty
                        ? null
                        : () {
                            final cards = _selected
                                .map((c) => CardRepository.instance.byCode(c))
                                .whereType<LyceeCard>()
                                .toList();
                            quickAddSheet(context, state, cards);
                          },
                  ),
                  IconButton(
                    tooltip: tr('保存卡图到相册'),
                    icon: const Icon(Icons.download),
                    onPressed: _selected.isEmpty || _saving
                        ? null
                        : _saveSelected,
                  ),
                ],
              )
            : GlassAppBar(
                title: Text(tr('检索')),
                actions: [
                  IconButton(
                    tooltip: tr('扫码识别卡号/二维码'),
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      // 扫到卡号时扫描页会就地进详情，这里只在扫到分享码时回来
                      final r = await ScanPage.show(context);
                      if (r == null || !context.mounted) return;
                      await importDeckFromText(context, state, r);
                    },
                  ),
                  if (_results.isNotEmpty && _mode == _Mode.text)
                    IconButton(
                      tooltip: tr('多选保存'),
                      icon: const Icon(Icons.checklist),
                      onPressed: () => setState(() => _selecting = true),
                    ),
                  IconButton(
                    tooltip:
                        '手动列数：${state.gridColumns == 0 ? '自动' : state.gridColumns}',
                    icon: Icon(
                      state.gridColumns == 0
                          ? Icons.grid_view
                          : Icons.grid_view_rounded,
                    ),
                    onPressed: () => _pickColumns(context, state),
                  ),
                ],
              ),
        body: Column(
          children: [
            // 这一对也做成悬浮胶囊（透明 + 模糊）
            Glass(
              margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              blur: state.barBlur,
              opacity: state.barOpacity,
              child: PillSwitch(
                labels: [tr('搜索'), tr('筛选')],
                icons: const [Icons.search, Icons.tune],
                index: _mode == _Mode.text ? 0 : 1,
                onChanged: (i) =>
                    _switchMode(i == 0 ? _Mode.text : _Mode.filter),
              ),
            ),
            if (_mode == _Mode.text)
              Glass(
                margin: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                radius: 22,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onChanged: _onType,
                    onSubmitted: _runSearch,
                    keyboardType: state.searchNumberPad
                        ? const TextInputType.numberWithOptions(signed: false)
                        : TextInputType.text,
                    decoration: InputDecoration(
                      hintText: tr('卡名/卡号/效果…'),
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: state.searchNumberPad
                                ? tr('切到文字键盘')
                                : tr('切到数字键盘'),
                            icon: Icon(
                              state.searchNumberPad
                                  ? Icons.dialpad
                                  : Icons.keyboard,
                            ),
                            onPressed: () {
                              final next = !state.searchNumberPad;
                              state.setSearchNumberPad(next);
                              // 光改 keyboardType 平台键盘不会换：得先把输入通道断掉，
                              // 下一帧再连回来，新的 keyboardType 才生效
                              _focus.unfocus();
                              Future.delayed(
                                const Duration(milliseconds: 90),
                                () {
                                  if (mounted) _focus.requestFocus();
                                },
                              );
                            },
                          ),
                          if (_q.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _ctrl.clear();
                                _runSearch('');
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_saving)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(_saveMsg, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            if (_mode == _Mode.filter)
              Expanded(child: _filterView(context, cols, gap))
            else if (_q.isEmpty && _filter.isEmpty)
              Expanded(
                child: _EmptyHint(
                  count: repo.count,
                  onExample: (s) {
                    _ctrl.text = s;
                    _runSearch(s);
                  },
                ),
              )
            else if (_results.isEmpty)
              Expanded(child: Center(child: Text(tr('没找到符合条件的卡…'))))
            else
              Expanded(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '命中 ${_results.length} 张'
                              '${_filter.isEmpty ? '' : ' · 筛选 ${_filter.activeCount} 个条件'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (!_filter.isEmpty)
                            TextButton(
                              onPressed: () {
                                setState(_filter.clear);
                                _runFilter();
                              },
                              child: Text(tr('清筛选')),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          gap,
                          0,
                          gap,
                          kBottomBarSpace,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          childAspectRatio: 2 / 3,
                        ),
                        itemCount: _visibleCount,
                        itemBuilder: (c, i) {
                          final card = _results[i];
                          final checked = _selected.contains(card.code);
                          return CardTile(
                            card: card,
                            owned: state.isOwned(card.code),
                            favorite: state.isFavorite(card.code),
                            selected: _selecting && checked,
                            onTap: () {
                              if (_selecting) {
                                setState(() {
                                  checked
                                      ? _selected.remove(card.code)
                                      : _selected.add(card.code);
                                });
                              } else {
                                openCardDetail(
                                  context,
                                  card.code,
                                  scope: 'list',
                                );
                              }
                            },
                            onLongPress: () => setState(() {
                              _selecting = true;
                              _selected.add(card.code);
                            }),
                          );
                        },
                      ),
                    ),
                    if (_visibleCount < _results.length)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: OutlinedButton.icon(
                            onPressed: () => setState(
                              () => _shown = _visibleCount + _pageSize,
                            ),
                            icon: const Icon(Icons.expand_more),
                            label: Text(
                              tr('加载更多（还有 {0} 张）', [
                                _results.length - _visibleCount,
                              ]),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 复制选中的卡名（一行一张）
  void _copySelected() {
    final codes = _selected.toList()..sort();
    final sb = StringBuffer();
    var n = 0;
    for (final code in codes) {
      final card = CardRepository.instance.byCode(code);
      if (card != null) {
        sb.writeln(card.displayName);
        n++;
      }
    }
    Clipboard.setData(ClipboardData(text: sb.toString().trimRight()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('已复制 {0} 张卡的卡名', [n])),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 批量保存选中的卡图到系统相册
  Future<void> _saveSelected() async {
    final codes = _selected.toList();
    if (codes.isEmpty) return;
    final kinds = await Future.wait(
      codes.map((code) => CardSaver.instance.image(code)),
    );
    if (!mounted) return;
    final nonOriginal = kinds.where((image) => !image.isOriginal).toList();
    if (nonOriginal.isNotEmpty &&
        !await confirmCardImageQuality(context, nonOriginal.first.kind)) {
      return;
    }
    setState(() {
      _saving = true;
      _saveMsg = tr('准备中…');
    });
    final ok0 =
        await CardSaver.instance.hasAccess() ||
        await CardSaver.instance.requestAccess();
    if (!ok0) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveMsg = '';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('没有相册权限，没法保存'))));
      return;
    }
    final (ok, failed) = await CardSaver.instance.saveAll(
      codes,
      onProgress: (done, total) {
        if (mounted) {
          setState(() => _saveMsg = tr('保存中 {0}/{1}', [done, total]));
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveMsg = '';
      _selecting = false;
      _selected.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed.isEmpty
              ? tr('已保存 {0} 张卡图到相册', [ok])
              : '保存 $ok 张，失败 ${failed.length} 张（${failed.take(3).join('、')}…）',
        ),
      ),
    );
  }

  Future<void> _pickColumns(BuildContext context, AppState state) async {
    final v = await showGlassSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(tr('每行卡片数'))),
            RadioGroup<int>(
              groupValue: state.gridColumns,
              onChanged: (v) => Navigator.pop(c, v),
              child: Column(
                children: [
                  for (final n in [0, 2, 3, 4, 5, 6, 8])
                    RadioListTile<int>(
                      value: n,
                      title: Text(n == 0 ? tr('自动（跟随屏幕）') : tr('{0} 列', [n])),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (v != null) state.setGridColumns(v);
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.count, required this.onExample});

  final int count;
  final void Function(String) onExample;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 14),
            Text(
              tr('卡池里已有 {0} 张卡', [count]),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              tr('输入卡名或卡号开始检索\\n试试：'),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final e in ['LO-6665', tr('織部'), tr('跳跃')])
                  LyTag(label: e, dense: true, onTap: () => onExample(e)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 网格里的单张卡
class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.onTap,
    this.onLongPress,
    this.owned = true,
    this.favorite = false,
    this.selected = false,
  });

  final LyceeCard card;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool owned;
  final bool favorite;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 同名卡跨多个系列时，底部额外标出系列名 —— 数据里 154 个卡名
    // 分布在不同弹（如「セイバー／アルトリア・ペンドラゴン」在 FGO
    // 1.0/2.0/3.0 各一张），只看卡名分不清该点哪张。
    final spans = CardRepository.instance.nameSpansSeries(card.nameJp);
    return HoverCard(
      radius: 14,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CardHero(
            code: card.code,
            // 圆角和灰度都放在 Hero 里面：飞行途中也是圆角+灰度，
            // 不然起飞/落回那一瞬会闪成方形彩色
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              // 已收集的卡**不套 ColorFiltered**：那个组件每次都会
              // 建一个 saveLayer，一屏 40 张就是 40 层，滚动时很贵。
              // 以前无论收没收集都套（已收集时用 BlendMode.dst 空转），
              // 等于白付这份代价。
              child: owned
                  ? CardArt(card: card)
                  : ColorFiltered(
                      // 未收集 → 灰掉
                      colorFilter: const ColorFilter.matrix(<double>[
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0.2126,
                        0.7152,
                        0.0722,
                        0,
                        0,
                        0,
                        0,
                        0,
                        1,
                        0,
                      ]),
                      child: CardArt(card: card),
                    ),
            ),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (spans)
                    Text(
                      card.seriesName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8.5,
                        height: 1.2,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (favorite)
            Positioned(
              top: 4,
              right: 4,
              child: Icon(Icons.star, size: 18, color: scheme.tertiary),
            ),
          if (selected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.primary, width: 3),
                ),
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.check_circle,
                    size: 22,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
