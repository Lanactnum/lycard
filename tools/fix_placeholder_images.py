#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修掉官方站的「占位图」。

现象：`-X` 这类变体卡号，官网的 card/image/{code}.png 返回的是一张
1KB 的通用问号占位图（不是真卡图）。

处理：这些变体本来就是同一张卡的不同版本，所以直接用**本体卡号的卡图**
顶上；本体也没有的话就留空，让 App 显示自己的占位样式。
"""
from __future__ import annotations

import collections
import hashlib
import json
import os
import shutil
import sys

SRC = os.path.join("assets", "cards")
SMALL = 5 * 1024  # 小于 5KB 的肯定不是卡图


def main():
    files = sorted(f for f in os.listdir(SRC) if f.lower().endswith(".png"))

    # ① 体积极小的（1KB 灰色问号图）
    small = [fn[:-4] for fn in files
             if os.path.getsize(os.path.join(SRC, fn)) < SMALL]

    # ② 内容完全一样、而且被 3 个以上卡号共用的（51KB 红色问号图）
    #    真卡图最多被「本体 + 一个变体」两张共用，不会被 3 个卡号共用。
    h2c = collections.defaultdict(list)
    for fn in files:
        h = hashlib.md5(open(os.path.join(SRC, fn), "rb").read()).hexdigest()
        h2c[h].append(fn[:-4])
    shared = []
    for h, codes in h2c.items():
        if len(codes) >= 3:
            shared.extend(codes)
    print(f"  · 极小图 {len(small)} 张")
    print(f"  · 多卡共用图 {len(shared)} 张")

    small = sorted(set(small) | set(shared))
    print(f"总卡图 {len(files)} 张，其中疑似占位图 {len(small)} 张")
    if small:
        print("  卡号后缀分布:",
              dict(collections.Counter(c.split("-")[-1] for c in small)))

    fixed = 0
    no_base = []
    for code in small:
        # 本体卡号：去掉最后的 -X / -A 之类变体后缀
        i = code.rindex("-")
        base = code[:i]
        base_png = os.path.join(SRC, f"{base}.png")
        if os.path.exists(base_png) and os.path.getsize(base_png) >= SMALL:
            shutil.copyfile(base_png, os.path.join(SRC, f"{code}.png"))
            fixed += 1
        else:
            no_base.append(code)

    print(f"用本体卡图补上: {fixed} 张")
    print(f"本体也没有、保持占位: {len(no_base)} 张")
    if no_base:
        print("  样例:", no_base[:8])
        json.dump(sorted(no_base),
                  open(os.path.join("work", "noart_codes.json"), "w"),
                  ensure_ascii=False)
        print("  名单已存 work/noart_codes.json")

    # 再验一遍还剩多少小图
    left = [f for f in os.listdir(SRC)
            if f.endswith(".png") and os.path.getsize(os.path.join(SRC, f)) < SMALL]
    print(f"处理后仍小于 5KB 的: {len(left)} 张")
    return 0


if __name__ == "__main__":
    sys.exit(main())
