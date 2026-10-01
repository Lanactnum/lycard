#!/usr/bin/env bash
# 为 dist/ 里的旧版本 APK 生成「升到新版」的差分补丁。
#
# 为什么要它：APK 里 86% 是内置卡图，卡图在版本之间从不变化 —— 每次更新让用户
# 重下 573 MB 是纯浪费。补丁只含变化的那一小部分（实测 0.85.3→0.85.4 只要 12.6 MB）。
#
# 用法：
#     bash tools/make_patches.sh 0.85.5
#
# 它会给 dist/ 里**每一个**旧版本 × 每一个架构各生成一个补丁，命名成：
#     lycard-0.85.5-arm64.apk.from-0.85.4.lycpatch
# App 侧按「本机版本 + 本机架构」挑（见 lib/services/update_service.dart 的 pickPatch）。
#
# 注意：生成补丁需要**旧版本那个 APK 本体**，所以 dist/ 里的旧包别急着删 ——
# 至少留住最近两三个版本，否则老用户就只能下整包。

set -u
cd "$(dirname "$0")/.." || exit 1

NEW_VER="${1:-}"
if [ -z "$NEW_VER" ]; then
  echo "用法: bash tools/make_patches.sh <新版本号>   例: bash tools/make_patches.sh 0.85.5"
  exit 2
fi

DIST="dist"
made=0

for new in "$DIST"/lycard-"$NEW_VER"-*.apk; do
  [ -e "$new" ] || { echo "找不到 $DIST/lycard-$NEW_VER-*.apk —— 先把新版构建出来"; exit 1; }
  base=$(basename "$new")
  abi="${base#lycard-${NEW_VER}-}"     # arm64.apk / universal.apk
  abi="${abi%.apk}"

  # 同一个架构的所有旧版本
  for old in "$DIST"/lycard-*-"$abi".apk; do
    [ -e "$old" ] || continue
    oldbase=$(basename "$old")
    oldver=$(echo "$oldbase" | sed -n 's/^lycard-\([0-9][0-9.]*\)-.*/\1/p')
    [ -z "$oldver" ] && continue
    [ "$oldver" = "$NEW_VER" ] && continue

    out="$DIST/lycard-${NEW_VER}-${abi}.apk.from-${oldver}.lycpatch"
    echo "── $oldver → $NEW_VER ($abi) ──"
    python tools/make_delta.py "$old" "$new" -o "$out" || { echo "  生成失败"; continue; }
    # 顺手写个校验文件，和 APK 一样的规矩
    (cd "$DIST" && sha256sum "$(basename "$out")" \
        | sed "s# \*\{0,1\}$(basename "$out")#  $(basename "$out")#" \
        > "$(basename "$out").sha256")
    made=$((made + 1))
  done
done

echo
echo "共生成 $made 个补丁："
ls -lh "$DIST"/*.lycpatch 2>/dev/null | awk '{print "  " $5 "\t" $9}'
