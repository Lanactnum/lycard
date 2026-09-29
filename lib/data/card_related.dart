import '../models/lycee_card.dart';
import '../state/app_state.dart';
import 'card_repository.dart';
import 'keyword_db.dart';
import '../l10n/l10n.dart';

/// 关联卡牌里的一个小分组（同一个构筑内）
class RelatedItem {
  RelatedItem(this.label, this.cards);

  /// 比如「关联（效果里提到）」或「相似-跳跃」
  final String label;
  final List<LyceeCard> cards;
}

/// 某个构筑下的关联推荐
class RelatedGroup {
  RelatedGroup(this.deckName, this.items);

  final String deckName;
  final List<RelatedItem> items;
}

String _textOf(LyceeCard c) => '${c.effectZh ?? ''} ${c.effectJp ?? ''}';

/// 算「关联卡牌」推荐栏：
/// 对每一套包含这张卡的构筑，先给「效果里互相提到名字」的卡，
/// 再按词条（跳跃 / 诱发 …）给相似卡。
///
/// 返回顺序就是界面上的显示顺序：构筑1 → 构筑2 …
List<RelatedGroup> relatedGroups({
  required String code,
  required List<Deck> decks,
  CardRepository? repo,
  KeywordDb? kwdb,
}) {
  final r = repo ?? CardRepository.instance;
  final kd = kwdb ?? KeywordDb.instance;
  final me = r.byCode(code);
  if (me == null) return const [];

  final myText = _textOf(me);
  final myNames = <String>{
    if (me.displayName.isNotEmpty) me.displayName,
    if (me.nameJp.isNotEmpty) me.nameJp,
    if ((me.nameZh ?? '').isNotEmpty) me.nameZh!,
  };
  final myKw = kd.scan(myText).map((e) => e.$3.zh).toSet();

  final out = <RelatedGroup>[];
  for (final d in decks) {
    if (!d.cards.containsKey(code)) continue;
    final others = d.cards.keys
        .where((k) => k != code)
        .map(r.byCode)
        .whereType<LyceeCard>()
        .toList();
    if (others.isEmpty) continue;

    final items = <RelatedItem>[];

    // 1) 关联：两边效果文本里互相出现了对方的名字
    final byName = others.where((c) {
      final names = <String>{
        if (c.displayName.isNotEmpty) c.displayName,
        if (c.nameJp.isNotEmpty) c.nameJp,
        if ((c.nameZh ?? '').isNotEmpty) c.nameZh!,
      };
      final hitMine = names.any((n) => n.length >= 2 && myText.contains(n));
      final ct = _textOf(c);
      final hitHis = myNames.any((n) => n.length >= 2 && ct.contains(n));
      return hitMine || hitHis;
    }).toList();
    if (byName.isNotEmpty) {
      items.add(RelatedItem(tr('关联'), byName));
    }

    // 2) 相似：同词条（跳过已经在「关联」里出现过的）
    for (final k in myKw) {
      final same = others
          .where((c) => !byName.contains(c) && _textOf(c).contains(k))
          .toList();
      if (same.isNotEmpty) items.add(RelatedItem(tr('相似-{0}', [k]), same));
    }

    if (items.isNotEmpty) out.add(RelatedGroup(d.name, items));
  }
  return out;
}
