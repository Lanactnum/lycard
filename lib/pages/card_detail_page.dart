import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../data/haptics.dart';
import '../data/card_saver.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/card_related_view.dart';
import '../widgets/effect_text.dart';
import '../widgets/image_quality_dialog.dart';
import '../widgets/owned_info_dialog.dart';
import '../widgets/quick_add.dart';
import 'card_edit_page.dart';
import '../widgets/glass.dart';
import '../widgets/card_route.dart';
import '../widgets/tags.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/glass_menu.dart';
import '../l10n/l10n.dart';

/// 「我的记录」里显示的一行摘要
String _ownedSummary(AppState state, String code) {
  final info = state.infoOf(code);
  if (info == null) return tr('还没填购入价/入库时间');
  final parts = <String>[];
  if (info.price != null) {
    parts.add(
      '${_num(info.price!)} ${info.currency}'
      '（≈¥${info.valueCny!.toStringAsFixed(2)}）',
    );
  }
  if (info.acquiredAt != null) {
    final d = info.acquiredAt!;
    parts.add(
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
    );
  }
  if (info.rate != null) parts.add('汇率 ${_num(info.rate!)}');
  if (info.note.isNotEmpty) parts.add(info.note);
  return parts.isEmpty ? tr('还没填购入价/入库时间') : parts.join(' · ');
}

String _num(double v) {
  final s = v.toStringAsFixed(4);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// 复制一段文字并给个提示
void _copy(BuildContext context, String text, String toast) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(toast), duration: const Duration(seconds: 2)),
  );
}

class CardDetailPage extends StatefulWidget {
  const CardDetailPage({super.key, required this.code, this.heroScope});

  final String code;

  /// 缩略图那边用同一个 scope，Hero 才能接上（null = 不做 Hero）
  final String? heroScope;

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  String get code => widget.code;
  String? get heroScope => widget.heroScope;

  @override
  void initState() {
    super.initState();
    // 散开 / 收回 统一由 openCardDetail() 控制（入口唯一，时序才可控）
  }

