#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把界面文案模板翻译成多语言（要求 L103）。

只翻 App 本体 —— 卡名/效果文本属于卡数据，不在这个流程里。

输入：work/i18n/templates.json   （tools/make_i18n_templates.py 产出）
输出：work/i18n/out_<lang>_<batch>.json

用法：
    export TR_BASE=https://www.micuapi.ai/v1
    export TR_MODEL=gpt-5.6-sol
    export TR_KEY=...
    python tools/translate_ui.py --all --workers 3
    python tools/translate_ui.py --lang en          # 只翻某一种
"""
import argparse
import glob
import hashlib
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IDIR = os.path.join(ROOT, "work", "i18n")

BASE = os.environ.get("TR_BASE", "https://www.micuapi.ai/v1")
KEY = os.environ.get("TR_KEY", "")
MODEL = os.environ.get("TR_MODEL", "gpt-5.6-sol")

# 语言代码 → 给模型的说法
LANGS = {
    "zhHant": "繁体中文（台湾用语习惯，例如「設定」「檔案」「搜尋」）",
    "en": "English",
    "ja": "日本語（自然なアプリUI用語で）",
    "ru": "Русский язык",
    "ko": "한국어",
}

BATCH = 40

SYSTEM = """你是手机 App 的界面本地化译者。

把用户给的中文界面文案翻译成指定语言。要求：
1. **原样保留 {0} {1} 这类占位符** —— 它们是程序替换进去的变量，
   一个字符都不能改、不能翻译、不能调整顺序。
2. 界面用语要短：按钮、标签、开关尽量用行业惯用的短词，
   不要写成句子。
3. 保持原文的语气（这是卡牌游戏工具，偏工具/收藏向，不用太口语）。
4. 不要翻译成解释性文字，只给对应语言的等价界面文案。

只输出 JSON，不要 Markdown 代码块，不要任何解释。
输出格式：{"items":[{"k":"原文模板","v":"译文"}]}
"""


def call_api(items, lang_desc, tries=3):
    user = (f"目标语言：{lang_desc}\n\n"
            f"待翻译（JSON）：\n{json.dumps(items, ensure_ascii=False)}\n\n"
            "请返回翻译后的 JSON。")
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user},
        ],
        "temperature": 0.2,
    }).encode("utf-8")

    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(
                f"{BASE}/chat/completions",
                data=body,
                headers={
                    "Content-Type": "application/json",
                    # 必须带浏览器 UA：默认的 Python-urllib 会被中转站的
                    # WAF 直接 403（实测踩过）
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                                  "AppleWebKit/537.36 Chrome/131.0 Safari/537.36",
                    "Authorization": f"Bearer {KEY}",
                },
            )
            with urllib.request.urlopen(req, timeout=180) as r:
                j = json.loads(r.read().decode("utf-8"))
            text = j["choices"][0]["message"]["content"].strip()
            if text.startswith("```"):
                text = text.split("```")[1]
                if text.startswith("json"):
                    text = text[4:]
            got = json.loads(text)
            return got["items"] if isinstance(got, dict) else got
        except Exception as e:      # noqa: BLE001
            last = e
    raise RuntimeError(f"翻译失败：{last}")


# ⚠ 输出文件名必须带**内容指纹**：光用批次号的话，templates 变了
# 但批次号一样，会被"文件已存在就跳过"直接略过 —— 实测踩过：
# 跑了 1000 条却一条都没写进去。
TAG = ""


def do_batch(idx, batch, lang, lang_desc):
    outp = os.path.join(IDIR, f"out_{lang}_{TAG}_{idx:03d}.json")
    if os.path.exists(outp):
        return idx, lang, len(json.load(open(outp, encoding="utf-8")))
    payload = [{"k": b["key"], "v": ""} for b in batch]
    got = call_api(payload, lang_desc)
    m = {g.get("k", ""): g.get("v", "") for g in got}
    out = [{"k": b["key"], "v": m.get(b["key"], "")} for b in batch]
    json.dump(out, open(outp, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    return idx, lang, len(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lang", default=None)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()

    if not KEY:
        print("缺少 TR_KEY")
        return 1

    templates = json.load(open(os.path.join(IDIR, "templates.json"),
                               encoding="utf-8"))
    # 用 templates 内容算指纹，写进文件名
    global TAG
    TAG = hashlib.md5(json.dumps(
        [t["key"] for t in templates], ensure_ascii=False
    ).encode("utf-8")).hexdigest()[:8]
    langs = list(LANGS) if (args.all or not args.lang) else [args.lang]
    print(f"templates 指纹: {TAG}")

    # 已经翻好的 key 跳过 —— 重跑时只补新加的，不浪费额度
    def already_done(lang):
        done = {}
        for f in sorted(glob.glob(os.path.join(IDIR, f"out_{lang}_*.json"))):
            for it in json.load(open(f, encoding="utf-8")):
                k, v = it.get("k", ""), (it.get("v") or "").strip()
                if k and v:
                    done[k] = v
        return done

    pending = {}
    for lang in langs:
        done = already_done(lang)
        todo = [t for t in templates if t["key"] not in done]
        if todo:
            pending[lang] = todo
        print(f"  {lang}: 已有 {len(done)} 条，待翻 {len(todo)} 条")

    jobs = []
    for lang, todo in pending.items():
        if lang not in LANGS:
            print(f"未知语言：{lang}")
            return 1
        bs = [todo[i:i + BATCH] for i in range(0, len(todo), BATCH)]
        for i, b in enumerate(bs):
            # 文件名带上批次内容的特征，避免和之前那批撞名
            jobs.append((900 + i, b, lang, LANGS[lang]))

    print(f"模型 {MODEL} @ {BASE}")
    if not jobs:
        print("没有待翻的条目，全部已完成 ✅")
        return 0
    print(f"待翻 {sum(len(v) for v in pending.values())} 条 → {len(jobs)} 个批次任务")
    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = [ex.submit(do_batch, *j) for j in jobs]
        for f in as_completed(futs):
            try:
                idx, lang, n = f.result()
                done += n
                print(f"  {lang} 批{idx}: {n} 条（累计 {done}）")
            except Exception as e:   # noqa: BLE001
                print(f"  !! 失败：{e}")
    print("跑完，用 tools/build_l10n_tables.py 合并成 Dart 表")
    return 0


if __name__ == "__main__":
    sys.exit(main())
