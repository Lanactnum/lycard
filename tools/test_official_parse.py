#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只用几张卡验证官方页解析是否正确，不动主卡表。

    python tools/test_official_parse.py LO-6665 LO-6971
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_official import opener, fetch_one  # noqa: E402

PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"


def main():
    codes = sys.argv[1:] or ["LO-6665", "LO-6971"]
    op = opener(PROXY)
    print(f"代理：{PROXY}\n")
    for code in codes:
        c, info, err = fetch_one(op, code, tries=2)
        print(f"===== {code} =====")
        if err:
            print("  失败:", err)
            continue
        print("  raw_stats_row:", info.get("raw_stats_row"))
        print("  series      :", info.get("series"))
        print("  illustrator :", info.get("illustrator"))
        print("  releaseInfo :", info.get("releaseInfo"))
        eff = (info.get("effect_jp") or "")[:220].replace("\n", " ")
        print("  effect_jp   :", eff)
        print("  rows        :", json.dumps(info.get("rows"), ensure_ascii=False)[:400])
        print()


if __name__ == "__main__":
    main()
