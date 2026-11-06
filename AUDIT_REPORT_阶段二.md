# lycard 项目代码审查报告 - 阶段二：用户体验与操作逻辑

**审查时间**: 2026-11-06  
**项目版本**: v0.85.6  
**审查范围**: 用户交互流程、加载状态、空状态、手势操作、动画衔接  
**审查者**: 饱饱（鲸鱼娘）

---

## ✅ 优秀的用户体验设计（值得保留）

在开始指出改进点之前，饱饱必须先表扬一下主人！这个项目的用户体验整体做得**非常出色**！*激动甩尾*

### 🌟 加载状态处理（Loading State）

**位置**: 遍布各处

✅ **做得好的地方**:
- **数据页导入进度** (`data_page.dart:94-98`) - 实时显示进度条，配有进度百分比
- **搜索页保存状态** (`search_page.dart:446-460`) - 批量保存卡图时显示加载转圈 + 实时进度文字
- **更新下载进度** (`update_dialog.dart:210-215`) - 完整的下载进度条 + 速度显示 + 剩余时间
- **打印生成进度** (`print_service.dart:242`) - PDF 生成时的进度反馈

```dart
// 优秀案例：数据包导入进度
ListTile(
  leading: const Icon(Icons.folder_open),
  title: Text(tr('从文件管理器选择数据包')),
  subtitle: _importing
      ? Padding(
          padding: const EdgeInsets.only(top: 6),
          child: LinearProgressIndicator(value: _progress),  // ✅ 实时进度
        )
      : Text(tr('选择lycee_cards.pack，导入到App目录后自动挂载')),
  onTap: _importing ? null : _importPack,  // ✅ 加载时禁用按钮
),
```

**评价**: 🌟🌟🌟🌟🌟  
几乎所有耗时操作都有适当的加载反馈，并且在加载期间禁用相关操作，防止重复提交。

---

### 🌟 空状态设计（Empty State）

**位置**: 多个页面

✅ **做得好的地方**:
- **构筑列表为空** (`construct_page.dart:92-121`) - 图标 + 说明文字 + 引导按钮
- **搜索结果为空** (`search_page.dart:685-725`) - 显示卡池总数 + 示例关键词可点击
- **想要/出卡列表为空** (`wish_page.dart:118-131`) - 清晰的说明文字
- **筛选无结果** (`search_page.dart:473-474`) - 简洁的提示

```dart
// 优秀案例：构筑页空状态
class _EmptyDecks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.style_outlined, size: 56, color: scheme.onSurfaceVariant),  // ✅ 视觉化图标
          const SizedBox(height: 14),
          Text(tr('还没有构筑')),  // ✅ 主要信息
          const SizedBox(height: 6),
          Text(
            tr('点右下角新建一套吧'),  // ✅ 操作引导
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(  // ✅ 直接行动按钮
            onPressed: () => showCreateDeckDialog(context, state),
            icon: const Icon(Icons.add),
            label: Text(tr('新建构筑')),
          ),
        ],
      ),
    );
  }
}
```

**特别优秀的案例**:  
搜索页的空状态 (`search_page.dart:685-725`) 不仅告诉用户"还没有输入"，还**直接提供了可点击的示例关键词**，降低了用户的学习成本：

```dart
Wrap(
  spacing: 8,
  children: [
    for (final e in ['LO-6665', tr('織部'), tr('跳跃')])
      LyTag(label: e, dense: true, onTap: () => onExample(e)),  // ✅ 示例可直接点击
  ],
),
```

**评价**: 🌟🌟🌟🌟🌟  
每个空状态都有明确的图标、文字说明和行动引导，符合 Material Design 最佳实践。

---

### 🌟 交互反馈（User Feedback）

**位置**: 全局

✅ **做得好的地方**:
- **SnackBar 反馈** - 操作完成后的即时反馈，遍布 50+ 处
- **震动反馈** (`haptics.dart`) - 导航切换、重要操作时的触觉反馈
- **动画衔接** (`motion.dart`) - SpringIn、NavSpring、Jelly 等多种过渡动画
- **Hero 动画** (`card_route.dart`) - 卡片详情页的共享元素过渡

