#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把卡图全部下载并转成 WebP，塞进 App 的 assets（离线可用）。

原图是 372x520 PNG（约 363KB），实测转成 WebP q80 只要 44KB —— 小 8 倍。
所以流程是：下载 PNG → ffmpeg 转 WebP → 删掉 PNG。

用法：
    python tools/fetch_images.py --limit 60      # 试跑 60 张
    python tools/fetch_images.py --all           # 全量（约 9811 张）
    python tools/fetch_images.py --all --proxy http://127.0.0.1:10809

断点续传：已存在的 .webp 会跳过。临时目录 work/img_tmp/。
"""
import argparse
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FULL = os.path.join(ROOT, "assets", "data", "cards_full.json")
OUTDIR = os.path.join(ROOT, "assets", "cards")
TMP = os.path.join(ROOT, "work", "img_tmp")
BASE = "https://lycee-tcg.com/card/image/{code}.png"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def make_opener(proxy):
    h = [urllib.request.HTTPSHandler(context=CTX)]
    h.insert(0, urllib.request.ProxyHandler(
        {"http": proxy, "https": proxy} if proxy else {}))
    return urllib.request.build_opener(*h)


def one(code, op, quality=95, tries=3, keep_orig=True):
    os.makedirs(OUTDIR, exist_ok=True)
    dst = os.path.join(OUTDIR, f"{code}.webp")
    if os.path.exists(dst) and os.path.getsize(dst) > 800:
        return code, "skip", os.path.getsize(dst)
    os.makedirs(TMP, exist_ok=True)
    png = os.path.join(TMP, f"{code}.png")
    have_png = os.path.exists(png) and os.path.getsize(png) > 1000
    if not have_png:
        for i in range(tries):
            try:
                req = urllib.request.Request(BASE.format(code=code),
                                             headers={"User-Agent": UA})
                with op.open(req, timeout=60) as r:
                    data = r.read()
                if len(data) < 1000:
                    return code, "空图", 0
                with open(png, "wb") as f:
                    f.write(data)
                break
            except Exception as e:  # noqa: BLE001
                if i == tries - 1:
                    return code, f"下载失败 {str(e)[:40]}", 0
                time.sleep(1.5 * (i + 1))
    try:
        r = subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", png,
             "-c:v", "libwebp", "-quality", str(quality),
             "-compression_level", "5", dst],
            capture_output=True, timeout=90)
        if r.returncode != 0 or not os.path.exists(dst):
            return code, "转码失败", 0
    finally:
        if not keep_orig:
            try:
                os.remove(png)
            except OSError:
                pass
    return code, "ok", os.path.getsize(dst)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--proxy", default=os.environ.get("HTTPS_PROXY") or "")
    ap.add_argument("--quality", type=int, default=80)
    args = ap.parse_args()

    cards = json.load(open(FULL, encoding="utf-8"))
    codes = [c["code"] for c in cards if (c.get("name") or "").strip()]
    if args.limit:
        codes = codes[: args.limit]

    done_before = len([f for f in os.listdir(OUTDIR)]) if os.path.isdir(OUTDIR) else 0
    print(f"目标 {len(codes)} 张（已有 {done_before} 张），"
          f"代理：{args.proxy or '直连'}，并发 {args.workers}", flush=True)

    op = make_opener(args.proxy)
    ok = fail = skip = 0
    total_bytes = 0
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(one, c, op, args.quality): c for c in codes}
        for n, f in enumerate(as_completed(futs), 1):
            code, status, size = f.result()
            if status == "ok":
                ok += 1
                total_bytes += size
            elif status == "skip":
                skip += 1
            else:
                fail += 1
            if n % 200 == 0 or n == len(codes):
                el = time.time() - t0
                print(f"  {n}/{len(codes)}  新增{ok} 跳过{skip} 失败{fail}  "
                      f"{n/max(el,1):.1f}张/s  已占 {total_bytes/1024/1024:.0f}MB  "
                      f"预计还剩 {(len(codes)-n)/max(n/max(el,1),0.01)/60:.0f} 分钟",
                      flush=True)
    print(f"完成：新增 {ok}，跳过 {skip}，失败 {fail}，"
          f"本次写入 {total_bytes/1024/1024:.0f} MB")


if __name__ == "__main__":
    main()
