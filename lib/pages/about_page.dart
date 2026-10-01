import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/update_service.dart';
import '../widgets/update_dialog.dart';
import 'license_page.dart';
import 'tutorial_page.dart';
import 'feedback_page.dart';
import '../widgets/glass.dart';
import '../widgets/bg_scaffold.dart';
import '../l10n/l10n.dart';

/// 「关于」（从设置里挪进来的二级菜单，要求 L115）
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  AppUpdate? _update;
  String? _updateMessage;
  String? _updateError;
  bool _checkingUpdate = false;

  Future<void> _checkForUpdate() async {
    setState(() {
      _checkingUpdate = true;
      _updateMessage = null;
      _updateError = null;
    });
    try {
      final result = await UpdateService.instance.check();
      if (!mounted) return;
      setState(() {
        _update = result.update;
        _updateMessage = result.hasUpdate ? null : (result.message ?? '当前已是最新版');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _updateError = '检查更新失败，请确认网络后重试');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  /// 应用内下载并安装（不跳浏览器）
  Future<void> _startUpdate() async {
    final u = _update;
    if (u == null || !mounted) return;
    if (u.downloadUrl == null) {
      setState(() => _updateError = '这个版本没挂安装包，过一会儿再试');
      return;
    }
    await showUpdateDialog(context, u);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('关于'))),
      body: ListView(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Column(
              children: [
                Icon(Icons.style, size: 56, color: scheme.primary),
                const SizedBox(height: 10),
                const Text(
                  'lycard',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Lycard',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 26),
          ListTile(
            leading: Icon(Icons.favorite),
            title: Text(
              tr('由镧锕Lanactnum的大肥鱼制作'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(tr('以 MIT 协议开源')),
          ),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(
              tr('对战教程'),
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(tr('从零开始的一局：开局、回合流程、战斗、卡面读法')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const TutorialPage())),
          ),
          ListTile(
            leading: const Icon(Icons.feedback_outlined),
            title: Text(tr('Bug / 功能反馈')),
            subtitle: Text(tr('填写并复制诊断报告')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const FeedbackPage())),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(tr('开源许可（MIT）')),
            subtitle: Text(tr('点击查看协议全文')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MitLicensePage())),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(tr('第三方开源许可')),
            subtitle: Text(tr('本项目所用各个开源包各自的许可')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'lycard',
              applicationVersion: '0.8.0',
              applicationLegalese: tr('© 2026 镧锕Lanactnum的蓝色大肥鱼 · MIT License'),
            ),
          ),
          ListTile(
            leading: Icon(Icons.dns_outlined),
            title: Text(tr('数据来源')),
            subtitle: Text(
              tr(
                '卡图与卡片数值：LYCEE OVERTURE 官方网站（lycee-tcg.com）\\n中文翻译：GPT-5.6-sol\\n全部数据与卡图已离线打包',
              ),
            ),
            isThreeLine: true,
          ),
          ListTile(
            leading: Icon(Icons.dataset_outlined),
            title: Text(tr('卡片数据')),
            subtitle: Text(tr('9952 张,离线卡图 9952 张')),
          ),
          FutureBuilder<String>(
            future: appVersionText(),
            builder: (c, s) => ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(tr('lycard 版本号')),
              subtitle: Text(s.hasData ? s.data! : tr('读取中…')),
            ),
          ),
          ListTile(
            leading: _checkingUpdate
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_outlined),
            title: const Text('检查更新'),
            subtitle: Text(
              _updateError ??
                  (_update?.isNewer == true
                      ? '发现新版本 ${_update!.latestVersion}'
                      : (_updateMessage ?? '从 GitHub Releases 检查最新版')),
            ),
            trailing: const Icon(Icons.refresh),
            onTap: _checkingUpdate ? null : _checkForUpdate,
          ),
          if (_update?.isNewer == true) ...[
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text('更新到 lycard ${_update!.latestVersion}'),
              subtitle: const Text('在应用内下载并安装，不用跳浏览器'),
              trailing: const Icon(Icons.system_update_alt),
              onTap: _startUpdate,
            ),
            if (_update!.notes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(_update!.notes),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 版本号文本（设置页和关于页共用）
Future<String> appVersionText() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version}+${info.buildNumber}';
  } catch (_) {
    return tr('未知');
  }
}
