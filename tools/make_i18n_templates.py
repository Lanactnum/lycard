#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把界面文案转成「模板」形式，作为多语言（L103）的翻译源。

中文原文里混着 Dart 插值，例如：

    胜负记录 · ${deck.wins} 胜 ${deck.losses} 负

翻译时必须让各语言共用同一个 key，所以先把插值抽成占位符：

    key  = "胜负记录 · {0} 胜 {1} 负"
    args = ["deck.wins", "deck.losses"]

输出 work/i18n/templates.json：
    [{"key": ..., "args": [...], "orig": ..., "file": ..., "line": ...}, ...]

含嵌套引号（如 ${a ? 'x' : 'y'}）的条目无法安全自动化，单独列进
work/i18n/manual.json，交人工处理。
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "work", "i18n_source.json")
OUT = os.path.join(ROOT, "work", "i18n")


def split_template(text):
    """把 Dart 插值抽成 {N}，返回 (模板, 参数表达式列表, 是否安全)

    Dart 有两种写法都要认：
        ${deck.wins}     完整形式
        $official        简写形式（只跟一个标识符）
    """
    args = []
    out = []
    i = 0
    n = len(text)
    while i < n:
        ch = text[i]
        # 转义的 \$ 是字面美元符号，不算插值
        if ch == "\\" and i + 1 < n:
            out.append(text[i:i + 2])
            i += 2
            continue
        if ch != "$":
            out.append(ch)
            i += 1
            continue

        # ---- ${ ... } ----
        if i + 1 < n and text[i + 1] == "{":
            k = i + 2
            depth = 1
            while k < n and depth:
                if text[k] == "{":
                    depth += 1
                elif text[k] == "}":
                    depth -= 1
                k += 1
            if depth != 0:
                return None, None, False
            expr = text[i + 2:k - 1]
            if "'" in expr or '"' in expr:
                return None, None, False
            args.append(expr)
            out.append("{%d}" % (len(args) - 1))
            i = k
            continue

        # ---- $identifier ----
        m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)", text[i:])
        if m:
            args.append(m.group(1))
            out.append("{%d}" % (len(args) - 1))
            i += m.end()
            continue

        out.append(ch)
        i += 1

    return "".join(out), args, True


def main():
    data = json.load(open(SRC, encoding="utf-8"))
    items = data["items"]

    # 按文案去重：同一条文案只翻一次，但记住它出现在哪些文件
    seen = {}
    manual = {}
    for it in items:
        text = it["old"]
        tpl, args, ok = split_template(text)
        if not ok:
            manual.setdefault(text, []).append(f"{it['file']}:{it['line']}")
            continue
        key = tpl
        if key in seen:
            seen[key]["where"].append(f"{it['file']}:{it['line']}")
            continue
        seen[key] = {
            "key": key,
            "args": args,
            "orig": text,
            "where": [f"{it['file']}:{it['line']}"],
        }

    os.makedirs(OUT, exist_ok=True)
    out = sorted(seen.values(), key=lambda x: x["key"])
    json.dump(out, open(os.path.join(OUT, "templates.json"), "w",
                        encoding="utf-8"), ensure_ascii=False, indent=1)
    json.dump([{"text": k, "where": v} for k, v in manual.items()],
              open(os.path.join(OUT, "manual.json"), "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    n_arg = len([x for x in out if x["args"]])
    print(f"可自动化: {len(out)} 条（其中含占位符 {n_arg} 条）")
    print(f"需人工  : {len(manual)} 条（含嵌套引号，另见 manual.json）")
    print(f"写到: {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
