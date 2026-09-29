#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从萌卡社 API 抓取 Lycee(kid=9) 全部卡片基础数据，存入 assets/data/cards_raw.json

萌卡社 TLS 证书已过期，所以用不校验证书的请求。
只依赖标准库，避免环境依赖问题。
"""
import json
import os
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

API = "https://www.moetcg.club/Api/search"
KID = 9  # Lycee
PAGE_SIZE = 30
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "data")
OUT_FILE = os.path.join(OUT_DIR, "cards_raw.json")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
HEADERS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0",
           "Accept": "application/json"}

# 萌卡社是国内站，必须绕开系统代理（代理开着时走代理会卡死）
OPENER = urllib.request.build_opener(
    urllib.request.ProxyHandler({}),
    urllib.request.HTTPSHandler(context=CTX),
)


def fetch_page(page, tries=5):
    url = f"{API}?page={page}&kid={KID}"
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with OPENER.open(req, timeout=45) as r:
                d = json.loads(r.read().decode("utf-8"))
            return page, d.get("data") or [], (d.get("pageInfo") or {}).get("total")
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(1.0 * (i + 1))
    print(f"[warn] page {page} 失败: {last}", flush=True)
    return page, [], None


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("[1/2] 取第 1 页，读总数 ...", flush=True)
    _, first, total = fetch_page(1)
    if not total:
        print("无法读取总数，退出", flush=True)
        sys.exit(1)
    pages = (total + PAGE_SIZE - 1) // PAGE_SIZE
    print(f"总数 {total} 张，共 {pages} 页", flush=True)

    cards = {}
    for c in first:
        cards[c["code"]] = c

    done = 1
    tmp = OUT_FILE + ".partial"
    with ThreadPoolExecutor(max_workers=6) as ex:
        futs = {ex.submit(fetch_page, p): p for p in range(2, pages + 1)}
        for f in as_completed(futs):
            page, data, _ = f.result()
            for c in data:
                cards[c["code"]] = c
            done += 1
            if done % 20 == 0:
                print(f"  {done}/{pages} 页，已收 {len(cards)} 张", flush=True)
                # 每 40 页落一次盘，中途挂掉也不白跑
                if done % 40 == 0:
                    with open(tmp, "w", encoding="utf-8") as fh:
                        json.dump(sorted(cards.values(), key=lambda x: x["code"]),
                                  fh, ensure_ascii=False)
                    print(f"    [checkpoint] 已保存 {len(cards)} 张", flush=True)

    out = sorted(cards.values(), key=lambda c: c["code"])
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"[2/2] 完成：{len(out)} 张 -> {OUT_FILE}", flush=True)


if __name__ == "__main__":
    main()
