#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""补跑指定的碎片文件（比如被拆开的 in_0059a.json / in_0059b.json）。

    python tools/run_fragments.py work/tr3 in_0059a.json in_0059b.json
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import translate_batch as T  # noqa: E402


def main():
    d = sys.argv[1]
    frags = sys.argv[2:]
    d = d if os.path.isabs(d) else os.path.join(ROOT, d)
    gloss = T.load_glossary()
    for frag in frags:
        inp = os.path.join(d, frag)
        outp = os.path.join(d, frag.replace("in_", "out_"))
        if os.path.exists(outp):
            print(f"{frag}: 已存在，跳过")
            continue
        items = json.load(open(inp, encoding="utf-8"))
        r, err = T.call_api(items, gloss, tries=3)
        if r is None:
            print(f"{frag}: 失败 {err}")
            continue
        json.dump({"items": r}, open(outp, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print(f"{frag}: 译好 {len(r)} 条")


if __name__ == "__main__":
    main()
