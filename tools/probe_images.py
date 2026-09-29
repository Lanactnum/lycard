#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""探测卡图体积，估算全量离线包的规模。

    python tools/probe_images.py LO-0001 LO-0002 LO-1000
"""
import io
import json
import os
import ssl
import struct
import sys
import urllib.request

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
PROXY = os.environ.get("HTTPS_PROXY") or ""


def opener():
    h = [urllib.request.HTTPSHandler(context=CTX)]
    h.insert(0, urllib.request.ProxyHandler(
        {"http": PROXY, "https": PROXY} if PROXY else {}))
    return urllib.request.build_opener(*h)


def png_size(data: bytes):
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        w, h = struct.unpack(">II", data[16:24])
        return w, h
    return None, None


def main():
    codes = sys.argv[1:] or ["LO-0001", "LO-0002", "LO-1000"]
    op = opener()
    total = 0
    for c in codes:
        url = f"https://lycee-tcg.com/card/image/{c}.png"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with op.open(req, timeout=60) as r:
                d = r.read()
            w, h = png_size(d)
            total += len(d)
            print(f"{c}: {len(d)/1024:.0f} KB  尺寸 {w}x{h}")
        except Exception as e:  # noqa: BLE001
            print(f"{c}: 失败 {str(e)[:80]}")
    if total:
        avg = total / len(codes)
        print(f"\n平均 {avg/1024:.0f} KB/张")
        print(f"9811 张全量原图 ≈ {avg*9811/1024/1024/1024:.2f} GB")
        # 压缩到 300px 宽 WebP 的粗略估算（约 1/8）
        print(f"若压成 300px WebP（约 40KB/张）≈ {40*9811/1024:.0f} MB")
        print(f"若压成 200px WebP（约 18KB/张）≈ {18*9811/1024:.0f} MB")


if __name__ == "__main__":
    main()
