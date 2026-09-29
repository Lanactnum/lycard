#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用缓存的官方列表页，把卡片的**全部字段**重扫一遍，补上空缺。

比早期那个解析强的地方：
  · 线性扫 <td>，不依赖 <td rowspan="5"> 这种结构（有些卡没有卡图，早期就漏了）
  · 连 初出 / Version（系列）/ illust（画家）/ 效果原文 一起抓
  · 只填空缺，不覆盖已有值

用法：
    python tools/refill_from_cache.py            # 只报告
    python tools/refill_from_cache.py --apply    # 写回
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
APP = os.path.join(ROOT, "assets", "data", "cards_app.json")
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
DUMP = os.path.join(ROOT, "work", "refill.json")

CODE_RE = re.compile(r"^[A-Z]{2,4}-\d{3,5}[A-Z0-9\-]*$")


def clean(frag: str) -> str:
    t = re.sub(r"<br\s*/?>", "\n", frag)
    t = re.sub(r"<[^>]+>", "", t)
    t = html.unescape(t)
    t = t.replace("\r", "")
    return re.sub(r"[ \t\u3000]+", " ", t).strip()


def parse_pages() -> dict:
    out: dict = {}
    for f in sorted(glob.glob(os.path.join(LIST_DIR, "*.html"))):
        cells = [clean(c) for c in
                 re.findall(r"<td[^>]*>(.*?)</td>",
                            open(f, encoding="utf-8", errors="ignore").read(), re.S)]
        n = len(cells)
        idxs = [i for i, c in enumerate(cells) if CODE_RE.match(c)]
        for k, i in enumerate(idxs):
            code = cells[i]
            end = idxs[k + 1] if k + 1 < len(idxs) else n
            seg = cells[i + 1:end]
            rec: dict = {}

            # 名字：紧跟在卡号后、且不是「卡种/稀有度」的第一个非空
            if seg:
                rec["name"] = seg[0]
            if len(seg) > 1:
                rec["kind"] = seg[1]
            if len(seg) > 2:
                rec["rarity"] = seg[2]

            # 9 个数值
            for j, c in enumerate(seg):
                if c == "属性" and j + 8 < len(seg) and seg[j + 8] == "タイプ":
                    v = seg[j + 9:j + 18]
                    if len(v) == 9:
                        (rec["color"], rec["ex"], rec["cost"], rec["limit"],
                         rec["ap"], rec["dp"], rec["sp"], rec["dmg"],
                         rec["type"]) = v
                    break

            # 系列 / 画家 / 初出 / 效果
            for c in seg:
                if c.startswith("Version") and "series" not in rec:
                    rec["series"] = c.split(":", 1)[-1].strip()
                elif c.startswith("illust") and "illustrator" not in rec:
                    rec["illustrator"] = c.split(":", 1)[-1].strip()
                elif "初出" in c and c not in ("初出", "初出 :"):
                    rec["release"] = c.split(":", 1)[-1].strip()
                elif ("[" in c and "]" in c) and len(c) > 20 and "effect_jp" not in rec:
                    rec["effect_jp"] = c

            if rec.get("name"):
                out.setdefault(code, {}).update(
                    {k2: v2 for k2, v2 in rec.items() if v2 not in (None, "", "-")})
    return out


def main():
    apply = "--apply" in sys.argv
    data = parse_pages()
    print(f"解析出 {len(data)} 个卡号")
    print("  kind:", Counter(v.get("kind", "") for v in data.values()).most_common(5))
    for f in ("name", "series", "illustrator", "release", "effect_jp", "cost", "rarity"):
        print(f"  有 {f} 的: {sum(1 for v in data.values() if v.get(f))}")
    json.dump(data, open(DUMP, "w", encoding="utf-8"), ensure_ascii=False)
    print(f"明细已存 {DUMP}")

    if not apply:
        print("\n（加 --apply 才写回）")
        return 0

    for path, keys in (
        (APP, ("name", "series", "illustrator", "release", "effect_jp", "cost",
               "rarity", "kind", "limit", "type", "color", "ex", "ap", "dp",
               "sp", "dmg")),
        (FULL, ("name", "series", "illustrator", "release", "effect_jp", "cost",
                "rarity", "kind", "limit", "type", "color", "ex", "ap", "dp",
                "sp", "dmg")),
    ):
        cards = json.load(open(path, encoding="utf-8"))
        filled = Counter()
        still = []
        for c in cards:
            rec = data.get(c["code"])
            if not rec:
                still.append(c["code"])
                continue
            for k in keys:
                v = rec.get(k)
                if v is None or v == "":
                    continue
                if not c.get(k):
                    c[k] = v
                    filled[k] += 1
        json.dump(cards, open(path, "w", encoding="utf-8"),
                  ensure_ascii=False, separators=(",", ":"))
        print(f"写回 {os.path.basename(path)}："
              f"{dict(filled.most_common(10))}")
        if still:
            print(f"  缓存里找不到的卡号 {len(still)} 个：{still[:8]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
