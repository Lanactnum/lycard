#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把卡表切成翻译批次，供分批翻译使用。

用法：
    python tools/make_translation_batches.py [每批张数，默认 150]

产出：
    work/translate/in_000.json ...  每批含 [{code, name, effect}]
    work/translate/index.json       批次清单
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
CARDS = os.path.join(ROOT, "assets", "data", "cards_raw.json")
OUT = os.path.join(ROOT, "work", "translate")


def main():
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 150
    sub = sys.argv[2] if len(sys.argv) > 2 else "translate"
    outdir = os.path.join(ROOT, "work", sub)
    src = FULL if os.path.exists(FULL) else CARDS
    if not os.path.exists(src):
        print(f"还没有卡表：{src}\n先跑 tools/fetch_list.py 或 fetch_cards.py")
        sys.exit(1)

    cards = json.load(open(src, encoding="utf-8"))
    # 只翻有原文的卡（没名字也没效果的没必要发出去）
    cards = [c for c in cards
             if (c.get("name") or "").strip() or (c.get("effect_jp") or "").strip()]
    os.makedirs(outdir, exist_ok=True)
    for f in os.listdir(outdir):
        if f.startswith("in_"):
            os.remove(os.path.join(outdir, f))

    batches = []
    for i in range(0, len(cards), size):
        chunk = cards[i:i + size]
        items = [
            {
                "code": c.get("code", ""),
                "name": c.get("name", ""),
                "effect_jp": c.get("effect_jp") or "",
                # 萌卡社的机翻中文，只作校对参考
                "ref_zh": c.get("effect", ""),
            }
            for c in chunk
        ]
        idx = i // size
        fn = f"in_{idx:04d}.json"
        with open(os.path.join(outdir, fn), "w", encoding="utf-8") as f:
            json.dump(items, f, ensure_ascii=False, indent=1)
        batches.append({"batch": idx, "file": fn, "out": f"out_{idx:04d}.json",
                        "count": len(items)})

    with open(os.path.join(outdir, "index.json"), "w", encoding="utf-8") as f:
        json.dump({"total_cards": len(cards), "batch_size": size,
                   "batches": batches}, f, ensure_ascii=False, indent=1)

    named = len([c for c in cards if (c.get("name") or "").strip()])
    print(f"共 {len(cards)} 张（有名字 {named}）-> {len(batches)} 批（每批 {size}）")
    print(f"来源：{os.path.basename(src)}")
    print(f"输出目录：{outdir}")


if __name__ == "__main__":
    main()
