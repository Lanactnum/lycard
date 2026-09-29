import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../data/storage_manager.dart';
import '../models/card_edit.dart';
import '../state/app_state.dart';
import '../widgets/glass.dart';
import '../widgets/tags.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 编辑一张卡的信息（改错的字段 / 换卡面 / 归类），也能新建卡
class CardEditPage extends StatefulWidget {
  const CardEditPage({super.key, required this.code, this.isNewCard = false});

  final String code;
  final bool isNewCard;

  @override
  State<CardEditPage> createState() => _CardEditPageState();
}

class _CardEditPageState extends State<CardEditPage> {
  late final AppState state = context.read<AppState>();
  late CardOverride e;
  late final bool isNew;

  final _nameZh = TextEditingController();
  final _nameJp = TextEditingController();
  final _effect = TextEditingController();
  final _color = TextEditingController();
  final _cost = TextEditingController();
  final _ex = TextEditingController();
  final _ap = TextEditingController();
  final _dp = TextEditingController();
  final _sp = TextEditingController();
  final _dmg = TextEditingController();
  final _kind = TextEditingController();
  final _type = TextEditingController();
  final _series = TextEditingController();
  final _illust = TextEditingController();
  final _rarity = TextEditingController();

  @override
  void initState() {
    super.initState();
    final card = CardRepository.instance.byCode(widget.code);
    isNew = widget.isNewCard || (state.cardEditOf(widget.code)?.isNew ?? false);
    e = state.cardEditOf(widget.code) ?? CardOverride(code: widget.code);

    _nameZh.text = e.nameZh ?? card?.nameZh ?? '';
    _nameJp.text = e.nameJp ?? card?.nameJp ?? '';
    _effect.text = e.effectZh ?? card?.effectZh ?? '';
    _color.text = e.color ?? card?.color ?? '';
    _cost.text = e.cost ?? card?.cost ?? '';
    _ex.text = '${e.ex ?? card?.ex ?? ''}';
    _ap.text = '${e.ap ?? card?.ap ?? ''}';
    _dp.text = '${e.dp ?? card?.dp ?? ''}';
    _sp.text = '${e.sp ?? card?.sp ?? ''}';
    _dmg.text = '${e.dmg ?? card?.dmg ?? ''}';
    _kind.text = e.kind ?? card?.kind ?? '';
    _type.text = e.cardType ?? card?.cardType ?? '';
    _series.text = e.series ?? card?.series ?? '';
    _illust.text = e.illust ?? card?.illustrator ?? '';
    _rarity.text = e.rarity ?? card?.rarity ?? '';
  }

