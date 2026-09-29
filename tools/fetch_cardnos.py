#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""遍历 lycee-tcg.com 官方卡表分页，收集全部卡号。

官方卡表：https://lycee-tcg.com/card/?page=N ，每页 10 张。
本机直连被挡，必须走代理（默认 127.0.0.1:10809）。

产出：work/cardnos.json   形如 {"count": 9763, "codes": ["LO-0001", ...]}
"""
import json
import os
import re
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "work", "cardnos.json")
LIST = "https://lycee-tcg.com/card/?page={page}"
PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
OP = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}),
    urllib.request.HTTPSHandler(context=CTX),
)

CODE_RE = re.compile(r"cardno=([A-Za-z0-9\-]+)")


def fetch_page(page, tries=4):
    for i in range(tries):
        try:
            req = urllib.request.Request(LIST.format(page=page),
                                         headers={"User-Agent": UA})
            with OP.open(req, timeout=60) as r:
                html = r.read().decode("utf-8", "ignore")
            codes = sorted(set(CODE_RE.findall(html)))
            return page, codes, None
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                return page, [], str(e)
            time.sleep(1.5 * (i + 1))
    return page, [], "unknown"


def main():
    max_page = int(sys.argv[1]) if len(sys.argv) > 1 else 1100
    all_codes: set[str] = set()
    empty_streak = 0
    page = 1
    t0 = time.time()

    while page <= max_page and empty_streak < 3:
        batch = list(range(page, min(page + 8, max_page + 1)))
        with ThreadPoolExecutor(max_workers=4) as ex:
            futs = [ex.submit(fetch_page, p) for p in batch]
            results = {}
            for f in as_completed(futs):
                p, codes, err = f.result()
                results[p] = codes
        for p in batch:
            codes = results.get(p, [])
            if codes:
                all_codes.update(codes)
                empty_streak = 0
            else:
                empty_streak += 1
        page += len(batch)
        if page % 100 < 9:
            print(f"  到第 {page} 页，累计 {len(all_codes)} 个卡号"
                  f"（{time.time() - t0:.0f}s）", flush=True)
            os.makedirs(os.path.dirname(OUT), exist_ok=True)
            with open(OUT, "w", encoding="utf-8") as f:
                json.dump({"count": len(all_codes),
                           "codes": sorted(all_codes)}, f, ensure_ascii=False)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump({"count": len(all_codes), "codes": sorted(all_codes)},
                  f, ensure_ascii=False)
    print(f"完成：{len(all_codes)} 个卡号 -> {OUT}（{time.time() - t0:.0f}s）")


if __name__ == "__main__":
    main()
