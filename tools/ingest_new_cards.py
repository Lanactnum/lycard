#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 `check_new_cards.py` 检出的新卡真正抓进来。

它只做一件事：**把新卡的字段补进 `cards_full.json`**，不碰翻译、不碰卡图、不打包。
后面的步骤各有各的工具，见 `tools/update_cards.sh`。

为什么不能直接跑 `fetch_list.py --pages 40`
--------------------------------------------
`fetch_list.py` 会**整体覆盖** `cards_full.json`（`OUT` 只在开头被打开一次、
循环里覆盖写），而且它优先读 `work/list_html/` 旧缓存。拿它"补新卡"会把已有的
9000 多张覆盖掉/写回旧数据。所以补数据必须走本工具：**只增不改**。

用法
----
    python tools/ingest_new_cards.py --dry-run     # 先看会补哪些，不落盘
    python tools/ingest_new_cards.py               # 真写
    python tools/ingest_new_cards.py --pages 8     # 只扫前 8 页
"""
import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))

from fetch_list import parse_page  # noqa: E402  复用官方列表页解析器

# 检测时存下的页面（work/list_fresh/<page>.html）—— 优先用它，少打官网
FRESH = os.path.join(ROOT, "work", "list_fresh")

NEW = os.path.join(ROOT, "work", "new_cards.json")
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
LIST = "https://lycee-tcg.com/card/?page={page}"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
CTX = ssl.create_default_context()  # 官方站证书合法，不降级


def build_opener(proxy):
    handlers = [urllib.request.HTTPSHandler(context=CTX)]  # type: list
    if proxy and proxy.lower() not in ("none", "off", ""):
        handlers.insert(0, urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    else:
        handlers.insert(0, urllib.request.ProxyHandler({}))
    return urllib.request.build_opener(*handlers)


def get(op, url, tries=3):
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with op.open(req, timeout=45) as r:
                return r.read().decode("utf-8", "ignore"), None
        except Exception as e:  # noqa: BLE001
            last = e
            if i < tries - 1:
                time.sleep(2.0 * (i + 1))
    return None, str(last)


def num_key(code):
    m = re.match(r"LO-(\d+)", code)
    return (int(m.group(1)) if m else 99999, code)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", type=int, default=0,
                    help="扫前 N 页；0 = 用 new_cards.json 里记的 last_new_page")
    ap.add_argument("--delay", type=float, default=1.0)
    ap.add_argument("--proxy", default="none")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--only-incomplete", action="store_true",
                    help="只处理「已入库但缺 kind」的卡（补字段时用，别每次全量重扫）")
    args = ap.parse_args()

    if not os.path.exists(NEW):
        print(f"找不到 {NEW}，先跑 python tools/check_new_cards.py --json", file=sys.stderr)
        return 2
    payload = json.load(open(NEW, encoding="utf-8"))
    want = set(payload["codes"])
    if args.only_incomplete:
        _cards = {c["code"]: c for c in json.load(open(FULL, encoding="utf-8"))}
        want = {c for c in want if not (_cards.get(c) or {}).get("kind")}
        print(f"只补缺 kind 的卡：{len(want)} 张")
    if not want:
        print("new_cards.json 里没有新卡")
        return 0

    pages = args.pages or payload.get("last_new_page") or 10
    print(f"待补 {len(want)} 张；扫前 {pages} 页（直连={args.proxy.lower() in ('none','off','')}）…")

    op = build_opener(args.proxy)
    found = {}
    reused = 0
    for page in range(1, pages + 1):
        cached = os.path.join(FRESH, f"{page}.html")
        if os.path.exists(cached) and os.path.getsize(cached) > 2000:
            html = open(cached, encoding="utf-8", errors="ignore").read()
            err = None
            reused += 1
        else:
            html, err = get(op, LIST.format(page=page))
            # 抓成功就落盘 —— 官网会间歇性握手超时，重试时能复用已抓到的页，
            # 否则每次都从头打一遍，永远到不了后面失败的页（实测卡在 25~39 页）。
            if html is not None:
                try:
                    os.makedirs(FRESH, exist_ok=True)
                    with open(cached, "w", encoding="utf-8") as fh:
                        fh.write(html)
                except Exception:  # noqa: BLE001
                    pass
        if html is None:
            print(f"  第 {page} 页失败：{err}", flush=True)
            time.sleep(args.delay * 2)
            continue
        for c in parse_page(html):
            if c.get("code") in want:
                found[c["code"]] = c
        print(f"  第 {page} 页：累计命中 {len(found)}/{len(want)}", flush=True)
        if len(found) == len(want):
            break
        time.sleep(args.delay)

    missing = sorted(want - set(found), key=num_key)
    if missing:
        print(f"\n⚠️ 这 {len(missing)} 张没在扫过的页里找到（可能页数不够）：")
        for c in missing[:20]:
            print("   ", c)

    if not found:
        print("一张也没抓到，不落盘")
        return 2

    cards = json.load(open(FULL, encoding="utf-8"))
    by_code = {c["code"]: c for c in cards}
    added = updated = 0
    for code, rec in found.items():
        if code in by_code:
            by_code[code].update(rec)
            updated += 1
        else:
            by_code[code] = rec
            added += 1

    sample = found[sorted(found, key=num_key)[0]]
    if reused:
        print(f"  （其中 {reused} 页复用检测时的缓存，没再打官网）")
    print(f"\n解析样本：{sample.get('code')} | {sample.get('name')} | "
          f"{sample.get('color')} AP{sample.get('ap')} DP{sample.get('dp')} | "
          f"效果 {len(sample.get('effect_jp') or '')} 字")
    print(f"　新增 {added} 张，更新 {updated} 张；cards_full 由 {len(cards)} → {len(by_code)}")

    if args.dry_run:
        print("--dry-run，不写盘")
        return 0

    out = sorted(by_code.values(), key=lambda c: num_key(c.get("code", "")))
    tmp = FULL + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    os.replace(tmp, FULL)
    print(f"已写 {FULL}（{len(out)} 张）")
    print("\n下一步：")
    print("  python tools/make_app_data.py             # 生成 cards_app.json")
    print("  python tools/fetch_images_png.py --all    # 只下缺的图（已有的会跳过）")
    print("  bash tools/update_cards.sh --translate    # 翻译新卡 + 重建索引 + 打包")
    return 0


if __name__ == "__main__":
    sys.exit(main())
