#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把新卡的原图 PNG **追加**进已有数据包，不动老数据。

为什么不能直接 `build_pack.py` 重打
------------------------------------
`build_pack.py` 从 `assets/cards/` 打包，而那个目录现在是**给 APK 用的 WebP**
（平均 50KB）。拿它重打会把包里 9952 张**PNG 原图**（平均 363KB）整体降质成 WebP。
小林的画质口径是「原图」，所以必须**保留旧包的字节、只追加新卡**。

做法
----
数据包格式（`LYCPACK1`）：
    [0..7]   magic
    [8..11]  索引长度 N（uint32 LE）
    [12..12+N)  索引 JSON：{"卡号": [相对图片区偏移, 长度]}
    [12+N..]    所有图片字节首尾拼接

偏移是**相对图片区开头**的，所以只要把旧图片区**原样搬运**，旧偏移就一直有效；
新图的偏移 = 旧图片区长度 + 累计。索引变长不影响偏移。

用法
----
    python tools/extend_pack.py --old dist/lycee_cards.pack \\
        --dir work/img_png_new --out dist/lycee_cards.pack.new

    # 旧包是分卷的（part01/part02）时会自动先拼一个临时整包
    python tools/extend_pack.py --old dist/lycee_cards.pack --dir work/img_png_new

    # 打完顺手切回 1900 MiB 一卷（和原来的切法一致）
    python tools/extend_pack.py ... --split-mib 1900
"""
import argparse
import json
import os
import shutil
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAGIC = b"LYCPACK1"


def join_parts(path):
    """旧包如果只有 .part01/.part02，先拼成一个临时整包，返回其路径。"""
    if os.path.exists(path):
        return path, None
    parts = []
    i = 1
    while True:
        p = f"{path}.part{i:02d}"
        if not os.path.exists(p):
            break
        parts.append(p)
        i += 1
    if not parts:
        raise SystemExit(f"找不到 {path}，也没有 {path}.part01 …")
    tmp = path + ".joined"
    print(f"拼接 {len(parts)} 个分卷 → {tmp}")
    with open(tmp, "wb") as out:
        for p in parts:
            print(f"  + {os.path.basename(p)} ({os.path.getsize(p)/1048576:.0f} MB)")
            with open(p, "rb") as f:
                shutil.copyfileobj(f, out, 16 << 20)
    return tmp, tmp


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", required=True)
    ap.add_argument("--dir", required=True, help="新卡 PNG 所在目录")
    ap.add_argument("--out", default=None)
    ap.add_argument("--split-mib", type=int, default=0,
                    help=">0 时按这个大小切卷（原包是 1900 MiB 一卷）")
    a = ap.parse_args()

    old, tmp_join = join_parts(a.old)
    out = a.out or (old.replace(".joined", "") + ".new")

    with open(old, "rb") as f:
        magic = f.read(8)
        if magic != MAGIC:
            raise SystemExit(f"magic 不对：{magic!r}")
        n = struct.unpack("<I", f.read(4))[0]
        idx = json.loads(f.read(n).decode("utf-8"))
        head_len = 12 + n
        old_images = os.path.getsize(old) - head_len
        print(f"旧包：{len(idx)} 张，图片区 {old_images/1048576:.0f} MB")

    # 收集新图（跳过包里已有的）
    new_files = []
    for fn in sorted(os.listdir(a.dir)):
        if not fn.lower().endswith(".png"):
            continue
        code = fn[:-4]
        p = os.path.join(a.dir, fn)
        if os.path.getsize(p) < 1000:
            continue
        if code in idx:
            print(f"  跳过已在包里的：{code}")
            continue
        new_files.append((code, p))
    print(f"新增 {len(new_files)} 张")
    if not new_files:
        print("没有要加的，退出")
        return 0

    # 先算好新索引（新图偏移 = 旧图片区长度 + 累计）
    new_idx = dict(idx)
    off = old_images
    for code, p in new_files:
        size = os.path.getsize(p)
        new_idx[code] = [off, size]
        off += size

    payload = json.dumps(new_idx, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    print(f"新索引：{len(new_idx)} 张，{len(payload)/1048576:.1f} MB")

    with open(out, "wb") as w:
        w.write(MAGIC)
        w.write(struct.pack("<I", len(payload)))
        w.write(payload)
        # 旧图片区原样搬运（偏移不变）
        with open(old, "rb") as f:
            f.seek(head_len)
            left = old_images
            while left:
                chunk = f.read(min(16 << 20, left))
                if not chunk:
                    raise SystemExit("旧包读到一半断了")
                w.write(chunk)
                left -= len(chunk)
        # 追加新图
        for i, (code, p) in enumerate(new_files, 1):
            with open(p, "rb") as f:
                shutil.copyfileobj(f, w, 4 << 20)
            if i % 50 == 0 or i == len(new_files):
                print(f"  追加 {i}/{len(new_files)}", flush=True)

    size = os.path.getsize(out)
    print(f"\n输出 {out}：{size/1073741824:.2f} GB（{len(new_idx)} 张）")

    if tmp_join:
        os.remove(tmp_join)
        print(f"已删临时拼接包 {tmp_join}")

    # 自检：抽 3 张旧卡 + 3 张新卡，验魔数与长度
    import random
    picks = list(idx)[:3] + [c for c, _ in new_files][:3]
    with open(out, "rb") as f:
        f.seek(8)
        nn = struct.unpack("<I", f.read(4))[0]
        json.loads(f.read(nn).decode("utf-8"))
        base = 12 + nn
        ok = 0
        for code in picks:
            o, ln = new_idx[code]
            f.seek(base + o)
            d = f.read(12)
            fmt = ("PNG" if d[:8] == b"\x89PNG\r\n\x1a\n"
                   else "WebP" if d[:4] == b"RIFF" and d[8:12] == b"WEBP" else "未知")
            print(f"  {code:14s} {ln:>8,} 字节 {fmt}")
            if fmt == "PNG":
                ok += 1
    if ok < len(picks):
        print("⚠️ 有样本不是 PNG，检查一下")

    if a.split_mib:
        base_name = out.replace(".new", "")
        print(f"\n切卷（每卷 {a.split_mib} MiB）…")
        with open(out, "rb") as f:
            i = 1
            while True:
                chunk = f.read(a.split_mib * 1024 * 1024)
                if not chunk:
                    break
                p = f"{base_name}.part{i:02d}"
                with open(p, "wb") as w:
                    w.write(chunk)
                print(f"  {p}  {len(chunk)/1048576:.0f} MB")
                i += 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
