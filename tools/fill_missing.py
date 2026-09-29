#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补齐缺失的卡片数据：先试官方站（限流解封后可用），失败再走 Wayback。

给 cron 用：每次只跑一小批、低并发，跑完就退出，反复跑直到补满。

    python tools/fill_missing.py --max 200 --workers 2

判断「缺失」= cards_full.json 里没有 color 字段的那些卡。
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_official import opener, fetch_one as official_one, RAW_DIR  # noqa: E402
from fetch_wayback import fetch_one as wayback_one  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=200)
    ap.add_argument("--workers", type=int, default=2)
    args = ap.parse_args()

    if not os.path.exists(FULL):
        print("还没有 cards_full.json，先跑 fetch_wayback.py")
        return 0
    cards = json.load(open(FULL, encoding="utf-8"))
    missing = [c["code"] for c in cards if not c.get("color")]
    print(f"缺数据 {len(missing)} / {len(cards)}")
    if not missing:
        print("已经齐了")
        return 0

    from concurrent.futures import ThreadPoolExecutor, as_completed
    op = opener(PROXY)
    targets = missing[: args.max]
    filled = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(official_one, op, c, 2, True): c for c in targets}
        for f in as_completed(futs):
            code, info, err = f.result()
            if not info:
                continue
            for c in cards:
                if c["code"] == code:
                    c.update({
                        "name": info.get("name_official") or c.get("name"),
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
                        "source": "official",
                    })
                    filled += 1
                    break

    with open(FULL, "w", encoding="utf-8") as f:
        json.dump(cards, f, ensure_ascii=False)
    remain = len([c for c in cards if not c.get("color")])
    print(f"本轮补了 {filled} 张，还缺 {remain} 张")
    return 0


if __name__ == "__main__":
    sys.exit(main())