  @override
  void dispose() {
    for (final c in [
      _nameZh, _nameJp, _effect, _color, _cost, _ex, _ap, _dp, _sp, _dmg,
      _kind, _type, _series, _illust, _rarity,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _num(TextEditingController c) => int.tryParse(c.text.trim());

  void _save() {
    e
      ..nameZh = _nameZh.text.trim()
      ..nameJp = _nameJp.text.trim()
      ..effectZh = _effect.text.trim()
      ..color = _color.text.trim()
      ..cost = _cost.text.trim()
      ..ex = _num(_ex)
      ..ap = _num(_ap)
      ..dp = _num(_dp)
      ..sp = _num(_sp)
      ..dmg = _num(_dmg)
      ..kind = _kind.text.trim()
      ..cardType = _type.text.trim()
      ..series = _series.text.trim()
      ..illust = _illust.text.trim()
      ..rarity = _rarity.text.trim();
    state.setCardEdit(e);
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final f = res?.files.single;
    if (f == null) return;
    final bytes =
        f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
    if (bytes == null) return;
    final name = await StorageManager.instance
        .saveCardImage(bytes, (f.extension ?? 'jpg').toLowerCase());
    if (name == null || !mounted) return;
    setState(() => e.imageFile = name);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final allCats = state.categories;

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(isNew ? tr('新建卡牌') : tr('编辑卡信息')),
        actions: [
          TextButton(
            onPressed: () {
              _save();
              Navigator.pop(context);
            },
            child: Text(tr('保存')),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (!isNew)
            Text(tr('卡号 {0}（卡号不能改）', [widget.code]),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          _field(tr('中文名'), _nameZh),
          _field(tr('日文原名'), _nameJp),
          _field(tr('效果'), _effect, lines: 4),
          Row(children: [
            Expanded(child: _field(tr('属性'), _color)),
            const SizedBox(width: 10),
            Expanded(child: _field(tr('费用（符号串，如 花花）'), _cost)),
          ]),
          Row(children: [
            Expanded(child: _field('EX', _ex, num: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('AP', _ap, num: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('DP', _dp, num: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('SP', _sp, num: true)),
            const SizedBox(width: 8),
            Expanded(child: _field('DMG', _dmg, num: true)),
          ]),
          Row(children: [
            Expanded(child: _field(tr('卡种（角色/事件/道具/区域）'), _kind)),
            const SizedBox(width: 10),
            Expanded(child: _field(tr('类型'), _type)),
          ]),
          Row(children: [
            Expanded(child: _field(tr('作品'), _series)),
            const SizedBox(width: 10),
            Expanded(child: _field(tr('画师'), _illust)),
          ]),
          _field(tr('罕贵度'), _rarity),
          const Divider(height: 26),
          Text(tr('卡面'), style: _label(scheme)),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(e.imageFile == null ? tr('换一张卡面') : tr('已换（再选几张）')),
              ),
              const SizedBox(width: 10),
              if (e.imageFile != null)
                TextButton(
                  onPressed: () {
                    setState(() => e.imageFile = null);
                    _save();
                  },
                  child: Text(tr('恢复官方卡图')),
                ),
            ],
          ),
          const Divider(height: 26),
          Text(tr('分类'), style: _label(scheme)),
          const SizedBox(height: 4),
          Text(tr('自建分类'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in allCats)
                LyTag(
                  label: c,
                  dense: true,
                  selected: e.categories.contains(c),
                  onTap: () {
                    setState(() => e.categories.contains(c)
                        ? e.categories.remove(c)
                        : e.categories.add(c));
                    _save();
                  },
                ),
              LyTag(
                icon: Icons.add,
                label: tr('新建分类'),
                dense: true,
                onTap: () async {
                  final ctrl = TextEditingController();
                  final t = await showDialog<String>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: Text(tr('新建分类')),
                      content: TextField(
                        controller: ctrl,
                        autofocus: true,
                        decoration:
                            const InputDecoration(border: OutlineInputBorder()),
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: Text(tr('取消'))),
                        FilledButton(
                            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
                            child: const Text('建')),
                      ],
                    ),
                  );
                  if (t != null && t.isNotEmpty) {
                    setState(() => e.categories.add(t));
                    _save();
                  }
                },
              ),
            ],
          ),
          const Divider(height: 26),
          if (!isNew)
            OutlinedButton.icon(
              onPressed: () {
                state.clearCardEdit(widget.code);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.restore),
              label: Text(tr('恢复成官方数据')),
            ),
          if (isNew)
            OutlinedButton.icon(
              onPressed: () {
                state.clearCardEdit(widget.code);
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
              label: Text(tr('删除这张自定义卡')),
            ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c,
          {int lines = 1, bool num = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: TextField(
          controller: c,
          maxLines: lines,
          keyboardType: num ? TextInputType.number : null,
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => _save(),
        ),
      );

  TextStyle _label(ColorScheme s) => TextStyle(
      fontSize: 13, fontWeight: FontWeight.w700, color: s.primary);
}

/// 新建一张卡：先要一个卡号 + 名字
Future<void> showNewCardDialog(BuildContext context, AppState state) async {
  final code = TextEditingController();
  final name = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('新建卡牌')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: code,
            decoration: InputDecoration(
              labelText: tr('卡号'),
              hintText: tr('如 MY-0001'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: name,
            decoration: InputDecoration(
              labelText: tr('卡名'),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
        FilledButton(
            onPressed: () => Navigator.pop(c, true), child: Text(tr('创建'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final c = code.text.trim();
  if (c.isEmpty) return;
  if (CardRepository.instance.byCode(c) != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('这个卡号已经存在了'))));
    return;
  }
  state.createCustomCard(c, name.text.trim());
  if (!context.mounted) return;
  await Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => CardEditPage(code: c, isNewCard: true)));
}