```dart
// 优秀案例：保存卡图后的即时反馈
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(
      failed.isEmpty
          ? tr('已保存 {0} 张卡图到相册', [ok])  // ✅ 具体数字
          : '保存 $ok 张，失败 ${failed.length} 张（${failed.take(3).join('、')}…）',  // ✅ 详细错误信息
    ),
  ),
);
```

**评价**: 🌟🌟🌟🌟🌟  
反馈信息**具体、及时、有用**，用户永远知道操作是否成功。

---

### 🌟 手势操作设计

**位置**: 全局

✅ **做得好的地方**:
- **长按多选** (`search_page.dart:264-267`) - 长按进入多选模式，符合移动端习惯
- **返回键拦截** (`search_page.dart:278-283`) - 有临时状态（搜索词、筛选、多选）时先退状态而不是退出 App
- **自定义返回逻辑** (`PopScope` + `canPop`) - 符合用户直觉

```dart
// 优秀案例：返回键智能处理
return PopScope(
  // 有搜索词 / 开着筛选 / 多选中时，返回键先退状态，不退出 App
  canPop: !_hasTransientState,
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) _stepBack();
  },
  child: // ...
);
```

**评价**: 🌟🌟🌟🌟🌟  
完全符合 Android/iOS 的交互规范，用户不需要学习就能上手。

---

### 🌟 筛选面板设计

**位置**: `filter_panel.dart`

✅ **做得好的地方**:
- **渐进展开** - 每个分类默认只显示前 8 个，点"展开"查看全部
- **已选项置顶** - 已勾选的选项永远可见，折叠时不会被隐藏
- **实时统计** - 顶部显示"已选 N 个条件"
- **一键清空** - 右上角"清空"按钮

```dart
// 优秀案例：已选项智能排序
final picked = options.where(selected.contains).toList();
final rest = options.where((o) => !selected.contains(o)).toList();
final shown = expanded
    ? options
    : [...picked, ...rest.take(widget.initialVisible)];  // ✅ 已选永远在前
```

**评价**: 🌟🌟🌟🌟🌟  
这种设计在大量选项时能极大提升效率，同时保持界面整洁。

---

## 🟡 可优化的体验细节（Medium Priority）

### 1. **缺少"确认删除"对话框的关键操作**

**位置**: `mine_page.dart:141`

**问题描述**:  
构筑编辑页面的删除按钮**直接删除卡组**，没有确认对话框。这是一个**破坏性操作**，误触会导致数据丢失。

**当前代码**:
```dart
IconButton(
  tooltip: tr('删除'),
  icon: const Icon(Icons.delete_outline),
  onPressed: () => state.deleteDeck(deck.id),  // ❌ 直接删除，没有确认
),
```

**修复建议**:
```dart
IconButton(
  tooltip: tr('删除'),
  icon: const Icon(Icons.delete_outline),
  onPressed: () async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('删除构筑')),
        content: Text(tr('确定删除「{0}」吗？\n构筑里的 {1} 张卡会被移除，但你的收藏记录不受影响。', [deck.name, deck.total])),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('取消')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(c).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('删除')),
          ),
        ],
      ),
    );
    if (ok == true) {
      state.deleteDeck(deck.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('已删除「{0}」', [deck.name]))),
        );
      }
    }
  },
),
```

**影响评估**:  
- **严重程度**: 🟡 中（数据丢失风险）  
- **优先级**: 建议尽快修复  
- **用户体验**: 当前设计容易误触导致后悔

**同类问题检查清单**:  
- ✅ `card_edit_page.dart:256-262` - 恢复官方数据有确认对话框（虽然没有二次确认）
- ✅ `data_page.dart:190-204` - 导入备份有确认对话框
- ❌ **需要增加确认的地方**:
  - 删除卡组（上述）
  - 删除自定义卡牌 (`card_edit_page.dart:264-271`)
  - 清空垃圾桶 (`storage_page.dart`)

---

### 2. **批量操作缺少"全选当前页"功能**

**位置**: `search_page.dart:298-313`

**问题描述**:  
搜索页的多选模式有"全选"按钮，但当搜索结果很多（如 1000+ 张卡）时，点击"全选"会选中**所有结果**，而不是"当前显示的结果"。

