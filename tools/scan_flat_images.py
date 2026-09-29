#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""再扫一遍卡图，这次专门找「纯色 / 近乎纯色」的图。

官方对没有卡图的卡号会返回一张极小的纯色 PNG（例如 LO-0583-X 是 1KB 的纯红），
放大到卡面就是一整块色块 —— 屏幕上看着就是个空白占位框。

判据：把图缩到 8x8，若 64 个像素三通道的标准差全都 < 8 → 纯色图。
"""
from __future__ import annotations

import json
import os
import statistics
import struct
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

SRC = os.path.join("assets", "cards")
OUT = os.path.join("work", "flat_images.json")


def png_size(p):
    d = open(p, "rb").read(33)
    if len(d) < 24:
        return (0, 0)
    return struct.unpack(">II", d[16:24])


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
    if len(d) < 192:
        return (fn[:-4], "解码失败", os.path.getsize(p), (0, 0))
    px = [tuple(d[i:i + 3]) for i in range(0, 192, 3)]
    sd = max(statistics.pstdev([t[c] for t in px]) for c in range(3))
    if sd < 8:
        avg = tuple(sum(t[c] for t in px) // len(px) for c in range(3))
        return (fn[:-4], f"纯色 rgb{avg} 波动{sd:.1f}",
                os.path.getsize(p), png_size(p))
    return None


def main():
    files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))
    print(f"扫描 {len(files)} 张…", flush=True)
    flats = []
    with ThreadPoolExecutor(max_workers=12) as ex:
        for i, res in enumerate(ex.map(probe, files), 1):
            if res:
                flats.append(res)
            if i % 2000 == 0:
                print(f"  {i}/{len(files)}  已发现 {len(flats)}", flush=True)

    print(f"纯色图 {len(flats)} 张：")
    for code, why, sz, dim in flats[:40]:
        print(f"  {code:14s} {why}  {sz/1024:.1f}KB  {dim[0]}x{dim[1]}")
    json.dump([{"code": c, "why": w, "size": s, "w": d[0], "h": d[1]}
               for c, w, s, d in flats], open(OUT, "w"),
              ensure_ascii=False, indent=1)
    print(f"名单已存 {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
