#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清掉因 t()/tr() 改写而失效的 const（要求 L103 的收尾步骤）。

`const Text('检索')` 改成 `Text(tr('检索'))` 之后就不再是编译期常量了，
Dart 会报 const_eval_method_invocation / invalid_constant。
这个脚本按 analyze 报的位置，往前找最近的 const 并删掉。

用法：
    python tools/fix_const.py            # 只看
    python tools/fix_const.py --write
"""
import argparse
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 这些错误码都意味着"这里不该有 const"
CODES = (
    "const_eval_method_invocation",
    "invalid_constant",
    "const_eval_property_access",
    "non_constant_list_element",
    "non_constant_map_value",
    "const_constructor_param_type_mismatch",
    "const_with_non_constant_argument",
    "const_eval_type_bool_num_string",
)

LINE_RE = re.compile(r"^(error|warning|info) - .* - (\S+\.dart):(\d+):(\d+) - (\w+)$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    r = subprocess.run(["flutter", "analyze"], cwd=ROOT,
                       capture_output=True, text=True, shell=True)
    out = r.stdout + r.stderr

    targets = {}
    for line in out.split("\n"):
        m = LINE_RE.match(line.strip())
        if not m:
            continue
        _sev, path, ln, _col, code = m.groups()
        if code not in CODES:
            continue
        p = os.path.join(ROOT, path.replace("/", os.sep))
        targets.setdefault(p, []).append(int(ln))

    if not targets:
        print("没有需要清 const 的地方 ✅")
        return 0

    total = sum(len(v) for v in targets.values())
    print(f"需要清 const 的位置：{total} 处，涉及 {len(targets)} 个文件")

    changed = 0
    for path, lines in targets.items():
        src = open(path, encoding="utf-8").read()
        src_lines = src.split("\n")
        # 从后往前，避免行号漂移
        for ln in sorted(set(lines), reverse=True):
            idx = ln - 1
            if idx >= len(src_lines):
                continue
            # 往前最多找 6 行，找最近的 "const "
            for k in range(idx, max(-1, idx - 6), -1):
                pos = src_lines[k].find("const ")
                if pos >= 0:
                    # 只删这一处
                    before = src_lines[k][:pos]
                    after = src_lines[k][pos + len("const "):]
                    src_lines[k] = before + after
                    changed += 1
                    break
        open(path, "w", encoding="utf-8").write("\n".join(src_lines))

    print(f"删掉了 {changed} 处 const")
    if not args.write:
        print("（这是预览，加 --write 才真改）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
