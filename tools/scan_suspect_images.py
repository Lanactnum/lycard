#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫一遍所有卡图，找出「不是正常插画」的图（官方占位图）。

判据（都是把图缩到 8x8 后看像素）：
  · 接近白：64 格里超过 48 格三通道都 > 230   → 白底问号图
  · 灰阶  ：64 格里超过 52 格三通道差距 < 12  → 灰底问号图
正常插画几乎不会整张接近纯白或纯灰。

输出：work/suspect_images.json
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

SRC = os.path.join("assets", "cards")
OUT = os.path.join("work", "suspect_images.json")


def probe(fn: str):
    p = os.path.join(SRC, fn)
    try:
        r = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", p, "-vf", "scale=8:8",
             "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            capture_output=True, timeout=30)
    except Exception:
        return None
    d = r.stdout
    if len(d) < 64 * 3:
        return (fn[:-4], "解码失败", os.path.getsize(p))
    px = [tuple(d[i:i + 3]) for i in range(0, 192, 3)]
    near_white = sum(1 for t in px if min(t) > 230)
    grey = sum(1 for t in px if max(t) - min(t) < 12)
    if near_white > 48:
        return (fn[:-4], f"接近纯白({near_white}/64)", os.path.getsize(p))
    if grey > 52:
        return (fn[:-4], f"整张灰阶({grey}/64)", os.path.getsize(p))
    return None


def main():
    files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))
    print(f"扫描 {len(files)} 张…", flush=True)
    suspects = []
    with ThreadPoolExecutor(max_workers=12) as ex:
        for i, res in enumerate(ex.map(probe, files), 1):
            if res:
                suspects.append(res)
            if i % 2000 == 0:
                print(f"  {i}/{len(files)}  已发现 {len(suspects)}", flush=True)

    print(f"可疑 {len(suspects)} 张：")
    for code, why, sz in suspects[:30]:
        print(f"  {code:14s} {why}  {sz/1024:.0f}KB")
    json.dump([{"code": c, "why": w, "size": s} for c, w, s in suspects],
              open(OUT, "w"), ensure_ascii=False, indent=1)
    print(f"名单已存 {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