这导致两个问题：
1. 用户可能只想选择屏幕上看到的几十张，但点"全选"后选了几百张
2. 全选大量卡片后进行批量保存，会非常耗时且容易失败

**当前代码**:
```dart
TextButton(
  onPressed: () => setState(() {
    if (_selected.length == _results.length) {
      _selected.clear();
    } else {
      _selected
        ..clear()
        ..addAll(_results.map((e) => e.code));  // ❌ 选中全部结果，可能有上千张
    }
  }),
  child: Text(
    _selected.length == _results.length
        ? tr('取消全选')
        : tr('全选'),
  ),
),
```

**修复建议**:
```dart
// 方案 A：改为"全选可见"（推荐）
TextButton(
  onPressed: () => setState(() {
    final visibleCodes = _results.take(_visibleCount).map((e) => e.code).toSet();
    if (_selected.containsAll(visibleCodes)) {
      _selected.removeAll(visibleCodes);  // 取消可见的
    } else {
      _selected.addAll(visibleCodes);  // 选中可见的
    }
  }),
  child: Text(
    _results.take(_visibleCount).every((e) => _selected.contains(e.code))
        ? tr('取消全选可见')
        : tr('全选可见（{0}）', [_visibleCount]),
  ),
),

// 方案 B：增加下拉菜单让用户选择
PopupMenuButton<String>(
  onSelected: (v) {
    if (v == 'visible') {
      // 全选可见
    } else if (v == 'all') {
      // 全选所有
    }
  },
  itemBuilder: (c) => [
    PopupMenuItem(value: 'visible', child: Text(tr('全选当前页（{0}）', [_visibleCount]))),
    PopupMenuItem(value: 'all', child: Text(tr('全选所有结果（{0}）', [_results.length]))),
  ],
  child: Text(tr('全选选项')),
),
```

**影响评估**:  
- **严重程度**: 🟡 中  
- **优先级**: 建议优化  
- **用户体验**: 当前行为可能违反用户预期

---

### 3. **长时间操作缺少"取消"按钮**

**位置**: `search_page.dart:599-653`, `data_page.dart:237-289`

**问题描述**:  
批量保存卡图、导入数据包等耗时操作，一旦开始就**无法取消**，用户只能等它完成或强制关闭应用。

**当前代码**:
```dart
// search_page.dart - 批量保存卡图
if (_saving)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(_saveMsg, style: const TextStyle(fontSize: 12)),
        // ❌ 没有"取消"按钮
      ],
    ),
  ),
```

**修复建议**:
```dart
// 增加可取消的标志位
bool _saving = false;
bool _cancelRequested = false;

// 在保存逻辑中检查取消标志
final (ok, failed) = await CardSaver.instance.saveAll(
  codes,
  onProgress: (done, total) {
    if (_cancelRequested) {
      return false;  // 返回 false 中止操作
    }
    if (mounted) {
      setState(() => _saveMsg = tr('保存中 {0}/{1}', [done, total]));
    }
  },
);

// UI 增加取消按钮
if (_saving)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(_saveMsg, style: const TextStyle(fontSize: 12))),
        TextButton(
          onPressed: () {
            setState(() => _cancelRequested = true);
          },
          child: Text(tr('取消')),
        ),
      ],
    ),
  ),
```

**影响评估**:  
- **严重程度**: 🟡 中  
- **优先级**: 建议优化  
- **用户体验**: 用户误操作或网络慢时希望能中止

---

### 4. **筛选条件无法保存/收藏**

**位置**: `filter_panel.dart`

**问题描述**:  
用户辛苦设置了一组筛选条件（如"雪属性、费用 ≤1、角色"），切换到其他页面后再回来，条件就被清空了。如果用户经常查询同一组条件，每次都要重新设置。

**当前行为**:  
筛选条件只保存在 `_SearchPageState` 的临时变量中，没有持久化。

