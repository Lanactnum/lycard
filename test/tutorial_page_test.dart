import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/pages/tutorial_page.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 对战教程页能不能真的渲染出来。
///
/// 光有数据体检（tutorial_test.dart）不够 —— 数据合法但渲染器分派
/// 不对、或者某个 block 类型崩了，用户看到的就是白屏或半截内容。
/// 这里把页面真 pump 起来，确认章节标题和内容都出现在 widget 树上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> boot() async {
    // ⚠ 必须在每个测试开头清掉 rootBundle 的资产缓存。
    //
    // 不清的话：第一个测试读 assets 走真实 IO、一切正常；第二个测试
    // 命中缓存，那个 Future 的完成回调会被调度到**上一个测试已经废弃的
    // zone** 里，于是 `await rootBundle.loadString(...)` 永远不返回 ——
    // 页面停在加载态，但单独跑这个测试又是好的（实测就卡在这上面）。
    // 症状是「单独跑通过、一起跑失败」，极难猜。
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
    return AppState.create();
  }

  testWidgets('教程页渲染出目录与全部章节标题', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      state = await boot();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: TutorialPage()),
      ),
    );

    // 资产读取是真 IO，得给它真实时间；之后再用 pump 把帧推完
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 标题栏
    expect(find.text('对战教程'), findsOneWidget);

    // 目录
    expect(find.text('目录'), findsOneWidget);

    // 第一章和最后一章的标题都应在树上
    expect(find.textContaining('先认识这个游戏'), findsWidgets,
        reason: '第一章标题没渲染出来');
    expect(find.textContaining('在 lycard 里怎么用'), findsWidgets,
        reason: '最后一章标题没渲染出来（内容被截断了？）');

    // 关键结论（key 块）与表格都要有内容
    expect(find.textContaining('谁先把对方的牌库削到 0 张'), findsOneWidget,
        reason: '胜利条件这句没渲染出来');
    expect(find.textContaining('攻击判定'), findsWidgets,
        reason: '表格里的内容没渲染出来');

    // 不应该出现加载失败
    expect(find.text('教程内容加载失败'), findsNothing);
  });

  testWidgets('教程页的序号与项目符号都画出来了', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      state = await boot();
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: TutorialPage()),
      ),
    );
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // steps 块的序号是画出来的圆 + 数字，至少应该有「1」「2」这样的序号
    expect(find.text('1'), findsWidgets, reason: '步骤序号没渲染');
    expect(find.text('2'), findsWidgets, reason: '步骤序号没渲染');

    // 正文不该出现渲染器不认识的类型被当成段落打印出来的痕迹
    expect(find.textContaining('{'), findsNothing,
        reason: '有块把原始 JSON 打印出来了');
  });
}
