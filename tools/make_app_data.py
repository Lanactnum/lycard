#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App 真正打包用的数据文件：去掉萌卡社相关字段。

输出 assets/data/cards_app.json，字段只保留：
  code / name / title_jp / name_zh / color / cost / ex / ap / dp / sp / dmg /
  type / kind / rarity / series / illustrator / release / effect_jp / effect_zh /
  leader / restriction / img

不写入：萌卡社的 effect（机翻原文）、cid。
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
TR = os.path.join(ROOT, "assets", "data", "translations_zh.json")
OUT = os.path.join(ROOT, "assets", "data", "cards_app.json")

KEEP = ["code", "name", "title_jp", "color", "cost", "ex", "ap", "dp", "sp",
        "dmg", "type", "kind", "limit", "rarity", "series", "illustrator",
        "release", "effect_jp", "leader", "restriction", "img"]


def main():
    cards = json.load(open(FULL, encoding="utf-8"))
    tr = json.load(open(TR, encoding="utf-8")) if os.path.exists(TR) else {}

    out = []
    for c in cards:
        code = c.get("code", "")
        t = tr.get(code) or {}
        rec = {k: c.get(k) for k in KEEP if c.get(k) is not None}
        rec["code"] = code
        rec["name_zh"] = t.get("name") or ""
        rec["effect_zh"] = t.get("effect") or ""
        # 离线图片（原图 PNG，走数据包/RES）
        rec["img"] = f"assets/cards/{code}.png"
        out.append(rec)

    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False)
    size = os.path.getsize(OUT) / 1024 / 1024
    named = len([r for r in out if (r.get("name") or "").strip()])
    zh = len([r for r in out if (r.get("name_zh") or "").strip()])
    banned = [k for k in ("effect", "cid") if any(k in r for r in out)]
    print(f"输出 {OUT}（{size:.1f} MB）")
    print(f"  条数 {len(out)}，有日文名 {named}，有中文名 {zh}")
    print(f"  萌卡社字段残留：{banned or '无 ✅'}")


if __name__ == "__main__":
    sys.exit(main())
