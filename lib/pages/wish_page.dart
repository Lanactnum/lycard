import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../data/storage_manager.dart';
import '../models/wish_card.dart';
import '../state/app_state.dart';
import '../widgets/card_art.dart';
import '../widgets/card_route.dart';
import '../widgets/scatter.dart';
import '../widgets/glass.dart';
import '../widgets/tags.dart';
import '../widgets/layout.dart';
import '../widgets/glass_menu.dart';
import '../l10n/l10n.dart';

/// 我的 →「想要 / 出卡」：两个分页，可以记品相、价格、实拍图
class WishPage extends StatelessWidget {
  const WishPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: tr('想要')),
              Tab(text: tr('出卡')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _WishList(kind: WishKind.want),
                _WishList(kind: WishKind.sell),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WishList extends StatelessWidget {
  const _WishList({required this.kind});

  final WishKind kind;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final items = kind == WishKind.want ? state.wantList : state.sellList;
    final isWant = kind == WishKind.want;

    // 价格合计
    final priced = items.where((w) => w.price != null).toList();
    final sum = priced.fold<double>(0, (a, w) => a + (w.price ?? 0));
    final allPriced = priced.length == items.length;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Row(
                    children: [
                      Icon(
                        isWant ? Icons.favorite_border : Icons.sell_outlined,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isWant
                                  ? tr('想要 {0} 张', [items.length])
                                  : tr('出卡 {0} 张', [items.length]),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              items.isEmpty
                                  ? (isWant
                                        ? tr('想买的卡放这里，可记录品相和价格')
                                        : tr('想出的卡放这里，可记录品相和价格'))
                                  : '${isWant ? '预计补齐' : '标价合计'} '
                                        '${allPriced ? '¥${sum.toStringAsFixed(2)}' : '- （还有 ${items.length - priced.length} 张未填价）'}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (items.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    isWant ? tr('还没有想要的卡\\n') : tr('还没有要出的卡'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.7,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: kBottomBarSpace),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) => ScatterItem(
                    index: i,
                    strength: 0.6,
                    code: items[i].code,
                    child: _WishTile(wish: items[i]),
                  ),
                ),
              ),
          ],
        ),
        Positioned(
          right: 16,
          // 让开悬浮底栏：以前是 16，正好被底栏压住
          bottom: kBottomBarHeight,
          child: FloatingActionButton.extended(
            heroTag: 'add-${kind.name}',
            onPressed: () => _addFlow(context, kind),
            icon: const Icon(Icons.add),
            label: Text(tr('添加')),
          ),
        ),
      ],
    );
  }
}

class _WishTile extends StatelessWidget {
  const _WishTile({required this.wish});

  final WishCard wish;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final card = CardRepository.instance.byCode(wish.code);

    return InkWell(
      onTap: () => _editSheet(context, state, wish),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 56,
              child: card == null
                  ? const Icon(Icons.help_outline)
                  : CardHero(
                      code: card.code,
                      child: CardArt(card: card, showName: false),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card?.displayName ?? wish.code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${wish.code} · ${card?.color ?? ''}',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (wish.condition.isNotEmpty)
                        _pill(tr('品相 {0}', [wish.condition]), scheme.primary),
                      for (final t in wish.tags) _pill(t, scheme.tertiary),
                      _pill(
                        wish.price == null
                            ? tr('价格 -')
                            : '${wish.currency} ${wish.price!.toStringAsFixed(2)}',
                        scheme.secondary,
                      ),
                    ],
                  ),
                  if (wish.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        wish.note,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  if (wish.photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SizedBox(
                        height: 46,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: wish.photos.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 6),
                          itemBuilder: (c, i) => _PhotoThumb(
                            name: wish.photos[i],
                            size: 46,
                            onTap: () =>
                                _savePhotoToGallery(context, wish.photos[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            GlassMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') {
                  _editSheet(context, state, wish);
                } else if (v == 'want') {
                  openCardDetail(context, wish.code, scope: 'list');
                } else if (v == 'del') {
                  state.removeWish(wish.id);
                }
              },
              items: [
                GlassMenuItem('edit', tr('编辑'), icon: Icons.edit_outlined),
                GlassMenuItem(
                  'want',
                  tr('看卡详情'),
                  icon: Icons.visibility_outlined,
                ),
                GlassMenuItem(
                  'del',
                  tr('删除'),
                  icon: Icons.delete_outline,
                  danger: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(text, style: TextStyle(fontSize: 11, color: c)),
  );
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.name, required this.size, this.onTap});

  final String name;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: StorageManager.instance.photoPath(name),
      builder: (c, s) {
        final p = s.data;
        return InkWell(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: p == null
                ? const Icon(Icons.broken_image, size: 18)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(File(p), fit: BoxFit.cover),
                  ),
          ),
        );
      },
    );
  }
}

/// 把实拍图另存到相册
Future<void> _savePhotoToGallery(BuildContext context, String name) async {
  final p = await StorageManager.instance.photoPath(name);
  if (p == null) return;
  if (!context.mounted) return;
  try {
    await Gal.putImage(p);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('实拍图已保存到相册'))));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('保存失败：{0}', [e]))));
    }
  }
}

// ---------------------------------------------------------------- 添加流程

Future<void> _addFlow(BuildContext context, WishKind kind) async {
  final code = await showGlassSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _CardPickSheet(),
  );
  if (code == null || !context.mounted) return;
  final state = context.read<AppState>();
  final w = state.addWish(code, kind: kind);
  await _editSheet(context, state, w);
}

class _CardPickSheet extends StatefulWidget {
  const _CardPickSheet();

  @override
  State<_CardPickSheet> createState() => _CardPickSheetState();
}

