#!/usr/bin/env python3
"""为两个 APK 生成「差分补丁」—— 让 App 更新时只下变化的那一小部分。

为什么要自己写：zstd 的 --patch-from 效果极好（0.85.3→0.85.4 只有 10.3 MB），
但 zstd-jni 在 Maven 上没有 Android 版，自己编原生库在这台机器上又没法验证。
而这个项目的 APK 有个特点可以白拿：**它就是 ZIP，99% 的字节是内容完全相同的条目**
（那 493 MB 卡图从不变化）。所以差分只要说清两件事：
「这段从旧包第 N 字节复制」和「这段是新内容」。

补丁格式（`.lycpatch`）：
    [0..8]    magic  b"LYCDELTA1"
    [9..12]   旧包大小   uint32 小端
    [13..16]  新包大小   uint32 小端
    [17..48]  新包 SHA256（32 字节）—— App 应用完先核对，对不上就退回整包下载
    [49..]    指令流（gzip 压缩）

指令流（先解压再逐条执行）：
    varint 指令：0 = 结束，1 = 从旧包复制，2 = 新内容
    1 后面跟 varint 旧包偏移 + varint 长度
    2 后面跟 varint 长度 + 这么多字节

用法：
    python tools/make_delta.py 旧.apk 新.apk -o 补丁.lycpatch
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import struct
import sys
import zipfile
from dataclasses import dataclass

MAGIC = b"LYCDELTA1"
HEADER = len(MAGIC) + 4 + 4 + 32

# 指令
OP_END = 0
OP_COPY = 1
OP_LITERAL = 2

# 单条 COPY 最多复制多少（防止一条指令覆盖几百 MB，App 端不好报进度）
MAX_COPY = 8 << 20


@dataclass
class Entry:
    name: str
    data_off: int      # 压缩数据在文件里的起点
    comp_size: int
    file_size: int
    crc: int


def read_entries(path: str) -> dict[str, Entry]:
    """读出 ZIP 里每个条目的「数据区」位置和指纹。

    用 zipfile 拿到的 header_offset 是**本地头**的起点，
    数据区还要跳过本地头本身（长度不定，因为有可变长的文件名/扩展字段）。
    """
    out: dict[str, Entry] = {}
    with zipfile.ZipFile(path) as z:
        for info in z.infolist():
            with open(path, "rb") as f:
                f.seek(info.header_offset)
                raw = f.read(30)
                if raw[:4] != b"PK\x03\x04":
                    continue
                name_len, extra_len = struct.unpack("<HH", raw[26:30])
                data_off = info.header_offset + 30 + name_len + extra_len
            out[info.filename] = Entry(
                name=info.filename,
                data_off=data_off,
                comp_size=info.compress_size,
                file_size=info.file_size,
                crc=info.CRC,
            )
    return out


def block_hash(path: str, off: int, size: int, chunk: int = 1 << 20) -> bytes:
    """对文件的一段区间算哈希（分块读，别一次吃进内存）。"""
    h = hashlib.blake2b(digest_size=16)
    with open(path, "rb") as f:
        f.seek(off)
        left = size
        while left > 0:
            b = f.read(min(chunk, left))
            if not b:
                break
            h.update(b)
            left -= len(b)
    return h.digest()


def varint(n: int) -> bytes:
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def build_matches(old: str, new: str) -> tuple[list[tuple[int, int, int]], int]:
    """找出「新包的哪一段能从旧包哪里复制」。

    返回 [(新包偏移, 长度, 旧包偏移)]（按新包偏移升序）和可复制的总字节数。
    """
    oe = read_entries(old)
    ne = read_entries(new)
    matches: list[tuple[int, int, int]] = []
    saved = 0
    for name, e in ne.items():
        o = oe.get(name)
        if o is None or o.comp_size != e.comp_size or o.crc != e.crc:
            continue
        # crc 和大小都一样，再核一遍哈希，确保不是巧合
        if block_hash(old, o.data_off, o.comp_size) != block_hash(new, e.data_off, e.comp_size):
            continue
        off = e.data_off
        left = e.comp_size
        while left > 0:
            n = min(left, MAX_COPY)
            matches.append((off, n, o.data_off + (e.comp_size - left)))
            off += n
            left -= n
        saved += e.comp_size
    matches.sort(key=lambda m: m[0])
    return matches, saved


def build_patch(old: str, new: str, out: str) -> dict:
    import os

    new_size = os.path.getsize(new)
    old_size = os.path.getsize(old)
    matches, saved = build_matches(old, new)

    h = hashlib.sha256()
    with open(new, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    new_sha = h.digest()

    # 逐段生成指令流：匹配区间之间剩下的都是新内容
    raw = io.BytesIO()
    literal_bytes = 0
    with open(new, "rb") as f:
        pos = 0
        for (off, length, old_off) in matches:
            if off > pos:
                f.seek(pos)
                chunk = f.read(off - pos)
                raw.write(varint(OP_LITERAL))
                raw.write(varint(len(chunk)))
                raw.write(chunk)
                literal_bytes += len(chunk)
            raw.write(varint(OP_COPY))
            raw.write(varint(old_off))
            raw.write(varint(length))
            pos = off + length
        if pos < new_size:
            f.seek(pos)
            chunk = f.read(new_size - pos)
            raw.write(varint(OP_LITERAL))
            raw.write(varint(len(chunk)))
            raw.write(chunk)
            literal_bytes += len(chunk)
    raw.write(varint(OP_END))
    plain = raw.getvalue()

    with open(out, "wb") as f:
        f.write(MAGIC)
        f.write(struct.pack("<II", old_size, new_size))
        f.write(new_sha)
        f.write(gzip.compress(plain, compresslevel=9, mtime=0))

    import os as _os
    return {
        "old_size": old_size,
        "new_size": new_size,
        "patch_size": _os.path.getsize(out),
        "plain_size": len(plain),
        "literal_bytes": literal_bytes,
        "copy_bytes": saved,
        "matches": len(matches),
        "new_sha": h.hexdigest(),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description="生成 lycard 差分更新补丁")
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("-o", "--out", required=True)
    a = ap.parse_args()

    r = build_patch(a.old, a.new, a.out)
    mb = 1 << 20
    print(f"旧包 {r['old_size']:,} 字节 / 新包 {r['new_size']:,} 字节")
    print(f"可复制 {r['copy_bytes']/mb:.1f} MB（{r['matches']} 段）"
          f" / 新内容 {r['literal_bytes']/mb:.1f} MB")
    print(f"指令流未压缩 {r['plain_size']/mb:.1f} MB")
    print(f"→ 补丁 {r['patch_size']:,} 字节 = {r['patch_size']/mb:.1f} MB"
          f"（是新包的 {r['patch_size']/r['new_size']*100:.2f}%）")
    print(f"新包 SHA256 = {r['new_sha']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
