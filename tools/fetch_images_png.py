#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把卡图**原图 PNG** 直接塞进 App 的 assets（真·离线原图，无损）。

和 fetch_images.py 的区别：
  - fetch_images.py      ：下载 PNG → 转 WebP（体积小，有损）
  - 本脚本               ：下载 PNG → 原样放进 assets/cards/{code}.png

会优先复用 work/img_tmp/ 里已下好的 PNG，避免重复下载。

用法：
    python tools/fetch_images_png.py --all --workers 12 --proxy http://127.0.0.1:10809
    python tools/fetch_images_png.py --limit 50
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import threading
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = "https://lycee-tcg.com/card/image/{code}.png"
OUTDIR = "assets/cards"
CACHE = os.path.join("work", "img_tmp")
UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"

_lock = threading.Lock()
_stat = {"ok": 0, "copy": 0, "skip": 0, "fail": 0}
_sizes = []


def load_codes():
    with open("assets/data/cards_app.json", encoding="utf-8") as f:
        cards = json.load(f)
    return [c["code"] for c in cards if (c.get("name") or c.get("name_zh"))]


def one(code, op, tries=3):
    dst = os.path.join(OUTDIR, f"{code}.png")
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        return code, "skip", os.path.getsize(dst)

    # 1) 复用已经下好的原图缓存
    cached = os.path.join(CACHE, f"{code}.png")
    if os.path.exists(cached) and os.path.getsize(cached) > 1000:
        shutil.copyfile(cached, dst)
        return code, "copy", os.path.getsize(dst)

    # 2) 现下
    last = ""
    for i in range(tries):
        try:
            req = urllib.request.Request(BASE.format(code=code), headers={"User-Agent": UA})
            with op.open(req, timeout=60) as r:
                data = r.read()
            if len(data) < 1000:
                return code, "空图", 0
            tmp = dst + ".part"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, dst)
            return code, "ok", len(data)
        except Exception as e:  # noqa: BLE001
            last = str(e)[:40]
            time.sleep(1.2 * (i + 1))
    return code, f"失败 {last}", 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=12)
    ap.add_argument("--proxy", default=None)
    a = ap.parse_args()

    os.makedirs(OUTDIR, exist_ok=True)
    codes = load_codes()
    if not a.all:
        codes = codes[: a.limit or 50]

    op = urllib.request.build_opener(
        urllib.request.ProxyHandler({"http": a.proxy, "https": a.proxy}) if a.proxy
        else urllib.request.ProxyHandler({})
    ) if a.proxy else urllib.request.build_opener(urllib.request.ProxyHandler({}))

    todo = [c for c in codes
            if not (os.path.exists(os.path.join(OUTDIR, f"{c}.png"))
                    and os.path.getsize(os.path.join(OUTDIR, f"{c}.png")) > 1000)]
    print(f"目标 {len(codes)} 张（已有 {len(codes) - len(todo)} 张），"
          f"代理：{a.proxy or '直连'}，并发 {a.workers}", flush=True)

    t0 = time.time()
    done = 0
    fails = []
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = {ex.submit(one, c, op): c for c in todo}
        for fu in as_completed(futs):
            code, st, sz = fu.result()
            with _lock:
                done += 1
                if st in ("ok", "copy"):
                    _stat[st] += 1
                    _sizes.append(sz)
                elif st == "skip":
                    _stat["skip"] += 1
                else:
                    _stat["fail"] += 1
                    fails.append(f"{code}:{st}")
                if done % 200 == 0 or done == len(todo):
                    el = time.time() - t0
                    rate = done / el if el else 0
                    left = (len(todo) - done) / rate / 60 if rate else 0
                    avg = sum(_sizes) / len(_sizes) / 1024 if _sizes else 0
                    total = sum(_sizes) / 1024 / 1024 / 1024
                    print(f"  {done}/{len(todo)}  新增{_stat['ok']} 复用{_stat['copy']} "
                          f"失败{_stat['fail']}  {rate:.1f}张/s  平均{avg:.0f}KB  "
                          f"已占{total:.2f}GB  预计还剩 {left:.0f} 分钟", flush=True)

    print(f"完成：新增 {_stat['ok']}，复用缓存 {_stat['copy']}，跳过 {_stat['skip']}，"
          f"失败 {_stat['fail']}", flush=True)
    if fails:
        print("失败样例：" + "；".join(fails[:10]), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
