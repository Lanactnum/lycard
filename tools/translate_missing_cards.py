#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""只翻「还没翻好的」卡名/效果，已翻好的一条都不动。

为什么需要一个单独的工具
------------------------
`translate_batch.py` 是按**批**跑的，而且它看到 `out_XXXX.json` 已存在就跳过整批。
补几十个漏项时为这点东西重切批次、还会把已译好的重译一遍（花钱且可能变差）。

本工具的做法：
  · 直接从 `cards_app.json` + `translations_zh.json` 算出**缺口集合**
  · 只把这些条目送 API
  · 结果**并进** `translations_zh.json`（不动其他条目）

「缺口」的判定
--------------
卡名：
  · 空
  · **纯日文名**（一个汉字都没有）—— 默认补这类
  · 汉日混排 —— 默认不动（多半是角色专名，重译容易变差），要补加 `--also-mixed`
效果：
  · 日文原文有实际内容（不是 `-` / 空）但中文效果为空

关于专有名词
------------
原来的提示词写的是「不确定的专有名词保留日文原文」，结果 154 个片假名卡名
（ゲイボルグ＝ゼロ、ねこにゃー…）原样留了下来，用户看到的就是「翻译不完全」。
本工具改用**音译规则**：片假名专有名词按常见对音转写，不再原样保留。

用法
----
    export TR_BASE=https://www.micuapi.ai/v1
    export TR_KEY=<从 .env 的 HERMES_CUSTOM_MICU_API_KEY 取>
    export TR_MODEL=gpt-5.6-sol

    python tools/translate_missing_cards.py --dry-run      # 看有多少缺口
    python tools/translate_missing_cards.py --limit 40     # 先试一小批
    python tools/translate_missing_cards.py                # 全补
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARDS = os.path.join(ROOT, "assets", "data", "cards_app.json")
TR = os.path.join(ROOT, "assets", "data", "translations_zh.json")
GLOSSARY = os.path.join(ROOT, "tools", "glossary.md")

BASE = os.environ.get("TR_BASE", "https://www.micuapi.ai/v1")
KEY = os.environ.get("TR_KEY", "")
MODEL = os.environ.get("TR_MODEL", "gpt-5.6-sol")

KANA = re.compile(r"[\u3041-\u3096\u30a1-\u30fa]")   # 排除 ・ 与 ー
HAN = re.compile(r"[\u4e00-\u9fff]")

SYSTEM = """你是日文卡牌游戏《Lycee Overture》的中文译者。把用户给的卡名/效果翻成简体中文。

硬性规则：
1. **片假名/平假名专有名词必须音译成中文**，不要原样保留日文。
   按常见对音转写：ヴ→维、ゲ→盖、ゼ→泽、リ→莉、ィ→伊/依、ー 按前一个音延长或省略、
   ＝→· 或「=」、・→·。
   例：ゲイボルグ＝ゼロ → 盖尔伯格＝零；ねこにゃー → 猫喵；ぴよたん → 叽咕炭。
   实在无法对音的拟声词（如「ぴこぴこ」）才可意译或保留。
2. 能力标记 [xxx] 的方括号结构原样保留，标记本身按术语表翻。
3. 「」内的内容是引用其他卡名，保留原样（不要翻），**但里面的日文「無」要写成「无」**。
   效果文本里**一律不许出现日文「無」**（项目有测试卡这条）。

3b. **能力标记必须用下面这套新译名**（旧译名已被淘汰，用了测试会挂）：
   [激进]→[进取心]  [步进]→[移动]  [侧步]→[横移]  [指令步]→[竖移]
   [指令切换]→[列交换]  [跳跃]→[跳]  [辅助]→[援助]  [交战]→[迎战]
   [恢复]→[重振]  [毅力]→[再起]  [主角]→[主演]  [回合恢复]→[回合补正]
   （注意：普通用语里的「恢复」不是能力名，照常写「恢复」，别改。）
4. 数字用阿拉伯数字：AP＋２ → AP+2。
5. 卡名要简洁（一般不超过 20 个汉字）。
6. 只输出 JSON，不要解释、不要 Markdown 代码块。

输出格式：
{"items":[{"code":"LO-0001","name_zh":"…","effect_zh":"…"}]}
没让你翻的字段原样返回空字符串。"""


def load_glossary():
    try:
        return open(GLOSSARY, encoding="utf-8").read()
    except Exception:  # noqa: BLE001
        return "（未找到术语表）"


def name_of(c, tr):
    t = tr.get(c["code"], {})
    return (t.get("name") or c.get("name_zh") or "").strip()


def effect_of(c, tr):
    t = tr.get(c["code"], {})
    return (t.get("effect") or c.get("effect_zh") or "").strip()


def build_gaps(cards, tr, also_mixed=False):
    """返回 (需要补名字的, 需要补效果的)。"""
    need_name, need_eff = [], []
    for c in cards:
        code = c["code"]
        nm = name_of(c, tr)
        ej = (c.get("effect_jp") or "").strip()
        ef = effect_of(c, tr)

        if not nm:
            need_name.append(c)
        elif KANA.search(nm):
            pure_jp = not HAN.search(nm)
            if pure_jp or also_mixed:
                need_name.append(c)

        if ej and ej not in ("-", "－", "—") and len(ej) > 2 and not ef:
            need_eff.append(c)
    return need_name, need_eff


