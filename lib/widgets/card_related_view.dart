import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_related.dart';
import '../models/lycee_card.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import 'card_route.dart';
import 'scatter.dart';
import '../l10n/l10n.dart';

/// 卡详情底部的两块内容：
/// 1) 我的心得（记在构筑里的单卡笔记 + MVP）
/// 2) 关联卡牌（按构筑分组：先「效果里提到」的，再按词条相似的）
///
/// 单独放一个文件，免得 card_detail_page.dart 太长。

/// (构筑名, 心得, 是否 MVP)
List<(String, String, bool)> myNotes(AppState state, String code) {
  final out = <(String, String, bool)>[];
  for (final d in state.decks) {
    final n = d.cardNotes[code] ?? '';
    final mvp = d.mvpCodes.contains(code);
    if (n.isEmpty && !mvp) continue;
    out.add((d.name, n.isEmpty ? tr('（已标记 MVP）') : n, mvp));
  }
  return out;
}

/// 把关联卡牌渲染成一串 widget（没有就返回空列表）
List<Widget> relatedBlocks(BuildContext context, String code) {
  final state = context.watch<AppState>();
  final groups = relatedGroups(code: code, decks: state.decks);
  if (groups.isEmpty) return const [];
  return [
    const SizedBox(height: 16),
    RelatedSection(groups: groups),
  ];
}

class RelatedSection extends StatelessWidget {
  const RelatedSection({super.key, required this.groups});

  final List<RelatedGroup> groups;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(tr('关联卡牌'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary)),
            ],
          ),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(g.deckName,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
            for (final it in g.items) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text(it.label,
                    style: TextStyle(
                        fontSize: 11.5, color: scheme.onSurfaceVariant)),
              ),
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: it.cards.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (c, i) => ScatterItem(
                    index: i,
                    strength: 0.5,
                    code: it.cards[i].code,
                    child: _MiniCard(card: it.cards[i]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.card});

  final LyceeCard card;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${card.displayName}\n${card.code}',
      child: InkWell(
        onTap: () => openCardDetail(context, card.code, scope: 'list'),
        child: SizedBox(
          width: 56,
          child: Column(
            children: [
              Expanded(child: CardHero(code: card.code, child: CardArt(card: card))),
              const SizedBox(height: 2),
              Text(
                card.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
