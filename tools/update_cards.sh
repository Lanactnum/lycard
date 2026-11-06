#!/usr/bin/env bash
# 卡表更新通道 —— 一条命令走完「检测 → 入库 → 取图 → 翻译 → 打包」
#
# 为什么要有这个脚本
# ------------------
# 这几步的先后顺序是**有依赖的**，单独跑很容易漏步或顺序错：
#     检测(check) → 入库(ingest：补 cards_full) → 生成 App 数据(make_app_data)
#     → 取图(fetch_images：只下缺的) → 翻译(新卡的 name/effect) → 合并翻译
#     → 重建检索索引 → 重新打包
# 漏掉任何一步都会出现「卡有了但搜不到 / 有卡没图 / 打包了但翻译没进去」。
#
# 用法
# ----
#     bash tools/update_cards.sh check     # 只看有没有新卡（几秒~1 分钟，不写任何数据）
#     bash tools/update_cards.sh ingest    # 检测 + 把新卡数据补进 cards_full（不翻译不打包）
#     bash tools/update_cards.sh full      # 全流程（翻译要用 API，会花钱；打包要 1~2 分钟）
#
# 环境变量
# --------
#     LY_DELAY=1.0      每页间隔（官方站会限流，别调太小）
#     LY_FORCE=1        无视 12 小时冷却期（默认会跳过，防止把站点锤到封 IP）
#     LY_WORKERS=8      取图并发
#     SKIP_TRANSLATE=1  full 里跳过翻译（只补数据/图）
#
set -u
cd "$(dirname "$0")/.." || exit 1

MODE="${1:-check}"
DELAY="${LY_DELAY:-1.0}"
WORKERS="${LY_WORKERS:-8}"

step() { printf '\n\033[1m══ %s ══\033[0m\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

[ -f assets/data/cards_app.json ] || die "不在项目根目录（找不到 assets/data/cards_app.json）"

# ─────────────────────────────────────────────────────────────
step "① 检测新卡"
python tools/check_new_cards.py --json --delay "$DELAY" ${LY_FORCE:+--force}
RC=$?
if [ "$RC" -eq 2 ]; then
  die "检测失败（网络/解析）。这**不代表**没有新卡，别当成「已是最新」。"
fi
if [ "$RC" -eq 0 ]; then
  echo "没有新卡。"
  [ "$MODE" = "check" ] && exit 0
  # ingest/full 模式下没新卡也继续：可能是要补翻译或重新打包
fi

[ "$MODE" = "check" ] && { echo; echo "只看检测结果，结束（没有写任何数据）。"; exit 0; }

# ─────────────────────────────────────────────────────────────
step "② 把新卡字段补进 cards_full.json（只增不改）"
python tools/ingest_new_cards.py --delay "$DELAY" || die "入库失败"

step "③ 生成 App 用的 cards_app.json"
python tools/make_app_data.py || die "make_app_data 失败"

if [ "$MODE" = "ingest" ]; then
  echo
  echo "已补数据。下一步（要图/要翻译/要出包）跑："
  echo "    python tools/fetch_images_png.py --all"
  echo "    bash tools/update_cards.sh full"
  exit 0
fi

# ─────────────────────────────────────────────────────────────
step "④ 取卡图（已存在的会跳过，所以天然增量）"
python tools/fetch_images_png.py --all --workers "$WORKERS" || echo "⚠️ 取图有失败项，可重复跑本步续传"

# ─────────────────────────────────────────────────────────────
if [ "${SKIP_TRANSLATE:-0}" != "1" ]; then
  step "⑤ 翻译缺失的卡名/效果"
  if [ -f tools/translate_missing_cards.py ]; then
    python tools/translate_missing_cards.py || die "翻译失败（检查 TR_BASE/TR_KEY/TR_MODEL）"
  else
    echo "⚠️ 没有 tools/translate_missing_cards.py，跳过翻译"
  fi
fi

step "⑥ 合并翻译 + 重建检索索引（不重建的话新补的中文名搜不到）"
python tools/merge_translations.py || die "合并翻译失败"
python tools/make_app_data.py || die "make_app_data 失败"
python tools/build_search_keys.py || die "重建索引失败"
python - <<'PY' || die "压缩索引失败"
import gzip, os, shutil
src = "assets/data/search_keys.json"
dst = "assets/data/search_keys.json.gz"
if not os.path.exists(src):
    raise SystemExit("build_search_keys 没产出 search_keys.json")
raw = open(src, "rb").read()
with gzip.open(dst, "wb", compresslevel=9) as f:
    f.write(raw)
os.remove(src)            # 中间产物：12.7MB，压完就删（仓库里只留 .gz）
print(f"索引 {len(raw)/1e6:.1f} MB → gz {os.path.getsize(dst)/1e6:.1f} MB")
PY

# ─────────────────────────────────────────────────────────────
step "⑦ 重新打包数据包"
if [ -d assets/cards ] && [ "$(ls -A assets/cards 2>/dev/null | head -1)" ]; then
  python tools/build_pack.py || die "打包失败"
  echo "记得把 release/lycee_cards.pack 拆卷/上传（见 tools/join_cards_pack.py 的说明）"
else
  echo "⚠️ assets/cards 空的，跳过打包"
fi

step "完成"
echo "下一步："
echo "  1) flutter build apk ...（卡数据在 assets 里，要出新 APK 才会进包）"
echo "  2) 或者只发热更数据包 —— 见 tools/make_data_update.py"
