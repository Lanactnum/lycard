import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/card_repository.dart';
import '../l10n/l10n.dart';
import '../state/app_state.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/glass.dart';
import '../widgets/layout.dart';
import '../widgets/tags.dart';

/// 应用内反馈：离线填写并复制诊断报告，不依赖尚未配置的远程服务。
class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _body = TextEditingController();
  String _kind = 'bug';

  /// 正在逐条处理的待收录项：给一键模板，用户只要补卡号就行，
  /// 不用自己组织语言，我这边也好按主题归类。
  String? _topic;

  static const List<(String, String)> _quickTopics = [
    ('卡名待译', '卡名还是纯日文／外文\n卡号：\n现在的卡名：\n建议译名（可选）：'),
    ('效果待译', '效果文本里残留日文片段\n卡号：\n残留的片段：\n正确写法（可选）：'),
  ];

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  String _report(AppState state) {
    final repo = CardRepository.instance;
    final text = _body.text.trim();
    return [
      'lycard 反馈',
      '类型：${_kind == 'bug' ? 'Bug' : '功能建议'}',
      if (_topic != null) '主题：$_topic',
      '平台：${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      '卡池：${repo.all.length} 张',
      '已收集：${state.owned.length} 张',
      '构筑：${state.decks.length} 套',
      '',
      text.isEmpty ? '（未填写描述）' : text,
    ].join('\n');
  }

  Future<void> _copy() async {
    final state = context.read<AppState>();
    await Clipboard.setData(ClipboardData(text: _report(state)));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('反馈报告已复制'))));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return BgScaffold(
      appBar: GlassAppBar(title: Text(tr('Bug / 功能反馈'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, kBottomBarSpace),
        children: [
          Text(
            tr('填写后复制报告，发送给开发者即可。报告只包含诊断信息和你填写的内容。'),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              for (final (value, label) in <(String, String)>[
                ('bug', 'Bug'),
                ('feature', '功能建议'),
              ])
                LyTag(
                  label: tr(label),
                  selected: _kind == value,
                  onTap: () => setState(() => _kind = value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(tr('快捷收录'),
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, tpl) in _quickTopics)
                LyTag(
                  label: tr(label),
                  selected: _topic == label,
                  onTap: () => setState(() {
                    _topic = label;
                    _body.text = tpl;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _body,
            minLines: 7,
            maxLines: 14,
            decoration: InputDecoration(
              labelText: tr('描述问题或想法'),
              hintText: tr('请写复现步骤、涉及卡号/页面和期望结果'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.content_copy_outlined),
            label: Text(tr('复制反馈报告')),
          ),
          const SizedBox(height: 20),
          Text(tr('当前统计'), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            tr('卡池 {0} 张 · 已收集 {1} 张 · 构筑 {2} 套', [
              CardRepository.instance.all.length,
              state.owned.length,
              state.decks.length,
            ]),
          ),
        ],
      ),
    );
  }
}
