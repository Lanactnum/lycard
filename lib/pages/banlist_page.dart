import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../data/banlist.dart';
import '../data/card_repository.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/card_route.dart';
import '../widgets/glass.dart';
import '../widgets/layout.dart';
import '../widgets/tags.dart';

/// 禁限卡表（要求 L83-84）。
///
/// 官方表随包打包，离线可用；这里能看到全部限制卡、自定义追加限制，
/// 也能联网从官方页面更新（直连即可，不需要代理）。
class BanListPage extends StatefulWidget {
  const BanListPage({super.key});

  @override
  State<BanListPage> createState() => _BanListPageState();
}

class _BanListPageState extends State<BanListPage> {
  bool _updating = false;
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final ban = BanList.instance;
    final repo = CardRepository.instance;

    return BgScaffold(
      appBar: GlassAppBar(
        title: Text(tr('禁限卡表')),
        actions: [
          IconButton(
            tooltip: tr('从官方更新'),
            icon: _updating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            onPressed: _updating ? null : () => _update(context, state),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kBottomBarSpace),
        children: [
          _Head(tr('官方限制 · {0}',
              [ban.updatedAt.isEmpty ? tr('未知日期') : ban.updatedAt])),
          ListTile(
            dense: true,
            title: Text(ban.summary, style: const TextStyle(fontSize: 12)),
            subtitle: Text(tr('随 App 打包，离线可用'),
                style: const TextStyle(fontSize: 11)),
          ),
          const Divider(),
          _tabs(),
          if (_tab == 0) ..._forbiddenSection(repo, ban),
          if (_tab == 1) ..._constructionSection(repo, ban),
          if (_tab == 2) ..._copyLimitSection(ban),
          if (_tab == 3) ..._customSection(context, state, repo, ban),
          if (ban.history.isNotEmpty) ...[
            const Divider(),
            _Head(tr('官方更新履历')),
            for (final h in ban.history.take(8))
              ListTile(
                dense: true,
                title: Text(h['date'] ?? '',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                subtitle: Text(h['text'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _tabs() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
        child: Wrap(
          spacing: 6,
          children: [
            for (final (i, label) in [
              (0, tr('使用禁止')),
              (1, tr('构筑限制')),
              (2, tr('张数限制')),
              (3, tr('自定义')),
            ])
              LyTag(
                label: label,
                dense: true,
                selected: _tab == i,
                onTap: () => setState(() => _tab = i),
              ),
          ],
        ),
      );

  List<Widget> _forbiddenSection(CardRepository repo, BanList ban) {
    final all = {...ban.forbidden, ...ban.customForbidden}.toList()..sort();
    if (all.isEmpty) return [_empty(tr('官方目前没有禁用卡'))];
    return [
      _hint(tr('这些卡任何卡组都不能放入')),
      for (final code in all) _cardTile(repo, code, trailing: tr('禁止')),
    ];
  }

  List<Widget> _constructionSection(CardRepository repo, BanList ban) {
    final all = ban.constructionLimited.toList()..sort();
    if (all.isEmpty) return [_empty(tr('官方目前没有构筑限制卡'))];
    return [
      _hint(tr('这些卡只能用在单一会社构成的卡组里；混会社就会报错')),
      for (final code in all)
        _cardTile(repo, code, trailing: tr('限单一会社')),
    ];
  }

  List<Widget> _copyLimitSection(BanList ban) {
    final all = ban.allCopyLimited;
    if (all.isEmpty) {
      return [_empty(tr('官方目前没有张数限制卡（写的是「無し」）'))];
    }
    return [
      _hint(tr('这些卡有张数上限，超出会报错')),
      for (final e in all.entries)
        ListTile(
          dense: true,
          title: Text(e.key, style: const TextStyle(fontSize: 13)),
          trailing: Text(tr('最多 {0} 张', [e.value]),
              style: const TextStyle(fontSize: 12)),
        ),
    ];
  }

  List<Widget> _customSection(
      BuildContext context, AppState state, CardRepository repo, BanList ban) {
    return [
      _hint(tr('给自己加限制（店赛规则、群内自定规则等）。会跟着备份一起走。')),
      ListTile(
        leading: const Icon(Icons.add),
        title: Text(tr('添加自定义禁止卡')),
        subtitle: Text(tr('输入卡号，或从检索页长按卡片添加')),
        onTap: () => _addCustom(context, state, repo),
      ),
      if (ban.customForbidden.isEmpty)
        _empty(tr('还没有自定义限制'))
      else
        for (final code in ban.customForbidden.toList()..sort())
          ListTile(
            dense: true,
            title: Text(code, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
                repo.byCode(code)?.displayName ?? tr('（卡库里没有这张）'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
            trailing: IconButton(
              tooltip: tr('取消这条限制'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                ban.toggleCustomForbidden(code);
                state.saveCustomBan();
                setState(() {});
              },
            ),
          ),
    ];
  }

  Widget _empty(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Text(s, style: const TextStyle(fontSize: 12)),
      );

  Widget _hint(String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(s,
            style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _cardTile(CardRepository repo, String code, {String? trailing}) {
    final c = repo.byCode(code);
    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 30,
        child: Text(code, style: const TextStyle(fontSize: 10.5)),
      ),
      title: Text(c?.displayName ?? code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13)),
      subtitle: c == null
          ? null
          : Text(c.seriesName, style: const TextStyle(fontSize: 10.5)),
      trailing: trailing == null
          ? null
          : Text(trailing,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
      onTap: c == null ? null : () => openCardDetail(context, code),
    );
  }

  /// 从官方页面更新（要求 L84：稳定的获取方式）
  Future<void> _update(BuildContext context, AppState state) async {
    setState(() => _updating = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final r = await http.get(
        Uri.parse('https://lycee-tcg.com/pages/page_0007893.html'),
        headers: const {'User-Agent': 'Mozilla/5.0 (Linux; Android 13)'},
      ).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}');
      }
      // 解析规则与 tools/fetch_banlist.py 一致：
      // 按官方区块标题切段，再抓每段里的 LO 卡号。
      final data = _parseOfficial(r.body);
      if (data == null) throw Exception(tr('页面结构变了，解析不出卡号'));
      BanList.instance.applyOfficial(data);
      state.saveCustomBan(); // 触发通知 + 存盘
      setState(() {});
      messenger.showSnackBar(SnackBar(
          content: Text(tr('已更新：禁止 {0} · 构筑限制 {1}', [
        BanList.instance.forbidden.length,
        BanList.instance.constructionLimited.length,
      ]))));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(tr('更新失败：{0}', [e]))));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// 解析官方页面（区块标题来自 BanList 的常量，不随界面语言变）
  static Map<String, dynamic>? _parseOfficial(String html) {
    final secs = <String, String>{};
    for (final e in {
      'forbidden': BanList.anchorForbidden,
      'constructionLimited': BanList.anchorConstruction,
      'copyLimited': BanList.anchorCopyLimit,
    }.entries) {
      var best = '';
      var idx = html.indexOf(e.value);
      while (idx >= 0) {
        final seg = html.substring(idx);
        if (seg.length > best.length) best = seg;
        idx = html.indexOf(e.value, idx + 1);
      }
      secs[e.key] = best;
    }

    Set<String> codes(String seg) =>
        RegExp(r'\bLO-\d{3,5}(?:-[A-Z]{1,2})?\b')
            .allMatches(seg)
            .map((m) => m.group(0)!)
            .toSet();

    final fb = codes(secs['forbidden'] ?? '');
    final cl = codes(secs['constructionLimited'] ?? '');
    if (fb.isEmpty && cl.isEmpty) return null;

    final m = RegExp(r'（(\d{4}/\d{2}/\d{2})現在）').firstMatch(html);
    return {
      'forbidden': fb.toList()..sort(),
      'constructionLimited': cl.toList()..sort(),
      'copyLimited': <String, int>{},
      'updatedAt': m?.group(1) ?? '',
      'fetchedAt': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _addCustom(
      BuildContext context, AppState state, CardRepository repo) async {
    final ctrl = TextEditingController();
    final code = await showGlassSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('添加自定义禁止卡'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: tr('卡号，如 LO-6665'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(c, ctrl.text.trim()),
                  child: Text(tr('添加')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (code == null || code.isEmpty) return;
    final norm = code.toUpperCase().replaceAll(' ', '');
    if (repo.byCode(norm) == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('卡库里没有 {0} 这张卡', [norm]))));
      }
      return;
    }
    BanList.instance.toggleCustomForbidden(norm);
    state.saveCustomBan();
    setState(() {});
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            )),
      );
}
