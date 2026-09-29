#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「还没翻译的卡」重新切成更大的批次（已译的不重复提交）。

用法：
    python tools/make_remaining.py            # 每批 80 张
    python tools/make_remaining.py 100

产出：work/translate2/in_XXXX.json + index.json
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
OLD = os.path.join(ROOT, "work", "translate")
NEW = os.path.join(ROOT, "work", "translate2")


def translated_codes():
    done = set()
    for f in glob.glob(os.path.join(OLD, "out_*.json")) + \
             glob.glob(os.path.join(NEW, "out_*.json")):
        try:
            data = json.load(open(f, encoding="utf-8"))
        except Exception:  # noqa: BLE001
            continue
        items = data.get("items", data) if isinstance(data, dict) else data
        for it in items:
            if it.get("code"):
                done.add(it["code"])
    return done


def main():
    size = int(sys.argv[1]) if len(sys.argv) > 1 else 80
    cards = json.load(open(FULL, encoding="utf-8"))
    done = translated_codes()
    todo = [c for c in cards if c.get("code") not in done]
    print(f"卡表 {len(cards)} 张，已译 {len(done)} 张，待译 {len(todo)} 张")

    os.makedirs(NEW, exist_ok=True)
    for f in os.listdir(NEW):
        if f.startswith("in_"):
            os.remove(os.path.join(NEW, f))

    batches = []
    for i in range(0, len(todo), size):
        chunk = todo[i:i + size]
        items = [{
            "code": c.get("code", ""),
            "name": c.get("name", ""),
            "effect_jp": c.get("effect_jp") or "",
        } for c in chunk]
        idx = i // size
        with open(os.path.join(NEW, f"in_{idx:04d}.json"), "w",
                  encoding="utf-8") as f:
            json.dump(items, f, ensure_ascii=False, indent=1)
        batches.append({"batch": idx, "count": len(items)})

    json.dump({"total_cards": len(todo), "batch_size": size,
               "batches": batches},
              open(os.path.join(NEW, "index.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"切成 {len(batches)} 批（每批 {size}）-> {NEW}")


if __name__ == "__main__":
    main()
