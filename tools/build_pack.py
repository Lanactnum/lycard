#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 assets/cards/ 里的原图打包成**单个**数据包文件：

    release/lycee_cards.pack

文件结构（全是原图字节，零改动）：
    [0..7]    magic  b"LYCPACK1"
    [8..11]   索引长度 N（uint32 小端）
    [12..12+N) 索引 JSON： {"卡号": [相对偏移, 字节数], ...}
    [12+N..]  所有 PNG 首尾拼接

好处：整个数据包只有一个文件，从文件管理器里选一次就能导入。
"""
from __future__ import annotations

import json
import os
import sys

SRC = os.path.join("assets", "cards")
OUT = "release"
PACK = os.path.join(OUT, "lycee_cards.pack")
MAGIC = b"LYCPACK1"


def main():
    os.makedirs(OUT, exist_ok=True)
    files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))
    if not files:
        print("assets/cards 里没有 PNG，先跑 fetch_images_png.py")
        return 1

    # 先把索引算出来（相对偏移），再写文件
    index = {}
    rel = 0
    for fn in files:
        size = os.path.getsize(os.path.join(SRC, fn))
        index[fn[:-4]] = [rel, size]
        rel += size
    idx_bytes = json.dumps(index, separators=(",", ":"),
                           ensure_ascii=False).encode("utf-8")
    head = MAGIC + len(idx_bytes).to_bytes(4, "little")

    total = 0
    with open(PACK, "wb") as out:
        out.write(head)
        out.write(idx_bytes)
        for i, fn in enumerate(files, 1):
            with open(os.path.join(SRC, fn), "rb") as f:
                while True:
                    chunk = f.read(1 << 20)
                    if not chunk:
                        break
                    out.write(chunk)
            total += index[fn[:-4]][1]
            if i % 500 == 0 or i == len(files):
                print(f"  {i}/{len(files)}  {total/1024/1024/1024:.2f} GB", flush=True)

    print(f"完成：{len(index)} 张，"
          f"pack {os.path.getsize(PACK)/1024/1024/1024:.2f} GB，"
          f"索引头 {12 + len(idx_bytes)} 字节")

    # 自检：按索引读回一张，确认是 PNG
    import random
    base = 12 + len(idx_bytes)
    code = random.choice(list(index))
    off, size = index[code]
    with open(PACK, "rb") as f:
        f.seek(base + off)
        head8 = f.read(8)
    ok = head8[:4] == b"\x89PNG"
    print(f"自检 {code}: 偏移 {off} 长度 {size} 头部 {head8[:4]!r} -> "
          f"{'PNG 正常 ✅' if ok else '异常 ❌'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
