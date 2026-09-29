// 这个文件是 mine_page.dart 的一部分（part），所以能直接用它的私有成员。
// 目的：把「设置」从底栏 tab 里挪出来，做成「我的」右上角的独立页面。
part of 'mine_page.dart';

/// 设置页（从「我的」右上角齿轮进入）
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('设置'))),
      body: const _SettingsTab(),
    );
  }
}

/// 构筑编辑页（底栏「构筑」里点某套构筑的「编辑」进入）
class DeckEditorPage extends StatelessWidget {
  const DeckEditorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BgScaffold(
      // 背景交给最底层那一张图，页面自身透明 → 切页面不用重画背景
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('构筑编辑'))),
      body: const _DeckEditorTab(),
    );
  }
}