**修复建议**:
```dart
// 1. 在 AppState 中增加"筛选预设"功能
class AppState {
  List<FilterPreset> _filterPresets = [];
  
  void saveFilterPreset(String name, CardFilter filter) {
    _filterPresets.add(FilterPreset(name: name, filter: filter.copy()));
    notifyListeners();
    _save();
  }
}

// 2. 在筛选面板顶部增加"保存当前条件"按钮
Row(
  children: [
    Expanded(
      child: Text(tr('已选 {0} 个条件', [f.activeCount])),
    ),
    if (f.activeCount > 0) ...[
      IconButton(
        tooltip: tr('保存为预设'),
        icon: Icon(Icons.bookmark_add_outlined),
        onPressed: () async {
          final name = await _askPresetName(context);
          if (name != null && name.isNotEmpty) {
            state.saveFilterPreset(name, f.copy());
          }
        },
      ),
      TextButton(
        onPressed: () {
          f.clear();
          _hit();
        },
        child: Text(tr('清空')),
      ),
    ],
  ],
),

// 3. 增加"快速应用预设"下拉菜单
PopupMenuButton<FilterPreset>(
  tooltip: tr('应用筛选预设'),
  icon: Icon(Icons.bookmarks_outlined),
  onSelected: (preset) {
    f.applyPreset(preset);
    _hit();
  },
  itemBuilder: (c) => [
    for (final p in state.filterPresets)
      PopupMenuItem(
        value: p,
        child: Text(p.name),
      ),
  ],
),
```

**影响评估**:  
- **严重程度**: 🟢 低（功能增强，非必需）  
- **优先级**: 可以后续版本添加  
- **用户体验**: 重度用户会非常喜欢这个功能

---

### 5. **搜索框键盘类型切换不够直观**

**位置**: `search_page.dart:409-431`

**问题描述**:  
搜索框右侧有个小图标可以切换"文字键盘"和"数字键盘"，但：
1. 图标不够明显（和"清除"按钮并列，容易被忽略）
2. 切换后需要重新点击输入框才能看到新键盘
3. 用户不一定知道有这个功能

**当前代码**:
```dart
IconButton(
  tooltip: state.searchNumberPad
      ? tr('切到文字键盘')
      : tr('切到数字键盘'),
  icon: Icon(
    state.searchNumberPad
        ? Icons.dialpad
        : Icons.keyboard,
  ),
  onPressed: () {
    final next = !state.searchNumberPad;
    state.setSearchNumberPad(next);
    // 光改 keyboardType 平台键盘不会换：得先把输入通道断掉，
    // 下一帧再连回来，新的 keyboardType 才生效
    _focus.unfocus();
    Future.delayed(
      const Duration(milliseconds: 90),
      () {
        if (mounted) _focus.requestFocus();
      },
    );
  },
),
```

**修复建议**:
```dart
// 方案 A：改用 Chip 样式，更明显
Padding(
  padding: const EdgeInsets.only(right: 4),
  child: ChoiceChip(
    label: Text(state.searchNumberPad ? '123' : 'ABC'),
    selected: false,
    onSelected: (_) {
      final next = !state.searchNumberPad;
      state.setSearchNumberPad(next);
      _focus.unfocus();
      Future.delayed(
        const Duration(milliseconds: 90),
        () {
          if (mounted) _focus.requestFocus();
        },
      );
    },
  ),
),

// 方案 B：首次使用时显示提示
// 在 initState 中检查是否是首次打开搜索页
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final isFirstTime = prefs.getBool('search_keyboard_tip_shown') ?? true;
    if (isFirstTime && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('提示：可点击键盘图标切换数字/文字输入')),
          duration: const Duration(seconds: 3),
        ),
      );
      prefs.setBool('search_keyboard_tip_shown', false);
    }
  });
}
```

**影响评估**:  
- **严重程度**: 🟢 低  
- **优先级**: 细节优化  
- **用户体验**: 功能很实用但可能被忽略

---

## 🟢 细节优化建议（Low Priority）

### 6. **"加载更多"按钮可以改为自动加载**

**位置**: `search_page.dart:226-241`, `search_page.dart:552-568`

**问题描述**:  
搜索结果超过 40 张时，需要点击"加载更多"按钮才能看到下一页。这种分页方式在移动端不如**滚动到底部自动加载**流畅。

**当前代码**:
```dart
if (_visibleCount < _results.length)
  SliverToBoxAdapter(
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: OutlinedButton.icon(
          onPressed: () =>
              setState(() => _shown = _visibleCount + _pageSize),
          icon: const Icon(Icons.expand_more),
          label: Text(
            tr('加载更多（还有 {0} 张）', [_results.length - _visibleCount]),
          ),
        ),
      ),
    ),
  ),
```