STRICT_EXTRA = """

\n\n【这一轮是补翻】上一轮你把这些条目原样返回了日文，不合格。
本次**必须**给出中文：片假名一律音译（レオ→雷奥、アリエシア→阿莉西亚），
禁止输出任何假名。做不到音的拟声词也要用中文近似字写出来。"""


def call_api(items, glossary, tries=3, strict=False):
    user = (f"术语规范：\n{glossary}\n\n"
            f"待翻译条目（JSON）：\n{json.dumps(items, ensure_ascii=False)}\n\n"
            "请返回翻译后的 JSON。")
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM + (STRICT_EXTRA if strict else "")},
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
    last = None
    for i in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                resp = json.loads(r.read().decode("utf-8"))
            text = resp["choices"][0]["message"]["content"].strip()
            if text.startswith("```"):
                text = text.split("```")[1]
                text = text[4:] if text.lower().lstrip().startswith("json") else text
            data = json.loads(text)
            return data.get("items", data), None
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(3 * (i + 1))
    return None, str(last)[:200]


def still_open(w, tr):
    """这条还缺吗（重试用）。"""
    code = w["code"]
    ent = tr.get(code) or {}
    if w["want"] == "name":
        nm = (ent.get("name") or "").strip()
        return (not nm) or bool(KANA.search(nm))
    ef = (ent.get("effect") or "").strip()
    return not ef


def merge(tr, got):
    changed = 0
    for code, it in got.items():
        ent = tr.get(code) or {}
        if (it.get("name_zh") or "").strip():
            ent["name"] = it["name_zh"].strip()
            changed += 1
        if (it.get("effect_zh") or "").strip():
            ent["effect"] = it["effect_zh"].strip()
            changed += 1
        if ent:
            tr[code] = ent
    return changed


def run_pass(work, glossary, args, strict=False):
    batches = [work[i:i + args.batch] for i in range(0, len(work), args.batch)]
    got, done = {}, 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(call_api, b, glossary, 3, strict): i
                for i, b in enumerate(batches)}
        for f in as_completed(futs):
            i = futs[f]
            items, err = f.result()
            if items is None:
                print(f"  批 {i}: 失败 {err}", flush=True)
                continue
            for it in items:
                if isinstance(it, dict) and it.get("code"):
                    got[it["code"]] = it
            done += len(items)
            print(f"  批 {i}: {len(items)} 条（累计 {done}）", flush=True)
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=0, help="最多处理多少条（0=全部）")
    ap.add_argument("--only", choices=["name", "effect"], default=None)
    ap.add_argument("--also-mixed", action="store_true",
                    help="连「汉字+假名混排」的卡名也重译（会更彻底，但也可能改坏原本可以的）")
    ap.add_argument("--batch", type=int, default=40)
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()

    cards = json.load(open(CARDS, encoding="utf-8"))
    tr = json.load(open(TR, encoding="utf-8")) if os.path.exists(TR) else {}

    need_name, need_eff = build_gaps(cards, tr, also_mixed=args.also_mixed)
    if args.only == "name":
        need_eff = []
    elif args.only == "effect":
        need_name = []

    print(f"卡名缺口 {len(need_name)} 张"
          f"{'（含汉日混排）' if args.also_mixed else '（只算纯日文名）'}"
          f"／效果缺口 {len(need_eff)} 张")

    work = []
    for c in need_name:
        work.append({"code": c["code"], "name_jp": c.get("name", ""),
                     "title_jp": c.get("title_jp", ""), "want": "name"})
    for c in need_eff:
        work.append({"code": c["code"], "effect_jp": (c.get("effect_jp") or "")[:1200],
                     "want": "effect"})

    if args.limit:
        work = work[: args.limit]
    if not work:
        print("没有要补的")
        return 0
    print(f"本轮处理 {len(work)} 条，切 {args.batch} 条/批，并发 {args.workers}")
    if args.dry_run:
        for w in work[:15]:
            print("  ", w.get("code"), "|", (w.get("name_jp") or w.get("effect_jp", ""))[:50])
        print("--dry-run，不调 API")
        return 0

    if not KEY:
        print("缺少 TR_KEY", file=sys.stderr)
        return 2

    glossary = load_glossary()
    pending = list(work)
    total_changed = 0
    # 最多三轮：模型偶尔会「原样返回日文」，校验出来就带着更强措辞重试
    for attempt in range(1, 4):
        if not pending:
            break
        print(f"\n── 第 {attempt} 轮：{len(pending)} 条"
              f"{'（严格模式）' if attempt > 1 else ''} ──", flush=True)
        got = run_pass(pending, glossary, args, strict=attempt > 1)
        total_changed += merge(tr, got)
        if got:
            tmp = TR + ".tmp"
            json.dump(tr, open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
            os.replace(tmp, TR)   # 每轮都落盘，中途断了也不白跑
        left = [w for w in pending if still_open(w, tr)]
        print(f"  本轮后仍缺 {len(left)} 条", flush=True)
        if len(left) == len(pending) and attempt > 1:
            print("  没有进展，停止重试", flush=True)
            pending = left
            break
        pending = left

    if total_changed:
        print(f"\n已并进 {TR}（改动 {total_changed} 个字段，共 {len(tr)} 条）")
        if pending:
            print(f"⚠️ 仍有 {len(pending)} 条没翻出来（模型拒绝音译），清单：")
            for w in pending[:15]:
                print("   ", w["code"])
        print("下一步：python tools/make_app_data.py && python tools/build_search_keys.py")
    else:
        print("没有拿到有效结果，未写盘")
    return 0


if __name__ == "__main__":
    sys.exit(main())
