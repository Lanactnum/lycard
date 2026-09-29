import 'package:flutter/material.dart';

import '../data/storage_manager.dart';
import '../widgets/glass.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 设置 →「存储与清理」：分类清理 App 自己产生的额外数据
/// 删掉的东西先进垃圾桶，15 天内可以撤销。
class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  List<CleanCategory> _cats = const [];
  final Set<String> _picked = {};
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final cats = await StorageManager.instance.scan();
    if (!mounted) return;
    setState(() {
      _cats = cats;
      _picked.removeWhere((id) => !cats.any((c) => c.id == id));
      _loading = false;
    });
  }

  int get _pickedBytes => _cats
      .where((c) => _picked.contains(c.id))
      .fold(0, (a, c) => a + c.bytes);

  Future<void> _clean() async {
    if (_picked.isEmpty) return;
    setState(() => _busy = true);
    final bytes = await StorageManager.instance.clean(_picked.toList());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _picked.clear();
    });
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr('已清理 {0}，保留 15 天', [humanSize(bytes)])),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _cats.fold<int>(0, (a, c) => a + c.bytes);

    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(tr('存储与清理')),
        actions: [
          IconButton(
            tooltip: tr('垃圾桶'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TrashPage()))
                .then((_) => _reload()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Row(
                    children: [
                      Icon(Icons.sd_storage, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('App 额外数据合计 {0}', [humanSize(total)]),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(
                              tr('只清理数据，不删除构筑/收藏/设置'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                for (final c in _cats)
                  CheckboxListTile(
                    value: _picked.contains(c.id),
                    onChanged: c.isEmpty
                        ? null
                        : (v) => setState(() {
                              v == true
                                  ? _picked.add(c.id)
                                  : _picked.remove(c.id);
                            }),
                    title: Row(
                      children: [
                        Expanded(child: Text(c.label)),
                        Text(c.sizeText,
                            style: TextStyle(
                                fontSize: 13, color: scheme.primary)),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        c.isEmpty
                            ? tr('{0}（空）', [c.desc])
                            : tr('{0}\\n{1} 个文件', [c.desc, c.count]),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(tr('重新扫描')),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _picked.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _busy ? null : _clean,
                  icon: const Icon(Icons.cleaning_services),
                  label: Text(tr('清理选中 {0} 项（{1}）', [_picked.length, humanSize(_pickedBytes)])),
                ),
              ),
            ),
    );
  }
}

/// 垃圾桶：15 天内可撤销
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<TrashEntry> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final t = await StorageManager.instance.trash();
    if (!mounted) return;
    setState(() {
      _items = t;
      _loading = false;
    });
  }

  Future<void> _restore(TrashEntry e) async {
    final ok = await StorageManager.instance.restore(e.id);
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? tr('已撤销：{0}', [e.label]) : tr('撤销失败，部分文件可能被占用'))),
    );
  }

  Future<void> _purge(TrashEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('彻底删除？')),
        content: Text(tr('「{0}」将被永久销毁，无法再撤销。', [e.label])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false), child: Text(tr('算了'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: Text(tr('删除'))),
        ],
      ),
    );
    if (ok != true) return;
    await StorageManager.instance.purge(e.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(
        title: Text(tr('垃圾桶')),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(tr('清空垃圾桶？')),
                    content: Text(tr('将被永久销毁，无法撤销。')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(tr('算了'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(tr('清空'))),
                    ],
                  ),
                );
                if (ok == true) {
                  await StorageManager.instance.emptyTrash();
                  await _reload();
                }
              },
              child: Text(tr('清空')),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      tr('垃圾桶是空的。\\n清理掉的数据会先放在这里，保留 15 天。'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.6),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final e = _items[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            e.expired ? scheme.errorContainer : scheme.primaryContainer,
                        child: Text(tr('{0}天', [e.daysLeft.clamp(0, 99)]),
                            style: const TextStyle(fontSize: 11)),
                      ),
                      title: Text(e.label),
                      subtitle: Text(
                        '${e.fileCount} 个文件 · ${e.sizeText}\n'
                        '删除于 ${_fmt(e.deletedAt)}'
                        '${e.expired ? ' · 已过期' : ' · 还有 ${e.daysLeft} 天'}',
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: tr('撤销'),
                            icon: const Icon(Icons.undo),
                            onPressed: e.expired ? null : () => _restore(e),
                          ),
                          IconButton(
                            tooltip: tr('彻底删除'),
                            icon: const Icon(Icons.delete_forever),
                            onPressed: () => _purge(e),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${_two(d.month)}-${_two(d.day)} ${_two(d.hour)}:${_two(d.minute)}';

  static String _two(int n) => n < 10 ? '0$n' : '$n';
}
