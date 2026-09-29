#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""找出「代码里已经 tr(...) 包了、但翻译表里没有」的文案。

这类文案最隐蔽：代码看着是对的（有 tr），但切到外语时表里查不到，
tr() 原样返回中文 —— 用户看到的是"半截翻译"。

来源通常是：
  · 文件被加进了 apply_i18n 的黑名单（theme_page / banlist_page），
    但里面的文案是手工 tr 的，没进 templates.json；
  · 提取脚本某轮过滤条件变化，把这些 key 漏掉了。

用法：
    python tools/find_missing_tr.py            # 只看
    python tools/find_missing_tr.py --merge    # 并进 templates.json
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
TPL = os.path.join(ROOT, "work", "i18n", "templates.json")
SEP = chr(92)
NL = chr(10)

# tr('...') 或 tr("...")，只取单行（跨行的靠相邻拼接，这里够用）
TR_RE = re.compile(r"""\btr\(\s*(['"])((?:(?!\1).)+?)\1""")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--merge", action="store_true")
    args = ap.parse_args()

    tpl = json.load(open(TPL, encoding="utf-8"))
    have = {t["key"] for t in tpl}

    used = {}          # key -> [位置]
    for base, _d, names in os.walk(LIB):
        if os.path.join(LIB, "l10n") in base:
            continue
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            full = os.path.join(base, n)
            rel = os.path.relpath(full, ROOT).replace(SEP, "/")
            src = open(full, encoding="utf-8").read()
            for ln, line in enumerate(src.split(NL), 1):
                st = line.strip()
                if st.startswith("//"):
                    continue
                for m in TR_RE.finditer(line):
                    k = m.group(2)
                    used.setdefault(k, []).append(f"{rel}:{ln}")

    missing = {k: v for k, v in used.items() if k not in have}
    print(f"代码里 tr() 用到的文案 : {len(used)} 种")
    print(f"其中表里没有的（会漏翻）: {len(missing)} 种")
    if missing:
        print()
        for k, where in sorted(missing.items()):
            print(f"  {k[:66]!r}")
            print(f"      {where[0]}")

    if args.merge and missing:
        for k, where in sorted(missing.items()):
            n = len(re.findall(r"\{\d+\}", k))
            tpl.append({
                "key": k,
                "args": [""] * n,
                "orig": k,
                "where": where,
            })
        json.dump(tpl, open(TPL, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print(f"\n已并入 templates.json → 现在 {len(tpl)} 条")
        print("接着跑：python tools/translate_ui.py --all")
    return 0


if __name__ == "__main__":
    sys.exit(main())
