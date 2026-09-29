#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从缓存的官方列表页里补齐几个之前漏掉的字段。

漏掉的原因：早期解析只认了「属性 EX コスト 制限 AP DP SP DMG タイプ」那一行，
但卡种（キャラクター / イベント / アイテム）在**名字后面那一格**，
而 制限 是「－－－●●●」这种两段式的符号格，早期也没取全。

用法：
    python tools/extract_extra_fields.py            # 只解析 + 打印报告
    python tools/extract_extra_fields.py --apply    # 写回 cards_full.json / cards_app.json
"""
from __future__ import annotations

import glob
import html
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIST_DIR = os.path.join(ROOT, "work", "list_html")
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
APP = os.path.join(ROOT, "assets", "data", "cards_app.json")
OUT = os.path.join(ROOT, "work", "extra_fields.json")


def clean(frag: str) -> str:
    t = re.sub(r"<br\s*/?>", "\n", frag)
    t = re.sub(r"<[^>]+>", "", t)
    t = html.unescape(t)
    return re.sub(r"[ \t\u3000]+", " ", t).strip()


def rows_of(blk: str):
    return re.findall(r"<tr[^>]*>(.*?)</tr>", blk, re.S)


def parse_page(page_html: str, out: dict):
    """线性扫一遍所有 <td>：卡号格后面紧跟 名字 / 卡种 / 稀有度；
    「属性…タイプ」这 9 个标题格之后的 9 格就是数值。"""
    cells = [clean(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", page_html, re.S)]
    code_re = re.compile(r"^[A-Z]{2,4}-\d{3,5}[A-Z0-9\-]*$")
    n = len(cells)
    i = 0
    while i < n:
        c = cells[i]
        if code_re.match(c) and i + 3 < n:
            code = c
            kind = cells[i + 2]
            rarity = cells[i + 3]
            rec = {"kind": kind, "rarity": rarity}
            # 往后找标题行
            for j in range(i + 4, min(i + 30, n - 17)):
                if cells[j] == "属性" and cells[j + 8] == "タイプ":
                    v = cells[j + 9:j + 18]
                    rec.update({
                        "color": v[0], "ex": v[1], "cost": v[2], "limit": v[3],
                        "ap": v[4], "dp": v[5], "sp": v[6], "dmg": v[7],
                        "type": v[8],
                    })
                    break
            out.setdefault(code, {}).update(rec)
            i += 4
            continue
        i += 1


def main():
    apply = "--apply" in sys.argv
    files = sorted(glob.glob(os.path.join(LIST_DIR, "*.html")))
    print(f"解析 {len(files)} 个列表页…")
    data: dict = {}
    for f in files:
        parse_page(open(f, encoding="utf-8", errors="ignore").read(), data)
    print(f"解析到 {len(data)} 个卡号")
    print("  kind 分布:", Counter(v.get("kind", "") for v in data.values()).most_common(6))
    n_limit = sum(1 for v in data.values() if v.get("limit"))
    print(f"  有 limit 的: {n_limit}")
    json.dump(data, open(OUT, "w", encoding="utf-8"), ensure_ascii=False)
    print(f"明细已存 {OUT}")

    # 抽样看一眼
    for code in list(data)[:3]:
        print("  样例", code, {k: v for k, v in data[code].items()})

    if not apply:
        print("\n（加 --apply 才会写回 assets/data/*.json）")
        return 0

    for path, fields in ((FULL, ("kind", "limit", "type", "rarity", "cost", "ex")),
                         (APP, ("kind", "limit", "type", "rarity", "cost", "ex"))):
        cards = json.load(open(path, encoding="utf-8"))
        hit = 0
        for c in cards:
            rec = data.get(c["code"])
            if not rec:
                continue
            for k in fields:
                v = rec.get(k)
                if v is None or v == "":
                    continue
                # 空值不覆盖已有内容
                if not c.get(k):
                    c[k] = v
                    hit += 1
        json.dump(cards, open(path, "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        print(f"写回 {os.path.basename(path)}：补了 {hit} 个字段值")
    return 0


if __name__ == "__main__":
    sys.exit(main())
