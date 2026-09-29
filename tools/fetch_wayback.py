#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从 Wayback Machine 捞官方卡详情页（官方站把本机 IP 限流时的备用路线）。

Wayback 已存了约 6089 张卡的详情页（占 9952 张的 61%）。
用 /web/<年>id_/<原地址> 取「未经 Wayback 改写的原始页面」，结构跟官网一致，
可直接复用 fetch_official.parse_detail 解析。

用法：
    python tools/fetch_wayback.py --limit 20      # 试跑
    python tools/fetch_wayback.py --all --workers 4

产出：assets/data/cards_full.json（与官网抓取结果合并）
"""
import argparse
import json
import os
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_official import parse_detail  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
CARDS = os.path.join(DATA, "cards_raw.json")
FULL = os.path.join(DATA, "cards_full.json")
CACHE = os.path.join(ROOT, "work", "wayback_html")

PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
WB = "https://web.archive.org/web/2026id_/https://lycee-tcg.com/card/card_detail.pl?cardno={code}"

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
OP = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}),
    urllib.request.HTTPSHandler(context=CTX),
)


def fetch_one(code, tries=3):
    os.makedirs(CACHE, exist_ok=True)
    local = os.path.join(CACHE, f"{code}.html")
    if os.path.exists(local) and os.path.getsize(local) > 500:
        with open(local, encoding="utf-8", errors="ignore") as f:
            return code, parse_detail(f.read()), None
    for i in range(tries):
        try:
            req = urllib.request.Request(WB.format(code=code),
                                         headers={"User-Agent": UA})
            with OP.open(req, timeout=90) as r:
                html = r.read().decode("utf-8", "ignore")
            if len(html) < 500:
                return code, None, "内容过短"
            with open(local, "w", encoding="utf-8") as f:
                f.write(html)
            return code, parse_detail(html), None
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                return code, None, str(e)[:80]
            time.sleep(2 * (i + 1))
    return code, None, "unreachable"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    base = json.load(open(CARDS, encoding="utf-8"))
    codes = [c["code"] for c in base]
    if args.limit:
        codes = codes[: args.limit]
    elif not args.all:
        codes = codes[:10]

    print(f"共 {len(codes)} 张，代理 {PROXY}", flush=True)
    results, ok, fail = {}, 0, 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(fetch_one, c): c for c in codes}
        for n, f in enumerate(as_completed(futs), 1):
            code, info, err = f.result()
            if info:
                results[code] = info
                ok += 1
            else:
                fail += 1
            if n % 25 == 0 or n == len(codes):
                print(f"  {n}/{len(codes)}  成功 {ok}  失败 {fail}", flush=True)
                # 边跑边合并落盘
                merge_and_save(base, results)

    merge_and_save(base, results)
    print(f"完成：成功 {ok}，失败 {fail} -> {FULL}", flush=True)


def merge_and_save(base, results):
    by_code = {c["code"]: dict(c) for c in base}
    for code, info in results.items():
        by_code[code].update({
            "name": info.get("name_official") or by_code[code].get("name"),
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
            "source": "wayback",
        })
    with open(FULL, "w", encoding="utf-8") as f:
        json.dump(list(by_code.values()), f, ensure_ascii=False)


if __name__ == "__main__":
    main()
