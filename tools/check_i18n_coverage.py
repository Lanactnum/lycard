#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检查界面文案的多语言覆盖率（要求 L103 的体检脚本）。

回答两个问题：
  1. 有多少文案已经被 tr() 包住（会跟着界面语言变）
  2. 还有哪些含中文的字符串没被包住（切成外语时它们会保持中文）

用法：
    python tools/check_i18n_coverage.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
SEP = chr(92)      # 反斜杠，避开多层转义
NL = chr(10)

STR_RE = re.compile(
    r"""(?<![\w$])(['"])((?:(?!\1).)*?[\u4e00-\u9fff](?:(?!\1).)*?)\1""")

# 这些文件里没有界面文案（纯算法/数据）
SKIP_FILES = {
    "lib/data/search_index.dart",   # 假名罗马字映射表（数据）
    "lib/data/banlist.dart",        # 没有界面文案
    "lib/pages/banlist_page.dart",  # 手工加过 tr（含官方页面锚点，不能自动扫）
}
SKIP_DIRS = {os.path.join("lib", "l10n")}


def main():
    wrapped = 0
    miss = []

    for base, _dirs, names in os.walk(LIB):
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            full = os.path.join(base, n)
            rel = os.path.relpath(full, ROOT).replace(SEP, "/")
            if "lib" + SEP + "l10n" in full:
                continue
            if rel in SKIP_FILES:
                continue
            src = open(full, encoding="utf-8").read()
            for ln, line in enumerate(src.split(NL), 1):
                st = line.strip()
                if st.startswith("//") or "debugPrint" in line:
                    continue
                if "RegExp(" in line or "replaceAll(" in line:
                    continue
                for m in STR_RE.finditer(line):
                    text = m.group(2)
                    if len(text.strip()) < 2:
                        continue
                    head = line[:m.start()].rstrip()
                    if head.endswith("tr(") or head.endswith("L10n.tr("):
                        wrapped += 1
                        continue
                    miss.append((rel, ln, text))

    uniq = {}
    for rel, ln, text in miss:
        uniq.setdefault(text, []).append(f"{rel}:{ln}")

    print(f"已用 tr() 包住的文案引用 : {wrapped} 处")
    print(f"仍是纯中文（切外语不变）: {len(uniq)} 种，共 {len(miss)} 处")
    if uniq:
        print()
        print("--- 明细（最多列 40 条）---")
        for text, where in list(uniq.items())[:40]:
            print(f"  {text[:66]!r}")
            print(f"      {where[0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
