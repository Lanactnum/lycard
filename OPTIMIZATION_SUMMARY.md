# lycard 项目优化总结 - 2026-11-06

**版本**: v0.85.6 → v0.86.0 (建议)  
**优化者**: 饱饱（鲸鱼娘）🐋  
**优化时间**: 2026-11-06

---

## ✅ 已完成的优化

### 🔴 优化1：删除操作增加确认对话框

**问题**: 删除卡组等破坏性操作没有确认对话框，误触会丢失数据。

**解决方案**:
- 新增 `_confirmDelete()` 方法
- 删除前弹出确认对话框，显示将要删除的内容
- 使用红色按钮突出危险性
- 删除后显示 SnackBar 反馈

**修改文件**:
- `lib/pages/mine_page.dart` (+35 行)

**代码示例**:
```dart
Future<void> _confirmDelete(BuildContext context, AppState state, Deck deck) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('删除构筑')),
      content: Text(tr('确定删除「{0}」吗？\n\n构筑里的 {1} 张卡会被移除，但你的收藏记录不受影响。', [deck.name, deck.total])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('取消'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
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
}
```

---

### 🟡 优化3：批量保存增加取消按钮

**问题**: 批量保存卡图等长时间操作无法中途取消，用户只能等待或强制关闭。

**解决方案**:
- 增加 `_cancelSaving` 标志位
- 在进度显示区域添加"取消"按钮
- 在 `onProgress` 回调中检查取消信号
- 取消时显示已保存数量

**修改文件**:
- `lib/pages/search_page.dart` (+20 行)

**代码示例**:
```dart
// 状态标志
bool _saving = false;
bool _cancelSaving = false;

// UI 显示
if (_saving)
  Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 10),
        Expanded(child: Text(_saveMsg, style: const TextStyle(fontSize: 12))),
        TextButton(
          onPressed: () => setState(() => _cancelSaving = true),
          child: Text(tr('取消')),
        ),
      ],
    ),
  ),

// 保存逻辑
final (ok, failed) = await CardSaver.instance.saveAll(
  codes,
  onProgress: (done, total) {
    if (_cancelSaving) return false;  // ✅ 取消信号
    if (mounted) setState(() => _saveMsg = tr('保存中 {0}/{1}', [done, total]));
    return true;
  },
);
```

---

### 🟢 优化4：筛选条件保存功能

**问题**: 用户设置的复杂筛选条件无法保存，每次都要重新设置。

**解决方案**:
- 在 `CardFilter` 中增加 `copy()` 和 JSON 序列化方法
- 在 `AppState` 中增加筛选预设的存储和管理
- 在筛选面板增加"保存预设"和"加载预设"按钮
- 预设列表支持删除

**修改文件**:
- `lib/data/card_filter.dart` (+67 行)
- `lib/state/app_state.dart` (+45 行)
- `lib/widgets/filter_panel.dart` (+90 行)

**核心功能**:
```dart
// CardFilter 序列化
Map<String, dynamic> toJson() => {
  if (colors.isNotEmpty) 'colors': colors.toList(),
  if (kinds.isNotEmpty) 'kinds': kinds.toList(),
  // ...
};

factory CardFilter.fromJson(Map<String, dynamic> j) {
  return CardFilter()
    ..colors.addAll((j['colors'] as List<dynamic>? ?? []).cast<String>())
    // ...
}

// AppState 管理
void saveFilterPreset(String name, CardFilter filter) {
  final idx = _filterPresets.indexWhere((p) => p.name == name);
  if (idx >= 0) {
    _filterPresets[idx] = FilterPreset(name: name, filter: filter.copy());
  } else {
    _filterPresets.add(FilterPreset(name: name, filter: filter.copy()));
  }
  notifyListeners();
  _save();
}
```

**用户体验**:
- 点击书签按钮保存当前筛选条件
- 点击书签列表快速应用预设
- 长按预设可删除

---

### 🟢 优化5：键盘切换改为 Chip 样式

**问题**: 搜索框的数字/文字键盘切换图标不够明显，容易被忽略。

**解决方案**:
- 将 IconButton 改为 ChoiceChip
- 显示 "ABC" 或 "123" 文字更直观
- 保持原有的切换逻辑

**修改文件**:
- `lib/pages/search_page.dart` (+15 行)

**代码对比**:
```dart
// ❌ 旧版：不够明显
IconButton(
  tooltip: state.searchNumberPad ? tr('切到文字键盘') : tr('切到数字键盘'),
  icon: Icon(state.searchNumberPad ? Icons.dialpad : Icons.keyboard),
  onPressed: () { /* 切换逻辑 */ },
)

// ✅ 新版：更直观
Padding(
  padding: const EdgeInsets.only(right: 8),
  child: ChoiceChip(
    label: Text(state.searchNumberPad ? '123' : 'ABC', style: const TextStyle(fontSize: 12)),
    selected: false,
    tooltip: state.searchNumberPad ? tr('切到文字键盘') : tr('切到数字键盘'),
    onSelected: (_) { /* 切换逻辑 */ },
  ),
)
```

---

### 🟢 优化6：滚动自动加载

**问题**: 搜索结果需要手动点击"加载更多"按钮，不符合现代 App 习惯。

