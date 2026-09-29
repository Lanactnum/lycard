#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""找出「在列表项组件里 watch AppState」的地方 —— 那是 N 倍重建开销。

列表项（GridView/ListView 的 itemBuilder 里返回的那个 widget）如果
自己 watch 整个 AppState，屏幕上 N 个可见项就会在每次状态变化时全部
重建。要查的是：某个类里既有 context.watch<AppState>()，这个类又被
itemBuilder 实例化。

用法：python tools/check_perf_watch.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
NL = chr(10)


def main():
    # 1. 找出每个类里有没有 watch
    watch_classes = {}      # 类名 -> (文件, 行号)
    for base, _d, names in os.walk(LIB):
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            full = os.path.join(base, n)
            rel = os.path.relpath(full, ROOT).replace(chr(92), "/")
            lines = open(full, encoding="utf-8").read().split(NL)
            cur = None
            for i, l in enumerate(lines, 1):
                m = re.match(r"class\s+(\w+)", l)
                if m:
                    cur = m.group(1)
                if "context.watch<AppState>()" in l and cur:
                    watch_classes.setdefault(cur, (rel, i))

    # 2. 找出 itemBuilder / children 里实例化的类
    hot = []
    for base, _d, names in os.walk(LIB):
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            full = os.path.join(base, n)
            rel = os.path.relpath(full, ROOT).replace(chr(92), "/")
            src = open(full, encoding="utf-8").read()
            for m in re.finditer(r"itemBuilder", src):
                seg = src[m.start():m.start() + 2000]
                for cls, (wf, wl) in watch_classes.items():
                    # 这个类在 itemBuilder 段里被构造
                    if re.search(r"\b" + cls + r"\(", seg):
                        hot.append((cls, rel, wf, wl))

    print(f"含 context.watch<AppState>() 的类: {len(watch_classes)} 个")
    if hot:
        print()
        print("!! 这些类**在列表项里被实例化**，等于 N 倍重建：")
        seen = set()
        for cls, where, wf, wl in hot:
            if cls in seen:
                continue
            seen.add(cls)
            print(f"   {cls}  (定义 {wf}:{wl}，用于 {where} 的 itemBuilder)")
    else:
        print("列表项里没有 watch AppState 的组件 ✅")

    print()
    print("--- 全部 watch 点 ---")
    for cls, (f, l) in sorted(watch_classes.items(), key=lambda x: x[1][0]):
        print(f"   {f}:{l}  {cls}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