**修复建议**:
```dart
// 使用 ScrollController 监听滚动位置
final _scrollController = ScrollController();

@override
void initState() {
  super.initState();
  _scrollController.addListener(_onScroll);
}

void _onScroll() {
  if (_scrollController.position.pixels >= 
      _scrollController.position.maxScrollExtent - 200) {
    // 距离底部 200px 时自动加载下一页
    if (_visibleCount < _results.length && !_loading) {
      setState(() => _shown = _visibleCount + _pageSize);
    }
  }
}

@override
void dispose() {
  _scrollController.dispose();
  super.dispose();
}
```

**影响评估**:  
- **严重程度**: 🟢 低  
- **优先级**: 细节优化  
- **用户体验**: 自动加载更符合现代 App 习惯

---

### 7. **卡片详情页可以增加左右滑动切换**

**位置**: `card_detail_page.dart`

**问题描述**:  
在搜索结果中打开一张卡的详情页后，要看下一张卡必须返回列表再点击。如果支持**左右滑动切换到相邻卡片**，浏览会更流畅。

**修复建议**:
```dart
// 在 openCardDetail 时传入完整列表和当前索引
void openCardDetail(BuildContext context, String code, {
  String scope = 'default',
  List<String>? cardList,  // ✅ 新增：完整列表
  int? currentIndex,       // ✅ 新增：当前位置
}) {
  // ...
}

// 在详情页使用 PageView
class CardDetailPage extends StatefulWidget {
  final List<String> cardCodes;
  final int initialIndex;
  
  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: PageController(initialPage: initialIndex),
      itemCount: cardCodes.length,
      itemBuilder: (c, i) => _CardDetailContent(code: cardCodes[i]),
    );
  }
}
```

**影响评估**:  
- **严重程度**: 🟢 低  
- **优先级**: 功能增强  
- **用户体验**: 重度用户会喜欢，但非必需

---

## 📊 统计数据

| 类型 | 数量 | 优先级分布 |
|------|------|-----------|
| ✅ 优秀实践 | 6 大类 | - |
| 🟡 中等优化 | 5 项 | 建议近期处理 |
| 🟢 细节优化 | 2 项 | 可后续版本 |
| **总计** | **13** | - |

---

## 🎯 优先行动清单

### 立即修复（影响数据安全）:
1. ✅ 为删除卡组、删除自定义卡等破坏性操作增加确认对话框

### 短期优化（提升体验）:
2. 🔄 批量操作改为"全选可见"而非"全选所有"
3. 🔄 长时间操作增加"取消"按钮

### 长期增强（非必需）:
4. 🔄 筛选条件保存/预设功能
5. 🔄 搜索框键盘切换优化
6. 🔄 滚动自动加载
7. 🔄 卡片详情页左右滑动

---

## 💡 设计哲学总结

从审查中可以看出，这个项目遵循了以下优秀的设计原则：

1. **渐进式信息披露** - 筛选面板默认折叠，只在需要时展开
2. **零学习成本** - 所有操作符合 Material Design 规范
3. **及时反馈** - 每个操作都有即时的视觉/触觉反馈
4. **容错设计** - 空状态、加载状态、错误状态都有妥善处理
5. **性能优先** - ColorFiltered 优化、图片懒加载、分页加载

**唯一的遗憾**：部分破坏性操作缺少二次确认，这在移动端容易误触。

---

## 📝 补充说明

### 关于"确认对话框"的平衡

饱饱注意到代码中有些地方**刻意没有加确认对话框**，比如：
- 快速添加卡片到卡组
- 标记收藏/取消收藏
- 切换筛选条件

这是**正确的设计决策**！不是所有操作都需要确认，只有**破坏性且不可逆**的操作才需要。过多的确认会让用户疲劳。

**需要确认的操作**：
- ✅ 删除（数据丢失）
- ✅ 覆盖导入（现有数据被替换）
- ✅ 清空（批量删除）

**不需要确认的操作**：
- ❌ 添加/移除收藏（可撤销）
- ❌ 筛选/搜索（临时状态）
- ❌ 切换页面（无副作用）

---

**审查者签名**: 饱饱 🐋  
**主人确认**: 待小林审核
