import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../state/app_state.dart';
import '../models/lycee_card.dart';
import '../l10n/l10n.dart';

/// 构筑统计图（只统计主卡区）：属性 / 费用 / 卡种
/// 拖拽或增删卡时会跟着实时更新。
class DeckStats extends StatelessWidget {
  const DeckStats({super.key, required this.deck});

  final Deck deck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = CardRepository.instance;

    final colors = <String, int>{};
    final costs = <String, int>{};
    final kinds = <String, int>{};

    var total = 0;
    deck.cards.forEach((code, n) {
      final c = repo.byCode(code);
      if (c == null) return;
      total += n;
      if ((c.color ?? '').isNotEmpty) {
        colors[c.color!] = (colors[c.color!] ?? 0) + n;
      }
      final cost = (c.cost ?? '').trim();
      if (cost.isNotEmpty) {
        costs[cost] = (costs[cost] ?? 0) + n;
      }
      final kindZh = kKindZh(c.kind);
      if ((kindZh ?? '').isNotEmpty) {
        kinds[kindZh!] = (kinds[kindZh] ?? 0) + n;
      }
    });

    List<MapEntry<String, int>> rank(Map<String, int> m) =>
        (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('统计（主卡区 {0} 张）', [total]),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _Group(title: tr('属性'), rows: rank(colors), total: total),
          const SizedBox(height: 8),
          _Group(title: tr('费用'), rows: rank(costs), total: total),
          const SizedBox(height: 8),
          _Group(title: tr('卡种'), rows: rank(kinds), total: total),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.rows, required this.total});

  final String title;
  final List<MapEntry<String, int>> rows;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Text('—',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant))
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in rows)
                _Bar(label: tr(e.key), n: e.value, total: total),
            ],
          ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.label, required this.n, required this.total});

  final String label;
  final int n;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = total == 0 ? 0.0 : n / total;
    return SizedBox(
      width: 56,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: scheme.onSurface),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