class _CardPickSheetState extends State<_CardPickSheet> {
  final _ctrl = TextEditingController();
  List<dynamic> _res = const [];

  void _run(String q) {
    setState(() {
      _res = q.trim().isEmpty
          ? const []
          : CardRepository.instance.query(q, null, cap: 30);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 14,
        right: 14,
        top: 14,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('搜卡名 / 卡号…'),
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _run,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _res.isEmpty
                  ? Center(
                      child: Text(
                        tr('输入卡名或卡号'),
                        style: TextStyle(fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _res.length,
                      itemBuilder: (c, i) {
                        final card = _res[i];
                        return ListTile(
                          dense: true,
                          title: Text(
                            card.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('${card.code} · ${card.color ?? ''}'),
                          onTap: () =>
                              Navigator.pop(context, card.code as String),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 编辑面板

Future<void> _editSheet(
  BuildContext context,
  AppState state,
  WishCard w,
) async {
  await showGlassSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _WishEditSheet(state: state, wish: w),
  );
}

class _WishEditSheet extends StatefulWidget {
  const _WishEditSheet({required this.state, required this.wish});

  final AppState state;
  final WishCard wish;

  @override
  State<_WishEditSheet> createState() => _WishEditSheetState();
}

class _WishEditSheetState extends State<_WishEditSheet> {
  late final WishCard w = widget.wish;
  late final TextEditingController _price = TextEditingController(
    text: w.price?.toString() ?? '',
  );
  late final TextEditingController _note = TextEditingController(text: w.note);
  final _newTag = TextEditingController();
  final _newCond = TextEditingController();

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    _newTag.dispose();
    _newCond.dispose();
    super.dispose();
  }

  void _save() {
    w.price = double.tryParse(_price.text.trim());
    w.note = _note.text.trim();
    widget.state.updateWish(w);
  }

  Future<void> _addPhoto() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = res?.files.single;
    if (f == null) return;
    final bytes =
        f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
    if (bytes == null) return;
    final ext = (f.extension ?? 'jpg').toLowerCase();
    final name = await StorageManager.instance.savePhoto(bytes, ext);
    if (name == null || !mounted) return;
    setState(() => w.photos.add(name));
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = CardRepository.instance.byCode(w.code);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (card != null)
                  SizedBox(
                    width: 46,
                    child: CardHero(
                      code: card.code,
                      scope: 'wishpick',
                      child: CardArt(card: card, showName: false),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card?.displayName ?? w.code,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${w.code} · ${wishKindName(w.kind)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 22),
            Text(tr('品相'), style: _label(scheme)),
            Wrap(
              spacing: 8,
              children: [
                for (final c in kConditionPresets)
                  LyTag(
                    label: c,
                    dense: true,
                    selected: w.condition == c,
                    onTap: () => setState(() {
                      w.condition = w.condition == c ? '' : c;
                      _save();
                    }),
                  ),
                LyTag(
                  icon: Icons.edit,
                  dense: true,
                  label:
                      w.condition.isEmpty ||
                          kConditionPresets.contains(w.condition)
                      ? tr('自定义')
                      : w.condition,
                  onTap: () async {
                    final t = await _askText(context, tr('自定义品相'), _newCond);
                    if (t != null && t.isNotEmpty) {
                      setState(() => w.condition = t);
                      _save();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(tr('细化标签'), style: _label(scheme)),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in {...kTagSuggestions, ...w.tags})
                  LyTag(
                    label: t,
                    dense: true,
                    selected: w.tags.contains(t),
                    onTap: () => setState(() {
                      w.tags.contains(t) ? w.tags.remove(t) : w.tags.add(t);
                      _save();
                    }),
                  ),
                LyTag(
                  icon: Icons.add,
                  dense: true,
                  label: tr('加标签'),
                  onTap: () async {
                    final t = await _askText(context, tr('自定义标签'), _newTag);
                    if (t != null && t.isNotEmpty) {
                      setState(() => w.tags.add(t));
                      _save();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(tr('价格'), style: _label(scheme)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      hintText: tr('未填写则显示 -'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: w.currency,
                  items: [
                    for (final c in AppState.currencySymbols.keys)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() {
                    w.currency = v ?? 'CNY';
                    _save();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(tr('实拍图'), style: _label(scheme)),
            SizedBox(
              height: 66,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final p in w.photos)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          _PhotoThumb(
                            name: p,
                            size: 64,
                            onTap: () => _savePhotoToGallery(context, p),
                          ),
                          Positioned(
                            right: -6,
                            top: -6,
                            child: IconButton(
                              iconSize: 18,
                              icon: const Icon(Icons.cancel),
                              onPressed: () => setState(() {
                                w.photos.remove(p);
                                _save();
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  LyTag(
                    icon: Icons.add_a_photo,
                    dense: true,
                    label: tr('加实拍图'),
                    onTap: _addPhoto,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('点实拍图可以另存到相册'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(tr('备注'), style: _label(scheme)),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: tr('比如：只出给同城/面交'),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _save(),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      _save();
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.check),
                    label: Text(tr('保存')),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () {
                    widget.state.removeWish(w.id);
                    Navigator.pop(context);
                  },
                  child: Text(tr('删除')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _label(ColorScheme s) =>
      TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: s.primary);
}

Future<String?> _askText(
  BuildContext context,
  String title,
  TextEditingController ctrl,
) async {
  ctrl.clear();
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (v) => Navigator.pop(c, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('取消'))),
        FilledButton(
          onPressed: () => Navigator.pop(c, ctrl.text.trim()),
          child: Text(tr('确定')),
        ),
      ],
    ),
  );
}
