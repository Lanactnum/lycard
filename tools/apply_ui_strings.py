#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把编辑过的界面文案清单回写进 lib/。

    python tools/apply_ui_strings.py                      # 用默认路径
    python tools/apply_ui_strings.py --file 某个.json      # 指定清单
    python tools/apply_ui_strings.py --dry                # 只看会改什么

规则：
  · 以每条自己的 old 为定位依据（不看行号，所以代码动过位置也能对上）
  · 只在**那条记录所记的文件**里替换，不会误伤别处
  · 同一条 old 在同一文件里出现多次时，默认全改（--once 只改第一处）
  · 改完打印汇总；有 old 找不到的会单独列出来，方便排查
"""
import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_FILE = r"D:\Big Fat Fish\工作区\lycard界面文案.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", default=DEFAULT_FILE)
    ap.add_argument("--dry", action="store_true", help="只报告，不写入")
    ap.add_argument("--once", action="store_true", help="同一文件里只改第一处")
    args = ap.parse_args()

    if not os.path.exists(args.file):
        print(f"找不到清单文件：{args.file}")
        print("先跑 tools/extract_ui_strings.py 生成一份。")
        return 1

    data = json.load(open(args.file, encoding="utf-8"))
    items = data.get("items", [])

    changed = []          # (file, old, new)
    not_found = []        # (file, old)
    risky = []            # (file, old) —— 提取不完整的半截字符串
    cache = {}            # 文件内容缓存

    def looks_truncated(t: str) -> bool:
        """括号 / ${ 不配对 → 多半是抽取时被引号截断的半截字符串。
        这种如果照直替换，会把源码里的字符串拼坏（编译不过）。"""
        if t.count("(") != t.count(")"):
            return True
        if t.count("${") > t.count("}"):
            return True
        if t.count("{") != t.count("}"):
            return True
        return False

    for it in items:
        old = it.get("old", "")
        new = it.get("new", "")
        rel = it.get("file", "")
        if not old or not rel:
            continue
        if old == new:
            continue          # 没动过
        if looks_truncated(old):
            risky.append((rel, old))
            continue          # 交给人工/别的办法处理，绝不硬替

        path = os.path.join(ROOT, rel.replace("/", os.sep))
        if not os.path.exists(path):
            not_found.append((rel, old))
            continue

        if path not in cache:
            cache[path] = open(path, encoding="utf-8").read()
        src = cache[path]

        # 注意：源码里的字符串可能用单引号也可能用双引号，
        # 清单里存的是**引号内的内容**，所以两种都要试。
        hit = False
        for q in ("'", '"'):
            literal = f"{q}{old}{q}"
            if literal in src:
                if args.once:
                    src = src.replace(literal, f"{q}{new}{q}", 1)
                else:
                    src = src.replace(literal, f"{q}{new}{q}")
                hit = True
        if hit:
            cache[path] = src
            changed.append((rel, old, new))
        else:
            not_found.append((rel, old))

    print(f"要改 {len(changed)} 条，涉及文件 {len({c[0] for c in changed})} 个")
    if args.dry:
        print("\n--- 预览（前 40 条）---")
        for rel, old, new in changed[:40]:
            print(f"  {rel}\n      {old}\n   →  {new}")
        return 0

    for path, src in cache.items():
        open(path, "w", encoding="utf-8").write(src)

    print("已写入 ✅")
    if changed:
        print("\n--- 实际改动（前 30 条）---")
        for rel, old, new in changed[:30]:
            print(f"  {rel}\n      {old}\n   →  {new}")
    if not_found:
        print(f"\n!! 有 {len(not_found)} 条没能在源码里找到对应的字符串（可能代码已经改过）：")
        for rel, old in not_found[:15]:
            print(f"   {rel}  «{old[:50]}»")
    return 0


if __name__ == "__main__":
    sys.exit(main())
