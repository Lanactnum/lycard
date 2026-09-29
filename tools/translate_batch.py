#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""批量翻译卡名 + 效果文本（用任意 OpenAI 兼容接口，不吃 Hermes 的额度）。

设计：把「定标准」和「跑量」分开——
  * 术语与风格规范写在 tools/glossary.md（一次性，人工把关）
  * 批量翻译交给便宜的模型跑脚本（本文件）
  * Hermes 只负责抽检和修系统性问题

用法：
    export TR_BASE=https://openrouter.ai/api/v1
    export TR_KEY=sk-xxx
    export TR_MODEL=deepseek/deepseek-v4.1-flash

    python tools/translate_batch.py --batch 0            # 译第 0 批
    python tools/translate_batch.py --from 0 --to 9      # 译 0~9 批
    python tools/translate_batch.py --all --workers 4    # 全部，4 并发

输入：work/translate/in_XXXX.json   输出：work/translate/out_XXXX.json
"""
import argparse
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TDIR = os.path.join(ROOT, "work", "translate")
GLOSSARY = os.path.join(ROOT, "tools", "glossary.md")

BASE = os.environ.get("TR_BASE", "https://openrouter.ai/api/v1")
KEY = os.environ.get("TR_KEY", "")
MODEL = os.environ.get("TR_MODEL", "deepseek/deepseek-v4.1-flash")

SYSTEM = """你是日文卡牌游戏《Lycee Overture》的中文译者。
把用户给的卡名与效果文本翻成简体中文，严格遵守随附的术语规范。
只输出 JSON，不要解释，不要 Markdown 代码块。

要求：
- 参照术语表统一用词，能力标记 [xxx] 的括号结构原样保留
- 数字用阿拉伯数字，AP＋２ → AP+2
- 不确定的专有名词保留日文原文
- 名称字段 name_zh、效果字段 effect_zh
- 输出形如：{"items":[{"code":"LO-0001","name_zh":"…","effect_zh":"…"}]}"""


def load_glossary() -> str:
    try:
        return open(GLOSSARY, encoding="utf-8").read()
    except Exception:  # noqa: BLE001
        return "（未找到术语表）"


def call_api(items, glossary, tries=3):
    user = (f"术语规范：\n{glossary}\n\n"
            f"待翻译条目（JSON）：\n{json.dumps(items, ensure_ascii=False)}\n\n"
            "请返回翻译后的 JSON。")
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user},
        ],
        "temperature": 0.2,
    }).encode("utf-8")
    req = urllib.request.Request(
        BASE.rstrip("/") + "/chat/completions", data=body,
        headers={"Content-Type": "application/json",
                 "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                               "AppleWebKit/537.36 Chrome/131.0 Safari/537.36",
                 "Authorization": f"Bearer {KEY}"})
    for i in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                resp = json.loads(r.read().decode("utf-8"))
            text = resp["choices"][0]["message"]["content"].strip()
            if text.startswith("```"):
                text = text.split("```")[1]
                text = text[4:] if text.lower().startswith("json") else text
            data = json.loads(text)
            return data.get("items", data), None
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                return None, str(e)[:200]
            time.sleep(3 * (i + 1))
    return None, "unknown"


def do_batch(idx):
    inp = os.path.join(TDIR, f"in_{idx:04d}.json")
    outp = os.path.join(TDIR, f"out_{idx:04d}.json")
    if not os.path.exists(inp):
        return idx, 0, f"缺少 {inp}"
    if os.path.exists(outp) and os.path.getsize(outp) > 50:
        return idx, 0, "已存在，跳过"
    items = json.load(open(inp, encoding="utf-8"))
    parsed, err = call_api(items, load_glossary())
    if parsed is None:
        return idx, 0, f"失败: {err}"
    json.dump({"items": parsed}, open(outp, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    return idx, len(parsed), None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int)
    ap.add_argument("--from", dest="start", type=int, default=0)
    ap.add_argument("--to", dest="end", type=int, default=0)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--dir", default=None, help="批次目录，默认 work/translate")
    args = ap.parse_args()

    global TDIR
    if args.dir:
        TDIR = args.dir if os.path.isabs(args.dir) else os.path.join(ROOT, args.dir)

    if not KEY:
        print("缺少 TR_KEY —— 先 export TR_KEY=你的密钥（或写进 .env）")
        return 1
    index = json.load(open(os.path.join(TDIR, "index.json"), encoding="utf-8"))
    total = len(index["batches"])
    if args.batch is not None:
        batches = [args.batch]
    elif args.all:
        batches = list(range(total))
    else:
        batches = list(range(args.start, min(args.end + 1, total)))

    print(f"模型 {MODEL} @ {BASE}，共 {len(batches)} 批，并发 {args.workers}")
    done = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(do_batch, b): b for b in batches}
        for n, f in enumerate(as_completed(futs), 1):
            idx, cnt, err = f.result()
            if err:
                print(f"  批 {idx}: {err}", flush=True)
            else:
                done += cnt
                print(f"  批 {idx}: 译好 {cnt} 条（累计 {done}）", flush=True)
    print("跑完，用 tools/merge_translations.py 合并")
    return 0


if __name__ == "__main__":
    sys.exit(main())
