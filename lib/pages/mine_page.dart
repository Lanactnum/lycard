import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../data/haptics.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/card_picker.dart';
import '../widgets/deck_dialogs.dart';
import '../widgets/motion.dart';
import '../widgets/rarity_badge.dart';
import '../widgets/responsive.dart';
import 'about_page.dart';
import 'custom_cards_page.dart';
import 'data_page.dart';
import 'display_page.dart';
import 'look_page.dart';
import 'rarity_style_page.dart';
import 'storage_page.dart';
import 'theme_page.dart';
import 'wish_page.dart';
import '../widgets/glass.dart';
import '../widgets/card_route.dart';
import '../widgets/scatter.dart';
import '../widgets/layout.dart';
import '../widgets/bg_scaffold.dart';
import 'banlist_page.dart';
import '../data/banlist.dart';
import '../l10n/l10n.dart';
import 'rules_page.dart';

part 'settings_page.dart';

/// 底栏「我的」：卡组（收集）/ 收藏（特殊卡面）
/// 设置已挪到右上角齿轮；构筑并入了底栏「构筑」页。
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: BgScaffold(
        // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(
          title: Text(tr('我的')),
          actions: [
            IconButton(
              tooltip: tr('设置'),
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr('卡组')),
              Tab(text: tr('收藏')),
              Tab(text: tr('备忘录')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CollectionTab(mode: CollectionMode.all),
            _CollectionTab(mode: CollectionMode.favorites),
            WishPage(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 构筑编辑
class _DeckEditorTab extends StatelessWidget {
  const _DeckEditorTab();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, kBottomBarSpace),
      children: [
        for (final d in state.decks) _DeckCard(deck: d),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => showCreateDeckDialog(context, state),
          icon: const Icon(Icons.add),
          label: Text(tr('新建构筑')),
        ),
      ],
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final issues = state.checkDeck(deck);
    final hasError = issues.any((i) => i.level == IssueLevel.error);
    final scheme = Theme.of(context).colorScheme;
    final mainCard = CardRepository.instance.byCode(deck.mainCardCode);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    deck.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  '${deck.total} / ${DeckRules.mainDeckSize}',
                  style: TextStyle(
                    color: hasError ? scheme.error : scheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  tooltip: tr('删除'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => state.deleteDeck(deck.id),
                ),
              ],
            ),
            Row(
              children: [
                SizedBox(
                  width: 40,
                  child: mainCard == null
                      ? Icon(
                          Icons.military_tech_outlined,
                          color: scheme.onSurfaceVariant,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: CardArt(card: mainCard),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mainCard?.displayName ?? tr('未设置主战卡'),
                    style: TextStyle(
                      fontSize: 13,
                      color: mainCard == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _pickMain(context, state, deck),
                  child: Text(tr('选择主战')),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 自动规则检测结果
            for (final i in issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Icon(
                      switch (i.level) {
                        IssueLevel.ok => Icons.check_circle,
                        IssueLevel.warning => Icons.warning_amber,
                        IssueLevel.error => Icons.error_outline,
                      },
                      size: 15,
                      color: switch (i.level) {
                        IssueLevel.ok => Colors.green,
                        IssueLevel.warning => Colors.orange,
                        IssueLevel.error => scheme.error,
                      },
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        i.message,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _addCards(context, state, deck),
                  icon: const Icon(Icons.search, size: 18),
                  label: Text(tr('加卡')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _editList(context, state, deck),
                  icon: const Icon(Icons.list_alt, size: 18),
                  label: Text(tr('卡表')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMain(
    BuildContext context,
    AppState state,
    Deck deck,
  ) async {
    final code = await _pickCard(context, title: tr('选主战卡'));
    if (code != null) state.setDeckMain(deck, code);
  }

  Future<void> _addCards(
    BuildContext context,
    AppState state,
    Deck deck,
  ) async {
    final code = await _pickCard(context, title: tr('加入「{0}」', [deck.name]));
    final card = code == null ? null : CardRepository.instance.byCode(code);
    if (card != null) state.addCard(deck, card);
  }

  Future<String?> _pickCard(
    BuildContext context, {
    required String title,
  }) =>
      pickCard(context, title: title);

  Future<void> _editList(
    BuildContext context,
    AppState state,
    Deck deck,
  ) async {
    await showGlassSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) {
          final entries = deck.cards.entries.toList();
          return SizedBox(
            height: MediaQuery.sizeOf(c).height * 0.7,
            child: Column(
              children: [
                ListTile(title: Text(tr('{0} · 卡表', [deck.name]))),
                Expanded(
                  child: entries.isEmpty
                      ? Center(child: Text(tr('还没加卡')))
                      : ListView(
                          padding: const EdgeInsets.only(
                            bottom: kBottomBarSpace,
                          ),
                          children: [
                            for (final e in entries)
                              ListTile(
                                leading: Text('${e.value}×'),
                                title: Text(
                                  CardRepository.instance
                                          .byCode(e.key)
                                          ?.displayName ??
                                      e.key,
                                ),
                                subtitle: Text(e.key),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove),
                                      onPressed: () {
                                        state.removeCard(deck, e.key);
                                        Haptics.doubleTap(state.haptics);
                                        setSheet(() {});
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add),
                                      onPressed: () {
                                        final card = CardRepository.instance
                                            .byCode(e.key);
                                        if (card != null) {
                                          state.addCard(deck, card);
                                          Haptics.tap(state.haptics);
                                        }
                                        setSheet(() {});
                                      },
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- 收集 / 收藏
enum CollectionMode { all, favorites }

class _CollectionTab extends StatelessWidget {
  const _CollectionTab({required this.mode});

  final CollectionMode mode;

  bool _visible(AppState state, LyceeCard c) =>
      mode == CollectionMode.all || state.isFavorite(c.code);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final repo = CardRepository.instance;
    final cols = resolveColumns(context, state.gridColumns);
    final gap = resolveGap(context);
    final scheme = Theme.of(context).colorScheme;

    // 会社（品牌）→ 作品（系列）→ 卡；构筑限制就是按这两层来卡的
    final raw = repo.groupByBrandThenSeries();
    final grouped = <String, List<SeriesGroup>>{};
    raw.forEach((brand, groups) {
      final kept = <SeriesGroup>[];
      for (final g in groups) {
        final cards = g.cards.where((c) => _visible(state, c)).toList();
        if (cards.isNotEmpty) kept.add(SeriesGroup(g.name, g.brand, cards));
      }
      if (kept.isNotEmpty) grouped[brand] = kept;
    });

    // 各会社的卡数**先算好**再排序。
    // 以前是写成函数在比较器里现算 —— 每次比较都要 fold 遍历一遍，
    // 排序整体变成 O(n log n × n)，会社一多就很明显。
    final brandCount = <String, int>{};
    grouped.forEach((b, gs) {
      var n = 0;
      for (final g in gs) {
        n += g.cards.length;
      }
      brandCount[b] = n;
    });
    int brandCards(String b) => brandCount[b] ?? 0;

    final brands = grouped.keys.toList()
      ..sort((a, b) {
        if (a == LyceeCard.brandOther) return 1;
        if (b == LyceeCard.brandOther) return -1;
        final c = brandCards(b).compareTo(brandCards(a));
        return c != 0 ? c : a.compareTo(b);
      });

    final totalCards = grouped.values
        .expand((g) => g)
        .fold(0, (s, g) => s + g.cards.length);
    final totalSeries = grouped.values.fold(0, (s, g) => s + g.length);

    return ListView(
      padding: const EdgeInsets.only(bottom: kBottomBarSpace),
      children: [
        if (mode == CollectionMode.all) _CollectionProgressHeader(state: state),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Text(
            mode == CollectionMode.all
                ? tr('{0} 个作品 / {1} 个会社 · 共 {2} 张卡', [
                    totalSeries,
                    grouped.length,
                    totalCards,
                  ])
                : tr('特殊卡面收藏 · {0} 张', [state.favorites.length]),
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ),
        // 「全部」：不分系列，整个卡池一起看
        ExpansionTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: scheme.tertiaryContainer,
            child: Text(
              '全',
              style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer),
            ),
          ),
          title: Text(tr('全部'), style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(tr('{0} 张卡（不分会社/作品）', [totalCards])),
          children: [
            _SeriesTile(
              group: SeriesGroup(
                tr('全部卡片'),
                'ALL',
                repo.all.where((c) => _visible(state, c)).toList(),
              ),
              state: state,
              cols: cols,
              gap: gap,
              visible: (c) => _visible(state, c),
            ),
          ],
        ),
        const Divider(height: 1),
        for (final brand in brands)
          ExpansionTile(
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: scheme.primaryContainer,
              child: Text(
                brand == LyceeCard.brandOther
                    ? tr('作')
                    : brand.characters.take(2).toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
            title: Text(
              brand == LyceeCard.brandOther
                  ? tr('作品系列（无会社标记）')
                  : tr('{0} 会社', [brand]),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              tr('{0} 个作品 · {1} 张', [
                grouped[brand]!.length,
                brandCards(brand),
              ]),
            ),
            children: [
              for (final g in grouped[brand]!)
                _SeriesTile(
                  group: g,
                  state: state,
                  cols: cols,
                  gap: gap,
                  visible: (c) => _visible(state, c),
                ),
            ],
          ),
      ],
    );
  }
}

/// 一个「作品」：展开后是该作品的全部卡（没收集的灰显）
///
/// 大系列（有的作品 200 多张）不能一次性全铺开——一屏几百张图同时解码
/// 会把内存吃爆，卡图就会掉成占位符。所以分批显示，点按钮再加。
class _SeriesTile extends StatefulWidget {
  const _SeriesTile({
    required this.group,
    required this.state,
    required this.cols,
    required this.gap,
    required this.visible,
  });

  final SeriesGroup group;
  final AppState state;
  final int cols;
  final double gap;
  final bool Function(LyceeCard) visible;

  @override
  State<_SeriesTile> createState() => _SeriesTileState();
}

class _SeriesTileState extends State<_SeriesTile> {
  static const int _pageSize = 40;
  int _shown = _pageSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cards = widget.group.cards.where(widget.visible).toList();
    final owned = cards.where((c) => widget.state.isOwned(c.code)).length;
    final limit = _shown < cards.length ? _shown : cards.length;
    final slice = cards.sublist(0, limit);

    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: ExpansionTile(
        title: Text(widget.group.name, style: const TextStyle(fontSize: 14)),
        subtitle: Row(
          children: [
            Text(
              '$owned / ${cards.length}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: cards.isEmpty ? 0 : owned / cards.length,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(widget.gap),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: widget.cols,
                mainAxisSpacing: widget.gap,
                crossAxisSpacing: widget.gap,
                childAspectRatio: 2 / 3,
              ),
              itemCount: slice.length,
              itemBuilder: (c, i) {
                final card = slice[i];
                final info = widget.state.collectInfoOf(card.code);
                final rarity = widget.state.rarityOf(card.code, card.rarity);
                return ScatterItem(
                  index: i,
                  code: card.code,
                  child: HoverCard(
                    radius: 12,
                    onTap: () =>
                        openCardDetail(context, card.code, scope: 'list'),
                    onLongPress: () => _collectMenu(context, card.code),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CardHero(
                              code: card.code,
                              // 灰度放 Hero 里面，飞行途中保持灰卡。
                              // 已收集的卡不套 ColorFiltered —— 那个每次都会建
                              // saveLayer，一屏几十张白付这份代价。
                              child: widget.state.isOwned(card.code)
                                  ? CardArt(card: card)
                                  : ColorFiltered(
                                      colorFilter: const ColorFilter.matrix(
                                        <double>[
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
                                        ],
                                      ),
                                      child: CardArt(card: card),
                                    ),
                            ),
                          ),
                        ),
                        if (rarity.isNotEmpty || (info?.parallel ?? false))
                          Positioned(
                            right: 3,
                            top: 3,
                            child: RarityBadge(
                              text: rarity,
                              parallel: info?.parallel ?? false,
                              style: widget.state.rarityStyle(rarity),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (limit < cards.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: OutlinedButton.icon(
                onPressed: () => setState(() {
                  _shown = limit + _pageSize;
                }),
                icon: const Icon(Icons.expand_more),
                label: Text(
                  tr('再显示 {0} 张（还剩 {1} 张）', [_pageSize, cards.length - limit]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 长按卡面：直接把这张卡的信息复制走
void _copyCard(BuildContext context, LyceeCard card) {
  showGlassSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(tr('复制卡名')),
            subtitle: Text(card.displayName),
            onTap: () {
              Clipboard.setData(ClipboardData(text: card.displayName));
              Navigator.of(c).pop();
              _toast(context, tr('卡名已复制'));
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all),
            title: Text(tr('复制卡片信息')),
            subtitle: Text(tr('含属性/效果/系列/画家')),
            onTap: () {
              Clipboard.setData(
                ClipboardData(text: CardRepository.exportText(card)),
              );
              Navigator.of(c).pop();
              _toast(context, tr('卡片信息已复制'));
            },
          ),
          ListTile(
            leading: const Icon(Icons.image),
            title: Text(tr('打开详情')),
            onTap: () {
              Navigator.of(c).pop();
              openCardDetail(context, card.code, scope: 'list');
            },
          ),
        ],
      ),
    ),
  );
}

/// 长按收藏里的卡：记录罕贵度 / 异画，或复制卡名
Future<void> _collectMenu(BuildContext context, String code) async {
  final state = context.read<AppState>();
  final card = CardRepository.instance.byCode(code);
  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              card?.displayName ?? code,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(code),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.bookmark_add_outlined),
            title: Text(tr('记录我的罕贵度 / 异画')),
            onTap: () {
              Navigator.pop(c);
              showCollectDialog(
                context,
                state,
                code,
                CardRepository.instance.allRarities,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: Text(tr('复制卡名')),
            onTap: () {
              Navigator.pop(c);
              if (card != null) _copyCard(context, card);
            },
          ),
        ],
      ),
    ),
  );
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
  );
}

// ---------------------------------------------------------------- 设置
class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: kBottomBarSpace),
      children: [
        _Header(tr('设置')),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(tr('主题配色')),
          subtitle: Text(tr('明暗 / 调色板')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const ThemePage())),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: Text(tr('外观与动效')),
          subtitle: Text(tr('悬浮/透明/圆角/背景/字体')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const LookPage())),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(tr('显示与检索')),
          subtitle: Text(tr('DPI/默认页/每行卡片/键盘/震动')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DisplayPage())),
        ),
        ListTile(
          leading: const Icon(Icons.dashboard_customize_outlined),
          title: Text(tr('自定义卡牌')),
          subtitle: Text(tr('改卡/换卡面/新建')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CustomCardsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(tr('对战规则')),
          subtitle: Text(tr('卡组构成/数值/流程/词条')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const RulesPage())),
        ),
        ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(tr('禁限卡表')),
          subtitle: Text(BanList.instance.summary),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const BanListPage())),
        ),
        ListTile(
          leading: const Icon(Icons.bookmark_border),
          title: Text(tr('罕贵度角标')),
          subtitle: Text(tr('颜色/模糊/透明度')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const RarityStylePage())),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: Text(tr('数据与备份')),
          subtitle: Text(tr('备份/卡图数据包')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const DataPage())),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services),
          title: Text(tr('存储与清理')),
          subtitle: Text(tr('清理垃圾 ·保留 15 天')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const StoragePage())),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr('关于')),
          subtitle: Text(tr('许可/数据来源/版本')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AboutPage())),
        ),
      ],
    );
  }
}

/// 「我的-卡组」顶部的收集进度。
class _CollectionProgressHeader extends StatelessWidget {
  const _CollectionProgressHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = CardRepository.instance.all.length;
    final owned = state.owned.length;
    final rate = total == 0 ? 0.0 : owned * 100 / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$owned / $total',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  tr('张卡 · 收集率 {0}%', [rate.toStringAsFixed(1)]),
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : owned / total,
              minHeight: 5,
              backgroundColor: scheme.surfaceContainerHighest,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
