#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 Release 里分卷的卡图数据包合并回一个 lycee_cards.pack。

为什么会有分卷：GitHub 单个 Release 附件上限 2 GB，而原图数据包有 3.65 GB，
所以拆成了 lycee_cards.pack.part01 / .part02 两卷。本脚本按文件名顺序读完
再拼回去，然后比对 SHA256 —— 一定要比对：传输断在中间是真实存在的，
而症状是「有些卡图空白」，很容易被当成 App 的 bug。

用法：
    python tools/join_cards_pack.py <分卷所在目录> [-o 输出路径]

例：
    python tools/join_cards_pack.py %USERPROFILE%\\Downloads
    python tools/join_cards_pack.py . -o lycee_cards.pack
"""

import argparse
import glob
import hashlib
import os
import sys

# 完整数据包的 SHA256（Release 页面上也写了同一个值）
EXPECT_SHA256 = "49b26768074e345710ec7d6d9599a6bf3c9aaf2111114017d7b05c599170f5a9"
EXPECT_SIZE = 3919354515  # 3,919,354,515 字节

PART_GLOB = "lycee_cards.pack.part*"


def sha256_of(path: str, chunk: int = 8 << 20) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser(description="合并卡图数据包分卷")
    ap.add_argument("parts_dir", help="分卷所在目录")
    ap.add_argument("-o", "--out", default=None, help="输出路径（默认与分卷同目录）")
    args = ap.parse_args()

    parts = sorted(glob.glob(os.path.join(args.parts_dir, PART_GLOB)))
    if not parts:
        print(f"× 在 {args.parts_dir} 里没找到 {PART_GLOB}")
        print("  请把下载下来的 lycee_cards.pack.part01 / .part02 放在同一个目录里")
        return 1

    out = args.out or os.path.join(args.parts_dir, "lycee_cards.pack")
    print(f"→ 找到 {len(parts)} 卷，合并到 {out}")
    for p in parts:
        print(f"   · {os.path.basename(p)}  {os.path.getsize(p):,} 字节")

    with open(out, "wb") as w:
        for p in parts:
            with open(p, "rb") as r:
                while True:
                    b = r.read(8 << 20)
                    if not b:
                        break
                    w.write(b)

    size = os.path.getsize(out)
    print(f"→ 合并完成：{size:,} 字节")
    if size != EXPECT_SIZE:
        print(f"× 大小不对！应当是 {EXPECT_SIZE:,} 字节")
        print("  多半是某一卷没下完，重新下载后再试")
        return 2

    print("→ 正在校验 SHA256（3.65 GB，要一会儿）…")
    got = sha256_of(out)
    print(f"   {got}")
    if EXPECT_SHA256 != "PLACEHOLDER_SHA256":
        if got.lower() != EXPECT_SHA256.lower():
            print(f"× 校验失败！应当是 {EXPECT_SHA256}")
            return 3
        print("√ SHA256 正确")

    print()
    print("接下来：")
    print("  ① 手机上：把 %s 丢进「下载」文件夹，" % os.path.basename(out))
    print("     然后 App 里 我的 → 数据与备份 → 从文件管理器选择数据包")
    print("  ② 或用电脑：adb push %s "
          "/sdcard/Android/data/com.lycard.app/files/" % os.path.basename(out))
    print("     （App 必须先启动过一次，否则那个目录还不存在）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