**解决方案**:
- 增加 `ScrollController` 监听滚动位置
- 距离底部 300px 时自动加载下一页
- 替换"加载更多"按钮为加载提示文字

**修改文件**:
- `lib/pages/search_page.dart` (+25 行)

**代码示例**:
```dart
final _scrollController = ScrollController();

@override
void initState() {
  super.initState();
  _scrollController.addListener(_onScroll);
}

void _onScroll() {
  if (_scrollController.hasClients &&
      _scrollController.position.pixels >= 
          _scrollController.position.maxScrollExtent - 300) {
    if (_visibleCount < _results.length) {
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

---

### 🟢 优化7：卡片详情页左右滑动切换

**问题**: 在搜索结果中查看卡片详情时，要看下一张必须返回列表再点击。

**解决方案**:
- 新增 `CardDetailPageView` 支持 PageView 滑动
- 修改 `openCardDetail()` 函数，支持传入卡片列表
- 添加页码指示器显示当前位置
- 滑动时更新 Scatter 状态保证动画正确

**修改文件**:
- `lib/pages/card_detail_page.dart` (+70 行)
- `lib/widgets/card_route.dart` (重构)

**核心实现**:
```dart
class CardDetailPageView extends StatefulWidget {
  const CardDetailPageView({
    super.key,
    required this.codes,
    required this.initialIndex,
    this.scope = 'list',
  });

  final List<String> codes;
  final int initialIndex;
  final String scope;

  @override
  State<CardDetailPageView> createState() => _CardDetailPageViewState();
}

class _CardDetailPageViewState extends State<CardDetailPageView> {
  late PageController _pageController;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      itemCount: widget.codes.length,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
        Scatter.activeCode = widget.codes[index];  // ✅ 更新 Hero 动画
      },
      itemBuilder: (context, index) => CardDetailPage(
        code: widget.codes[index],
        showPageIndicator: true,
        currentPage: index + 1,
        totalPages: widget.codes.length,
      ),
    );
  }
}
```

**使用方式**:
```dart
// 单张卡片（原有方式）
openCardDetail(context, 'LO-0001');

// 支持滑动切换（新功能）
openCardDetail(
  context,
  'LO-0001',
  cardList: ['LO-0001', 'LO-0002', 'LO-0003'],
  currentIndex: 0,
);
```

---

## 📊 优化统计

| 优化项 | 优先级 | 修改文件数 | 新增代码行 | 用户体验提升 |
|--------|--------|-----------|-----------|------------|
| 优化1 删除确认 | 🔴 高 | 1 | +35 | ⭐⭐⭐⭐⭐ 防止误删 |
| 优化3 取消保存 | 🟡 中 | 1 | +20 | ⭐⭐⭐⭐ 可中止长操作 |
| 优化4 筛选预设 | 🟢 低 | 3 | +202 | ⭐⭐⭐⭐ 重度用户福音 |
| 优化5 键盘切换 | 🟢 低 | 1 | +15 | ⭐⭐⭐ 更直观 |
| 优化6 滚动加载 | 🟢 低 | 1 | +25 | ⭐⭐⭐⭐ 更流畅 |
| 优化7 滑动切换 | 🟢 低 | 2 | +85 | ⭐⭐⭐⭐⭐ 浏览效率提升 |
| **总计** | - | **9** | **+382** | - |

---

## ❌ 未实施的优化

### 优化2：批量全选逻辑优化

**原因**: 主人要求跳过

**建议**: 当前"全选"会选中所有结果（可能上千张），建议改为"全选可见"更符合用户预期。

---

## 🎯 测试建议

1. **删除确认**:
   - 尝试删除卡组，确认对话框显示正确信息
   - 点击"取消"应不删除
   - 点击"删除"应删除并显示 SnackBar

2. **取消保存**:
   - 多选 100+ 张卡批量保存
   - 保存进行中点击"取消"
   - 确认已保存数量显示正确

3. **筛选预设**:
   - 设置复杂筛选条件（如：雪属性 + 费用≤1 + 角色）
   - 保存为预设"低费雪角色"
   - 清空筛选，重新应用预设
   - 确认条件完全恢复

4. **键盘切换**:
   - 打开搜索页，观察右侧 Chip
   - 点击 ABC/123 切换
   - 确认键盘类型正确切换

5. **滚动加载**:
   - 搜索返回大量结果（如搜索"角色"）
   - 向下滚动到接近底部
   - 确认自动加载下一页

6. **滑动切换**:
   - 在搜索结果中打开任意卡片详情
   - 左右滑动切换到相邻卡片
   - 确认页码指示器显示正确
   - 确认返回时回到正确位置

---

## 🐛 已知问题

1. **优化7** 的实现移除了 `Scatter` 的散开/收回动画，以简化 PageView 集成。如需恢复该动画，需要更复杂的状态管理。

2. **优化4** 的筛选预设目前没有上限，建议后续添加最大预设数量限制（如 20 个）。

---

## 📝 后续优化建议

1. **首次使用引导**: 为筛选预设、键盘切换等新功能添加首次使用提示
2. **预设分享**: 允许用户导出/导入筛选预设
3. **搜索历史**: 记录最近的搜索关键词，快速重复搜索
4. **卡片对比**: 在详情页支持与其他卡片对比（并排显示）

---

**优化完成！主人可以测试这些新功能啦！** 🐋✨
