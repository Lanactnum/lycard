"""检查：带底栏的界面里，是否有滚动容器没有给底部留白（会被悬浮底栏压住）。

用法：python tools/check_bottom_pad.py
退出码 1 = 发现问题。
"""
import re
import sys

# 带底栏的界面（main.dart 的三个 tab + 它们的 part / 内嵌页）
TABS = [
    'lib/main.dart',
    'lib/pages/search_page.dart',
    'lib/pages/construct_page.dart',
    'lib/pages/mine_page.dart',
    'lib/pages/wish_page.dart',
    'lib/pages/settings_page.dart',
    'lib/pages/deck_extras.dart',
    'lib/pages/filter_page.dart',
]

SCROLL = r'(GridView|ListView|CustomScrollView|SingleChildScrollView)'
OK_MARK = ('kBottomBarSpace', '132', 'bottom: 1', 'SafeArea')

bad = []
for path in TABS:
    try:
        s = open(path, encoding='utf-8').read()
    except OSError:
        continue
    for m in re.finditer(SCROLL + r'[.\w]*(?:\.builder|\.separated)?\s*\(', s):
        # 只挑"纵向滚动 / 没写 scrollDirection"的（横向列表不会被底栏压）
        seg_start = m.end()
        # 找到这个调用的配对右括号
        depth = 1
        k = seg_start
        while k < len(s) and depth:
            if s[k] == '(':
                depth += 1
            elif s[k] == ')':
                depth -= 1
            k += 1
        body = s[seg_start:k]
        if 'Axis.horizontal' in body:
            continue
        # 内层嵌套（shrinkWrap + 禁用滚动）不受影响
        if 'NeverScrollableScrollPhysics' in body or 'shrinkWrap: true' in body:
            continue
        # CustomScrollView：底部留白可以写在里面的 SliverPadding 上
        if 'CustomScrollView' in m.group(1):
            if re.search(r'SliverPadding\(\s*padding:\s*(?:const\s*)?EdgeInsets[^;]*?kBottomBarSpace', s[m.start():m.start()+2500], re.S):
                continue
        # 固定高度的小窗口滚动区（弹层/横滑区）不算
        if re.search(r'SizedBox\(\s*height:|showModalBottomSheet|SafeArea', s[max(0, m.start() - 400):m.start()]):
            continue
        line = s[:m.start()].count('\n') + 1
        pm = re.search(r'padding:\s*(?:const\s*)?(EdgeInsets[^,;]*?\([^;]*?\)|EdgeInsets\.\w+)', body, re.S)
        if pm and any(mark in pm.group(1) for mark in OK_MARK):
            continue
        bad.append((path, line, m.group(1), pm.group(1)[:60] if pm else '无 padding'))

if bad:
    print('!! 这些滚动容器底部留白不足，会被悬浮底栏压住：')
    for path, line, kind, pad in bad:
        print(f'   {path}:{line}  {kind}  padding: {pad}')
    sys.exit(1)
# ── 另外查：贴在右下角的按钮（FAB / Positioned）有没有让开悬浮底栏 ──
BAR = ['lib/main.dart', 'lib/pages/search_page.dart', 'lib/pages/construct_page.dart',
       'lib/pages/mine_page.dart', 'lib/pages/wish_page.dart']
for path in BAR:
    try:
        s = open(path, encoding='utf-8').read()
    except OSError:
        continue
    for m in re.finditer(r'floatingActionButton:', s):
        seg = s[m.start():m.start() + 400]
        line = s[:m.start()].count(chr(10)) + 1
        # 页面开了 avoidBottomBar 就算让开了
        head = s[:m.start()]
        if 'avoidBottomBar: true' not in s:
            bad.append((path, line, 'floatingActionButton', '没开 avoidBottomBar'))
    for m in re.finditer(r'Positioned\([^)]*?bottom:\s*(\d+)', s, re.S):
        line = s[:m.start()].count(chr(10)) + 1
        v = int(m.group(1))
        # 卡图内部的小标签通常同时有 left/right，且内边距很小 —— 不算页面级贴底控件
        seg = s[m.start():m.start() + 120]
        if 'left:' in seg and 'right:' in seg:
            continue
        if v <= 40:
            bad.append((path, line, 'Positioned bottom', f'只有 {v}，会被底栏压住'))

if bad:
    print('!! 贴底控件没让开悬浮底栏：')
    for path, line, kind, why in bad:
        print(f'   {path}:{line}  {kind}  {why}')
    sys.exit(1)
print('OK 所有带底栏界面的滚动容器 + 贴底按钮都有留白')
