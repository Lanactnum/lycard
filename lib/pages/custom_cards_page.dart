import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../models/card_edit.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import 'card_edit_page.dart';
import '../widgets/glass.dart';
import '../widgets/card_route.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/glass_menu.dart';
import '../l10n/l10n.dart';

/// 设置 →「自定义卡牌」：改过的卡 / 新建的卡 / 分类编辑
class CustomCardsPage extends StatelessWidget {
  const CustomCardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final edits = state.cardEdits.values.toList()
      ..sort((a, b) => a.code.compareTo(b.code));
    final cats = state.categories;

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(tr('自定义卡牌')),
        actions: [
          IconButton(
            tooltip: tr('新建卡牌'),
            icon: const Icon(Icons.add),
            onPressed: () => showNewCardDialog(context, state),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              tr('已修改卡 {0} 张 · 自建卡 {1} 张 · 分类 {2} 个', [edits.where((e) => !e.isNew).length, edits.where((e) => e.isNew).length, cats.length]),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const Divider(height: 18),
          _Header(tr('我的分类')),
          if (cats.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Text(tr('还没有分类。在「编辑卡信息」中新建分类。'),
                  style: TextStyle(fontSize: 12)),
            )
          else
            for (final c in cats)
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_outlined),
                title: Text(c),
                subtitle: Text(
                    tr('{0} 张卡', [edits.where((e) => e.categories.contains(c)).length]),
                    style: const TextStyle(fontSize: 11)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: tr('改名'),
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () async {
                        final ctrl = TextEditingController(text: c);
                        final t = await showDialog<String>(
                          context: context,
                          builder: (cc) => AlertDialog(
                            title: Text(tr('改分类名')),
                            content: TextField(
                              controller: ctrl,
                              autofocus: true,
                              decoration: const InputDecoration(
                                  border: OutlineInputBorder()),
                            ),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(cc),
                                  child: Text(tr('取消'))),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(cc, ctrl.text.trim()),
                                  child: Text(tr('保存'))),
                            ],
                          ),
                        );
                        if (t != null && t.isNotEmpty) {
                          state.renameCategory(c, t);
                        }
                      },
                    ),
                    IconButton(
                      tooltip: tr('删除分类'),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (cc) => AlertDialog(
                            title: Text(tr('删掉分类「{0}」？', [c])),
                            content: Text(tr('卡本身不会被删除，仅移出分类。')),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(cc, false),
                                  child: Text(tr('算了'))),
                              FilledButton(
                                  onPressed: () => Navigator.pop(cc, true),
                                  child: Text(tr('删除'))),
                            ],
                          ),
                        );
                        if (ok == true) state.deleteCategory(c);
                      },
                    ),
                  ],
                ),
              ),
          const Divider(height: 18),
          _Header(tr('已修改/新建卡')),
          if (edits.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Text(tr('无。在卡详情页右上角「⋮ → 编辑卡信息」可修改。'),
                  style: TextStyle(fontSize: 12)),
            )
          else
            for (final CardOverride e in edits)
              _EditTile(e: e),
        ],
      ),
    );
  }
}

class _EditTile extends StatelessWidget {
  const _EditTile({required this.e});

  final CardOverride e;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final card = CardRepository.instance.byCode(e.code);
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: SizedBox(
        width: 40,
        child: card == null
            ? const Icon(Icons.help_outline)
            : CardHero(
                code: card.code,
                child: CardArt(card: card, showName: false),
              ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(card?.displayName ?? e.code,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (e.isNew)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tr('自建'), style: TextStyle(fontSize: 9)),
              ),
            ),
        ],
      ),
      subtitle: Text(
        [
          e.code,
          if (e.nameZh != null) tr('名字已改'),
          if (e.effectZh != null) tr('效果已改'),
          if (e.imageFile != null) tr('卡面已换'),
          if (e.categories.isNotEmpty) '分类：${e.categories.join('、')}',
        ].join(' · '),
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => CardEditPage(code: e.code))),
      trailing: GlassMenuButton<String>(
        onSelected: (v) {
          if (v == 'view') {
            openCardDetail(context, e.code, scope: 'list');
          } else if (v == 'reset') {
            state.clearCardEdit(e.code);
          }
        },
        items: [
          GlassMenuItem('view', tr('看卡详情'), icon: Icons.visibility_outlined),
          GlassMenuItem('reset', e.isNew ? tr('删除这张卡') : tr('恢复官方数据'),
              icon: e.isNew ? Icons.delete_outline : Icons.restore,
              danger: e.isNew),
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
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );
}
