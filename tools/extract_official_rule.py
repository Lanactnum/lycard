#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 lycee-tcg.com/rule/index_N.html 提取正文文本。

官方规则页是「侧边导航 + 正文」的固定模板，正文在
<div id="contents"> 里、导航在 <div id="sidenav"> 里，
所以先切掉 sidenav、再去标签。

用法：python tools/extract_official_rule.py
输出：work/rule/text_N.txt（每页一份）+ 控制台预览
"""
import html
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "work", "rule")
TITLES = {
    1: "游戏准备",
    2: "卡片种类",
    3: "卡片的看法",
    4: "场地的构成",
    5: "游戏的进行",
    6: "战斗",
    7: "使用代偿与限制",
    8: "基本能力",
    9: "使用代偿图标说明",
}


def clean(h: str) -> str:
    # 去掉 script / style
    h = re.sub(r"(?is)<(script|style)[^>]*>.*?</\1>", " ", h)
    # 只保留 contents 块
    m = re.search(r'(?is)<div id="contents">(.*?)(?:<div id="footer"|<!--.*?footer)', h)
    if m:
        h = m.group(1)
    # 切掉侧边导航
    h = re.sub(r'(?is)<div id="sidenav">.*?</div>\s*</div>', " ", h)
    # 换行标签 → 真换行
    h = re.sub(r"(?i)<br\s*/?>", "\n", h)
    h = re.sub(r"(?i)</(p|div|li|h\d|tr|dd|dt)>", "\n", h)
    h = re.sub(r"(?i)</t[dh]>", " | ", h)
    h = re.sub(r"(?s)<[^>]+>", "", h)
    h = html.unescape(h)
    lines = [re.sub(r"[ \t\u3000]+", " ", l).strip() for l in h.split("\n")]
    out = []
    for l in lines:
        if not l or l in ("|", "&nbsp;"):
            continue
        # 侧边导航的残留条目
        if l in ("よくある質問(FAQ)", "ルール", "TOP", "ルール・Q&A"):
            continue
        out.append(l)
    return "\n".join(out)


def main():
    total = 0
    for i in sorted(TITLES):
        p = os.path.join(SRC, f"index_{i}.html")
        if not os.path.exists(p):
            print(f"!! 缺 {p}")
            continue
        txt = clean(open(p, encoding="utf-8", errors="ignore").read())
        dst = os.path.join(SRC, f"text_{i}.txt")
        open(dst, "w", encoding="utf-8").write(txt)
        total += len(txt)
        print(f"--- {i}. {TITLES[i]}  ({len(txt)} 字) ---")
        print(txt[:700])
        print()
    print(f"合计 {total} 字 → work/rule/text_N.txt")
    return 0


if __name__ == "__main__":
    sys.exit(main())
