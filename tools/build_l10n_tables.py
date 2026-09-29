#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把翻译结果合并成 Dart 表文件（要求 L103）。

输入：work/i18n/out_<lang>_*.json
输出：lib/l10n/table_zh_hant.dart / table_en.dart / table_ja.dart /
      table_ru.dart / table_ko.dart

表是 `const Map<String, String>`，key 是中文原文模板，
value 是译文 —— 由 lib/l10n/l10n.dart 的 tr() 查。
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDIR = os.path.join(ROOT, "work", "i18n")
LDIR = os.path.join(ROOT, "lib", "l10n")

LANGS = {
    "zhHant": ("kZhHant", "table_zh_hant.dart"),
    "en": ("kEn", "table_en.dart"),
    "ja": ("kJa", "table_ja.dart"),
    "ru": ("kRu", "table_ru.dart"),
    "ko": ("kKo", "table_ko.dart"),
}


def dart_str(s):
    """转成 Dart 单引号字符串字面量（转义 \\ ' $）"""
    s = s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    s = s.replace("\n", "\\n").replace("\r", "")
    return "'" + s + "'"


def main():
    templates = json.load(open(os.path.join(IDIR, "templates.json"),
                               encoding="utf-8"))
    keys = [t["key"] for t in templates]

    os.makedirs(LDIR, exist_ok=True)
    total_report = []
    for lang, (var, fname) in LANGS.items():
        files = sorted(glob.glob(os.path.join(IDIR, f"out_{lang}_*.json")))
        if not files:
            print(f"  {lang}: 还没有翻译结果，跳过")
            continue
        m = {}
        for f in files:
            for it in json.load(open(f, encoding="utf-8")):
                k, v = it.get("k", ""), (it.get("v") or "").strip()
                if k and v:
                    m[k] = v

        missing = [k for k in keys if k not in m]
        lines = [
            "// 由 tools/build_l10n_tables.py 生成 —— 不要手改。",
            "// 改文案请改 work/i18n 里的翻译结果再重新生成。",
            "",
            f"const Map<String, String> {var} = {{",
        ]
        for k in keys:
            if k in m:
                lines.append(f"  {dart_str(k)}: {dart_str(m[k])},")
        lines.append("};")
        lines.append("")
        open(os.path.join(LDIR, fname), "w", encoding="utf-8").write(
            "\n".join(lines))
        total_report.append((lang, len(m), len(missing)))
        print(f"  {lang}: {len(m)}/{len(keys)} 条 -> lib/l10n/{fname}")

    if not total_report:
        print("没有任何翻译结果可合并。")
        return 1
    print("\n语言    已翻/总数   缺")
    for lang, n, miss in total_report:
        print(f"  {lang:<7} {n}/{len(keys)}   {miss}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
