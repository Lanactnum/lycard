import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../state/app_state.dart';
import 'card_art.dart';
import 'card_route.dart';
import 'glass.dart';
import '../l10n/l10n.dart';

/// 剪贴板里发现的一串卡号 → 底部浮窗列出来（要求 L73）
Future<void> showCardCodesSheet(
  BuildContext context,
  AppState state,
  List<String> codes,
) async {
  final repo = CardRepository.instance;
  final found = <String, dynamic>{};
  for (final c in codes) {
    final card = repo.byCode(c);
    if (card != null) found[c] = card;
  }
  if (found.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('剪贴板里的卡号在卡池里都没找到'))));
    }
    return;
  }

  await showGlassSheet(
    context: context,
    showDragHandle: true,
    builder: (c) {
      final scheme = Theme.of(c).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.content_paste_go, size: 17, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(tr('剪贴板里的 {0} 张卡', [found.length]),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(tr('点一下看详情'),
                      style: TextStyle(
                          fontSize: 11.5, color: scheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 132,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: found.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final code = found.keys.elementAt(i);
                    final card = found[code];
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(c);
                        openCardDetail(context, code, scope: 'list');
                      },
                      child: SizedBox(
                        width: 92,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CardArt(card: card, showName: false),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              code,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10.5),
                            ),
                            Text(
                              '${card.nameZh ?? card.nameJp}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.playlist_add, size: 17),
                      label: Text(tr('全部加进想要')),
                      onPressed: () {
                        for (final code in found.keys) {
                          state.addWish(code);
                        }
                        Navigator.pop(c);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(tr('已加入 {0} 张到想要', [found.length]))));
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
