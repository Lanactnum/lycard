#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 lib/ 里所有**界面文案**抽成一份可直接编辑的清单。

只抓含中文的字符串字面量 —— 卡名、效果文本都在 assets/data/*.json 里，
不在代码中，所以天然不会被抓进来。

产出（默认）: D:\\Big Fat Fish\\工作区\\lycard界面文案.json

格式：
{
  "_说明": "...",
  "items": [
    {"id": 1, "file": "...", "line": 42, "where": "标题", "old": "检索", "new": "检索"},
    ...
  ]
}

改的话**只改 new**，old 一个字都别动（回写脚本靠 old 定位）。
改完跑 tools/apply_ui_strings.py 回写。
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
DEFAULT_OUT = r"D:\Big Fat Fish\工作区\lycard界面文案.json"

# 只抓这些形态的字符串：'...' 或 "..."，中间含中文
STR_RE = re.compile(r"""(?<![\w$])(['"])((?:(?!\1).)*?[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef](?:(?!\1).)*?)\1""")

# 明显不该进清单的（代码里的键名、路径等）
SKIP_PATTERNS = [
    re.compile(r"^[\w./\-]+$"),          # 纯 ASCII 标识符/路径
    re.compile(r"^assets/"),
]


def is_skippable(text: str) -> bool:
    if not text.strip():
        return True
    for p in SKIP_PATTERNS:
        if p.match(text):
            return True
    # 含换行的大段文本很可能是别的东西，也跳过
    if "\n" in text:
        return True
    return False


def guess_where(lines, idx):
    """往上找最近的语义线索，作为"这条在哪儿"的提示"""
    for j in range(idx, max(-1, idx - 30), -1):
        l = lines[j].strip()
        if not l:
            continue
        # 形如  labelText:   /   title:   /   Text(   /  tooltip:
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*(?:Text|label|title|tooltip|hint|message|subtitle|name))\s*:", l)
        if m:
            return m.group(1)
        m2 = re.search(r"(Text|Tooltip|SnackBar|AppBar|title|label|hint)\b", l)
        if m2:
            return m2.group(1)
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--dedupe", action="store_true",
                    help="相同文案只留一条（减少重复，但回写会全局替换）")
    args = ap.parse_args()

    # 纯算法/工具文件里没有界面文案，里面的字符串都是正则和分隔符
    SKIP_FILES = {"lib/data/search_index.dart"}

    files = []
    for base, _dirs, names in os.walk(LIB):
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            full = os.path.join(base, n)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            if rel in SKIP_FILES:
                continue
            files.append(full)
    files.sort()

    items = []
    seen = {}
    i = 0
    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        src = open(path, encoding="utf-8").read()
        lines = src.split("\n")
        # 跳过「导出/复制给外部的纯文本」函数体：那是数据，不是界面文案
        skip_ranges = []
        for _j, _l in enumerate(lines):
            if "exportText" in _l or "StringBuffer(" in _l:
                skip_ranges.append((_j, _j + 80))
        # 逐行扫（够用，且能给出准确行号）
        for ln, line in enumerate(lines, start=1):
            if any(a <= ln - 1 < b for a, b in skip_ranges):
                continue
            stripped = line.strip()
            if stripped.startswith("//"):
                continue          # 注释
            if "debugPrint" in line:
                continue          # 调试输出
            if "RegExp(" in line or "replaceAll(" in line:
                continue          # 正则/替换用的字符集，不是文案
            if "import " in line or "part of" in line:
                continue
            for m in STR_RE.finditer(line):
                text = m.group(2)
                if is_skippable(text):
                    continue
                i += 1
                items.append({
                    "id": i,
                    "file": rel,
                    "line": ln,
                    "where": guess_where(lines, ln - 1),
                    "old": text,
                    "new": text,
                })
                seen[text] = seen.get(text, 0) + 1

    if args.dedupe:
        uniq = {}
        for it in items:
            if it["old"] not in uniq:
                uniq[it["old"]] = it
        items = list(uniq.values())

    payload = {
        "_说明": (
            "这是 lycard 的全部界面文案。**只改 new 字段**，old 一个字都别动"
            "（回写脚本靠 old 定位）。改完把文件保存好，让我跑 "
            "tools/apply_ui_strings.py 回写并重新构建。"
            "同一条文案出现在多处时，回写会全部一起改。"
            "卡名/效果文本不在这里（它们在 assets/data 里）。"
        ),
        "_统计": {
            "条目数": len(items),
            "涉及文件": len({it["file"] for it in items}),
            "重复文案种类": len([k for k, v in seen.items() if v > 1]),
        },
        "items": items,
    }

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)

    print(f"抽出 {len(items)} 条界面文案，来自 {payload['_统计']['涉及文件']} 个文件")
    print(f"其中重复出现的文案 {payload['_统计']['重复文案种类']} 种")
    print(f"写到: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
