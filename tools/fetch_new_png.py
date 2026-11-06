#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只下「新卡」的原图 PNG（给数据包用），不动 assets/cards 里的 WebP。

为什么要单独一个
----------------
`fetch_images_png.py` 是给「全量重下原图」写的，输出目录固定 `assets/cards/`。
但那个目录现在是**给 APK 用的 WebP**（平均 50KB），把 PNG（平均 363KB）混进去
会让打包和体积统计全乱。所以新卡的原图单独放 `work/img_png_new/`，
再由 `extend_pack.py` 追加进数据包。

断点续传：已存在且 >1KB 的跳过。官网对 `/card/image/` 限流很凶
（实测下到 ~128 张后全部握手超时），所以**反复跑这个脚本是正常用法**。

用法
----
    python tools/fetch_new_png.py                 # 下全部还没下的
    python tools/fetch_new_png.py --limit 60      # 一次下 60 张
    python tools/fetch_new_png.py --workers 3     # 保守一点
"""
import argparse
import json
import os
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NEW = os.path.join(ROOT, "work", "new_cards.json")
OUTDIR = os.path.join(ROOT, "work", "img_png_new")
BASE = "https://lycee-tcg.com/card/image/{code}.png"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
CTX = ssl.create_default_context()


def build_opener(proxy):
    handlers = [urllib.request.HTTPSHandler(context=CTX)]  # type: list
    if proxy and proxy.lower() not in ("none", "off", ""):
        handlers.insert(0, urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    else:
        handlers.insert(0, urllib.request.ProxyHandler({}))
    return urllib.request.build_opener(*handlers)


def one(code, op, tries=3):
    dst = os.path.join(OUTDIR, f"{code}.png")
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        return code, "skip", os.path.getsize(dst)
    last = ""
    for i in range(tries):
        try:
            req = urllib.request.Request(BASE.format(code=code), headers={"User-Agent": UA})
            with op.open(req, timeout=25) as r:
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
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--proxy", default="none")
    a = ap.parse_args()

    codes = json.load(open(NEW, encoding="utf-8"))["codes"]
    os.makedirs(OUTDIR, exist_ok=True)
    todo = [c for c in codes if not (
        os.path.exists(os.path.join(OUTDIR, f"{c}.png"))
        and os.path.getsize(os.path.join(OUTDIR, f"{c}.png")) > 1000)]
    if a.limit:
        todo = todo[: a.limit]

    print(f"新卡 {len(codes)} 张；已有 {len(codes)-len(todo)} 张；本次下 {len(todo)} 张")
    if not todo:
        print("都下好了")
        return 0

    op = build_opener(a.proxy)
    ok = skip = fail = 0
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = {ex.submit(one, c, op): c for c in todo}
        for n, f in enumerate(as_completed(futs), 1):
            code, status, size = f.result()
            if status == "ok":
                ok += 1
            elif status == "skip":
                skip += 1
            else:
                fail += 1
            if n % 20 == 0 or n == len(todo):
                print(f"  {n}/{len(todo)}  成功{ok} 跳过{skip} 失败{fail}  "
                      f"({time.time()-t0:.0f}s)", flush=True)

    total = sum(os.path.getsize(os.path.join(OUTDIR, f)) for f in os.listdir(OUTDIR))
    print(f"\n完成：成功 {ok} / 失败 {fail}；目录共 {len(os.listdir(OUTDIR))} 个文件，"
          f"{total/1048576:.1f} MB")
    if fail:
        print("有失败项：等官网解封后再跑一次本脚本（已下的会跳过）")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
