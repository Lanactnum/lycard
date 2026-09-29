#!/usr/bin/env bash
# 逐条核实要求清单的完成情况（对照代码，不抄摘要）
# 用法：bash tools/audit_requirements.sh
cd "$(dirname "$0")/.." || exit 1

chk() {  # chk "要求" "grep 模式" "在哪些文件里找"
  local label="$1" pat="$2" files="$3"
  local n
  n=$(grep -rl -- "$pat" $files 2>/dev/null | head -3 | tr '\n' ' ')
  if [ -n "$n" ]; then
    echo "  ✅ $label   ← $n"
  else
    echo "  ❌ $label   ← 没找到「$pat」"
  fi
}

echo "=== L13 缓存清理 + 垃圾桶 ==="
chk "缓存清理" "垃圾桶\|trash\|15" "lib/pages/storage_page.dart lib/data/storage.dart"

echo "=== L23 想要/出卡 + 品相 + 实拍图 ==="
chk "想要/出卡" "wish\|出卡" "lib/pages/wish_page.dart"
chk "品相" "品相\|condition" "lib/pages/wish_page.dart lib/models/*.dart"
chk "实拍图" "实拍\|photo\|imageFile" "lib/pages/wish_page.dart lib/models/*.dart"

echo "=== L27 缺卡统计 + 成本 ==="
chk "缺卡统计" "missing\|缺卡" "lib/data/*.dart lib/pages/*.dart"

echo "=== L29 抢卡冲突 ==="
chk "冲突标记" "conflict" "lib/data/*.dart lib/pages/*.dart"

echo "=== L35 胜负记录 ==="
chk "胜负" "wins\|losses\|胜负" "lib/models/*.dart lib/pages/*.dart"

echo "=== L37 MVP + 心得 ==="
chk "MVP" "mvp\|MVP" "lib/ --include=*.dart"
chk "心得/自定义内容" "心得\|note\b" "lib/models/*.dart"

echo "=== L39 版本快照 ==="
chk "快照" "snapshot" "lib/models/*.dart lib/pages/*.dart"

echo "=== L43 自定义卡信息 ==="
chk "卡编辑" "CardOverride\|card_edit" "lib/models/card_edit.dart"

echo "=== L55 罕贵度角标 ==="
chk "罕贵度" "rarity\|罕贵" "lib/widgets/rarity_badge.dart"

echo "=== L75 构筑封面编辑 ==="
chk "封面" "setDeckCover\|封面" "lib/state/app_state.dart"

echo "=== L77 卡面存相册 ==="
chk "存相册" "相册\|gallery\|saveImage" "lib/ --include=*.dart"

echo "=== L81 默认数字键盘 ==="
chk "数字键盘" "TextInputType.number" "lib/ --include=*.dart"

echo "=== L95 默认界面 ==="
chk "默认界面" "startTab\|默认界面" "lib/state/app_state.dart lib/pages/*.dart"

echo "=== L113 应用图标 ==="
chk "图标自定义" "icon\|图标" "lib/pages/look_page.dart"

echo "=== L117 背景编辑（裁剪/旋转/遮罩/亮度）==="
chk "裁剪/旋转" "crop\|rotate\|裁剪\|旋转" "lib/ --include=*.dart"
chk "遮罩/亮度" "mask\|brightness\|遮罩\|亮度" "lib/ --include=*.dart"

echo "=== L119 震动 ==="
chk "震动" "Haptics\." "lib/ --include=*.dart"

echo "=== L121 悬浮窗（系统级）==="
chk "SYSTEM_ALERT_WINDOW" "SYSTEM_ALERT_WINDOW" "android/app/src/main/AndroidManifest.xml"

echo "=== L126/128 卡片悬浮 ==="
chk "HoverCard" "HoverCard" "lib/ --include=*.dart"

echo "=== L92 统计图 ==="
chk "DeckStats" "DeckStats" "lib/ --include=*.dart"