  @override
  Widget build(BuildContext context) {
    final card = CardRepository.instance.byCode(code);
    if (card == null) {
      return BgScaffold(
        // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
        backgroundColor: Colors.transparent,
        appBar: GlassAppBar(),
        body: Center(child: Text(tr('找不到这张卡'))),
      );
    }
    final state = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final scheme = Theme.of(context).colorScheme;

    final art = Hero(
      tag: 'card-${card.code}',
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: heroScope == null
              ? CardArt(card: card)
              : Hero(
                  tag: cardHeroTag(code, heroScope!),
                  child: CardArt(card: card),
                ),
        ),
      ),
    );

    final infoChildren = <Widget>[
      Text(card.displayName, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Row(
        children: [
          LyTag(label: card.code, icon: Icons.tag, dense: true),
          const SizedBox(width: 6),
          if (card.color != null) LyTag(label: card.color!, dense: true),
        ],
      ),
      if (card.nameZh != null && card.nameJp.isNotEmpty)
        Text(
          tr('原文：{0}', [card.nameJp]),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      const SizedBox(height: 16),
      _StatRow(card: card),
      const SizedBox(height: 20),
      _Section(
        title: tr('效果'),
        child: EffectText(
          text: state.useZh
              ? (card.effectZh ?? tr('（暂未收录效果文本）'))
              : (card.effectJp ?? tr('（暂无原文）')),
          selfCode: card.code,
          selfSeries: card.series ?? '',
          style: TextStyle(
            height: 1.7,
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      if (state.useZh && (card.effectJp ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        _Section(
          title: tr('效果原文'),
          child: EffectText(
            text: card.effectJp!,
            selfCode: card.code,
            selfSeries: card.series ?? '',
            style: TextStyle(
              height: 1.6,
              fontSize: 12.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
      const SizedBox(height: 16),
      if (card.titleJp != null && card.titleJp!.isNotEmpty)
        _Section(title: tr('称号（原文）'), child: SelectableText(card.titleJp!)),
      const SizedBox(height: 16),
      _Section(
        title: tr('收录信息'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(tr('系列（作品）'), card.seriesName),
            _kv(tr('会社/品牌'), card.brandTag),
            if ((card.limit ?? '').isNotEmpty) _kv(tr('区域限制'), card.limit),
            _kv(tr('画家'), card.illustrator),
            _kv(tr('稀有度'), card.rarity),
            _kv(tr('初出'), card.releaseInfo),
          ],
        ),
      ),
      if (myNotes(state, card.code).isNotEmpty) ...[
        const SizedBox(height: 16),
        _Section(
          title: tr('我的心得'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in myNotes(state, card.code))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.sticky_note_2,
                        size: 15,
                        color: scheme.tertiary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.$2, style: const TextStyle(fontSize: 13)),
                            Text(
                              '记在构筑「${e.$1}」里'
                              '${e.$3 ? ' · MVP' : ''}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
      ...relatedBlocks(context, card.code),
      const SizedBox(height: 16),
      _Section(
        title: tr('我的记录'),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            state.isOwned(card.code)
                ? Icons.inventory_2
                : Icons.inventory_2_outlined,
          ),
          title: Text(state.isOwned(card.code) ? tr('已入库') : tr('未入库')),
          subtitle: Text(_ownedSummary(state, card.code)),
          trailing: TextButton.icon(
            onPressed: () => showOwnedInfoDialog(context, state, card.code),
            icon: const Icon(Icons.edit, size: 16),
            label: Text(tr('入库信息')),
          ),
        ),
      ),
      const SizedBox(height: 24),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.tonalIcon(
            onPressed: () => state.toggleOwned(card.code),
            icon: Icon(
              state.isOwned(card.code)
                  ? Icons.check_circle
                  : Icons.radio_button_unchecked,
            ),
            label: Text(state.isOwned(card.code) ? tr('已收集') : tr('标记为已收集')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => state.toggleFavorite(card.code),
            icon: Icon(
              state.isFavorite(card.code) ? Icons.star : Icons.star_border,
            ),
            label: Text(state.isFavorite(card.code) ? tr('已收藏') : tr('收藏')),
          ),
          FilledButton.icon(
            onPressed: () => _addToDeck(context, state, card),
            icon: const Icon(Icons.add),
            label: Text(tr('加入构筑')),
          ),
          FilledButton.tonalIcon(
            onPressed: () => quickAddSheet(context, state, [card]),
            icon: const Icon(Icons.exposure_plus_1),
            label: Text(tr('快速 +1/-1')),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final image = await CardSaver.instance.image(card.code);
              if (!context.mounted ||
                  !await confirmCardImageQuality(context, image.kind)) {
                return;
              }
              if (!await CardSaver.instance.hasAccess()) {
                await CardSaver.instance.requestAccess();
              }
              final ok = await CardSaver.instance.save(card.code);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(ok ? tr('已保存卡图到相册') : tr('保存失败'))),
              );
            },
            icon: const Icon(Icons.download),
            label: Text(tr('保存卡图')),
          ),
          OutlinedButton.icon(
            onPressed: () => _copy(context, card.displayName, tr('卡名已复制')),
            icon: const Icon(Icons.copy),
            label: Text(tr('复制卡名')),
          ),
          OutlinedButton.icon(
            onPressed: () =>
                _copy(context, CardRepository.exportText(card), tr('卡片信息已复制')),
            icon: const Icon(Icons.copy_all),
            label: Text(tr('复制信息')),
          ),
        ],
      ),
    ];

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(card.code),
        actions: [
          IconButton(
            tooltip: tr('编辑卡信息'),
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CardEditPage(code: card.code)),
            ),
          ),
          GlassMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CardEditPage(code: card.code),
                  ),
                );
              } else if (v == 'new') {
                showNewCardDialog(context, state);
              } else if (v == 'reset') {
                state.clearCardEdit(card.code);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(tr('已恢复成官方数据'))));
              }
            },
            items: [
              GlassMenuItem(
                'edit',
                tr('编辑卡信息 / 换卡面'),
                icon: Icons.edit_outlined,
              ),
              GlassMenuItem('new', tr('新建卡牌'), icon: Icons.add),
              if (state.cardEditOf(card.code) != null)
                GlassMenuItem('reset', tr('恢复成官方数据'), icon: Icons.restore),
            ],
          ),
        ],
      ),
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(16, 8, 8, 32),
                    child: art,
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 16, 32),
                    children: infoChildren,
                  ),
                ),
              ],
            )
          // 注意：千万别把 ListView 嵌进 ListView —— 内层拿到无界高度会直接炸，
          // 实机上的表现就是「详情页只剩卡图、一个字都不显示」。
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [art, ...infoChildren],
            ),
    );
  }

  Future<void> _addToDeck(
    BuildContext context,
    AppState state,
    LyceeCard card,
  ) async {
    if (state.decks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('先去「我的 → 构筑」建一套构筑'))));
      return;
    }
    final deck = await showGlassSheet<Deck>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(tr('加入哪套构筑？'))),
            for (final d in state.decks)
              ListTile(
                title: Text(d.name),
                subtitle: Text(tr('{0} 张', [d.total])),
                onTap: () => Navigator.pop(c, d),
              ),
          ],
        ),
      ),
    );
    if (deck == null) return;
    state.addCard(deck, card);
    Haptics.tap(state.haptics);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('已加入「{0}」', [deck.name]))));
    }
  }

  Widget _kv(String k, String? v) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text('$k：${(v == null || v.isEmpty) ? '—' : v}'),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Glass(
      child: Card(
        color: Colors.transparent,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.card});

  final LyceeCard card;

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      (tr('属性'), card.color ?? '—'),
      (tr('费用'), card.cost ?? '—'),
      if (card.ex != null) ('EX', '${card.ex}'),
      ('AP', card.ap?.toString() ?? '—'),
      ('DP', card.dp?.toString() ?? '—'),
      ('SP', card.sp?.toString() ?? '—'),
      ('DMG', card.dmg?.toString() ?? '—'),
      (tr('卡种'), card.kindZh == null ? '—' : tr(card.kindZh!)),
      (tr('类型'), card.cardType ?? '—'),
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [for (final (k, v) in items) LyInfoTile(label: k, value: v)],
    );
  }
}
