#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""合并翻译批次结果，生成 App 用的 assets/data/translations_zh.json

输入：work/translate/out_*.json
每条应为 {"code": "...", "name_zh": "...", "effect_zh": "..."}

输出：{ "LO-6665": {"name": "...", "effect": "..."}, ... }
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "work", "translate")
DST = os.path.join(ROOT, "assets", "data", "translations_zh.json")


def main():
    merged = {}
    files = sorted(glob.glob(os.path.join(SRC, "out_*.json")))
    for extra in ("translate2", "tr3"):
        files += sorted(glob.glob(os.path.join(
            os.path.dirname(SRC), extra, "out_*.json")))
    for fn in files:
        try:
            data = json.load(open(fn, encoding="utf-8"))
        except Exception as e:  # noqa: BLE001
            print(f"[skip] {os.path.basename(fn)}: {e}")
            continue
        if isinstance(data, dict) and "items" in data:
            data = data["items"]
        for it in data:
            code = (it.get("code") or "").strip()
            if not code:
                continue
            merged[code] = {
                "name": it.get("name_zh") or it.get("name") or "",
                "effect": it.get("effect_zh") or it.get("effect") or "",
            }

    os.makedirs(os.path.dirname(DST), exist_ok=True)
    with open(DST, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False)

    total = None
    cards = os.path.join(ROOT, "assets", "data", "cards_raw.json")
    if os.path.exists(cards):
        total = len(json.load(open(cards, encoding="utf-8")))

    print(f"合并 {len(files)} 个批次文件 -> {len(merged)} 条翻译")
    if total:
        print(f"覆盖率：{len(merged)}/{total} = {len(merged) / total:.1%}")
    print(f"输出：{DST}")
    if total and len(merged) < total:
        sys.exit(2)


if __name__ == "__main__":
    main()
