#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把已经抓下来的 HTML 缓存重新解析成 cards_full.json（不再发请求）。

两个缓存目录都吃：
    work/raw_html/       官方详情页（fetch_official 存的）
    work/wayback_html/   Wayback 捞回来的详情页
列表页缓存在 work/list_html/ 则走 fetch_list.parse_page。

用法：
    python tools/rebuild_from_cache.py
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_official import parse_detail  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
CARDS = os.path.join(DATA, "cards_raw.json")
FULL = os.path.join(DATA, "cards_full.json")
SOURCES = [
    (os.path.join(ROOT, "work", "raw_html"), "official"),
    (os.path.join(ROOT, "work", "wayback_html"), "wayback"),
    (os.path.join(ROOT, "work", "wayback_fast"), "wayback"),
]


def main():
    if not os.path.exists(CARDS):
        print("缺少 assets/data/cards_raw.json")
        return 1
    base = json.load(open(CARDS, encoding="utf-8"))
    by_code = {c["code"]: dict(c) for c in base}

    # 0) 先吃列表页缓存（一次给 10 张，字段最全）
    try:
        from fetch_list import parse_page as parse_list_page
        list_dir = os.path.join(ROOT, "work", "list_html")
        files = sorted(glob.glob(os.path.join(list_dir, "*.html")))
        n = 0
        for f in files:
            try:
                cs = parse_list_page(open(f, encoding="utf-8",
                                          errors="ignore").read())
            except Exception:  # noqa: BLE001
                continue
            for info in cs:
                code = info.get("code")
                if not code or not info.get("color"):
                    continue
                rec = by_code.get(code) or {
                    "code": code, "cid": "", "name": "",
                    "img": f"https://lycee-tcg.com/card/image/{code}.png",
                    "effect": ""}
                rec.update({
                    "name": info.get("name") or rec.get("name"),
                    "title_jp": info.get("title_jp"),
                    "kind": info.get("kind"),
                    "rarity": info.get("rarity"),
                    "color": info.get("color"),
                    "ex": info.get("ex"),
                    "cost": info.get("cost"),
                    "limit": info.get("limit"),
                    "ap": info.get("ap"), "dp": info.get("dp"),
                    "sp": info.get("sp"), "dmg": info.get("dmg"),
                    "type": info.get("type"),
                    "leader": info.get("leader", False),
                    "restriction": info.get("limit") or None,
                    "series": info.get("series"),
                    "illustrator": info.get("illustrator"),
                    "release": info.get("release"),
                    "effect_jp": info.get("effect_jp"),
                    "source": "official-list",
                })
                by_code[code] = rec
                n += 1
        print(f"official-list: 解析 {n} 条（来自 {len(files)} 个列表页缓存）")
    except Exception as e:  # noqa: BLE001
        print("列表页缓存解析跳过：", e)

    total = 0
    for d, src in SOURCES:
        files = sorted(glob.glob(os.path.join(d, "*.html")))
        ok = 0
        for f in files:
            code = os.path.basename(f)[:-5]
            try:
                info = parse_detail(open(f, encoding="utf-8", errors="ignore").read())
            except Exception:  # noqa: BLE001
                continue
            if not info.get("color"):
                continue
            rec = by_code.get(code)
            if rec is None:
                rec = {"code": code, "cid": "", "img":
                       f"https://lycee-tcg.com/card/image/{code}.png", "effect": ""}
                by_code[code] = rec
            rec.update({
                "name": info.get("name_official") or rec.get("name"),
                "title_jp": info.get("title_jp"),
                "kind": info.get("kind"),
                "rarity": info.get("rarity"),
                "color": info.get("color"),
                "ex": info.get("ex"),
                "cost": info.get("cost"),
                "limit": info.get("limit"),
                "ap": info.get("ap"),
                "dp": info.get("dp"),
                "sp": info.get("sp"),
                "dmg": info.get("dmg"),
                "type": info.get("type"),
                "leader": info.get("is_leader", False),
                "restriction": info.get("limit") or None,
                "series": info.get("series"),
                "illustrator": info.get("illustrator"),
                "release": info.get("releaseInfo"),
                "effect_jp": info.get("effect_jp"),
                "source": src,
            })
            ok += 1
        print(f"{src}: 解析 {ok} / {len(files)} 个缓存页")
        total += ok

    out = list(by_code.values())
    with open(FULL, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    have = len([c for c in out if c.get("color")])
    print(f"合并完成：{have} / {len(out)} 张有完整数据 -> {FULL}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
