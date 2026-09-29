#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""快路子：只用 Wayback 已存档的那批卡，按精确时间戳直取（比瞎猜快很多）。

为什么快：
  1. 先问 CDX 索引「哪些卡号被存过、存的时间戳是多少」——只打有货的靶子，
     命中率从 ~27% 提到接近 100%
  2. 用 /web/{timestamp}id_/{url} 直取快照，省掉 "找最近快照" 的那次跳转

用法：
    python tools/fetch_wayback_fast.py --workers 8
"""
import argparse
import json
import os
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_official import parse_detail  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
CARDS = os.path.join(DATA, "cards_raw.json")
FULL = os.path.join(DATA, "cards_full.json")
CACHE = os.path.join(ROOT, "work", "wayback_fast")
INDEX = os.path.join(ROOT, "work", "wayback_index.json")

PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")
CDX = ("https://web.archive.org/cdx/search/cdx?"
       "url=lycee-tcg.com/card/card_detail.pl*&output=json"
       "&fl=original,timestamp&collapse=urlkey&limit=30000")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE
OP = urllib.request.build_opener(
    urllib.request.ProxyHandler({"http": PROXY, "https": PROXY}),
    urllib.request.HTTPSHandler(context=CTX),
)


def build_index():
    """从 CDX 拉「卡号 -> 时间戳」清单，缓存到本地。"""
    if os.path.exists(INDEX):
        d = json.load(open(INDEX, encoding="utf-8"))
        if d.get("codes"):
            print(f"用本地索引：{len(d['codes'])} 个卡号")
            return d["codes"]
    print("查询 Wayback CDX 索引…", flush=True)
    req = urllib.request.Request(CDX, headers={"User-Agent": UA})
    with OP.open(req, timeout=180) as r:
        rows = json.loads(r.read().decode("utf-8", "ignore"))
    codes = {}
    for row in rows[1:]:
        if len(row) < 2:
            continue
        original, ts = row[0], row[1]
        if "cardno=" not in original:
            continue
        code = original.split("cardno=")[-1]
        # 去掉 URL 里可能带的参数，规范化成 LO-0001 这种
        code = code.split("&")[0].strip()
        if not code:
            continue
        prev = codes.get(code)
        if prev is None or ts > prev[0]:
            codes[code] = (ts, original)
    out = {k: {"ts": v[0], "url": v[1]} for k, v in codes.items()}
    os.makedirs(os.path.dirname(INDEX), exist_ok=True)
    json.dump({"codes": out}, open(INDEX, "w", encoding="utf-8"), ensure_ascii=False)
    print(f"索引就绪：{len(out)} 个卡号有存档")
    return out


def fetch_one(code, meta, tries=3):
    os.makedirs(CACHE, exist_ok=True)
    local = os.path.join(CACHE, f"{code}.html")
    if os.path.exists(local) and os.path.getsize(local) > 500:
        with open(local, encoding="utf-8", errors="ignore") as f:
            return code, parse_detail(f.read()), None
    url = f"https://web.archive.org/web/{meta['ts']}id_/{meta['url']}"
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with OP.open(req, timeout=90) as r:
                html = r.read().decode("utf-8", "ignore")
            if len(html) < 500:
                return code, None, "过短"
            with open(local, "w", encoding="utf-8") as f:
                f.write(html)
            return code, parse_detail(html), None
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                return code, None, str(e)[:60]
            time.sleep(1.5 * (i + 1))
    return code, None, "unreachable"


def merge_save(cards):
    json.dump(cards, open(FULL, "w", encoding="utf-8"), ensure_ascii=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    index = build_index()
    codes = list(index.keys())
    if args.limit:
        codes = codes[: args.limit]

    base = json.load(open(CARDS, encoding="utf-8"))
    by_code = {c["code"]: dict(c) for c in base}
    if os.path.exists(FULL):
        for c in json.load(open(FULL, encoding="utf-8")):
            if c.get("color") and c["code"] in by_code:
                by_code[c["code"]] = c

    todo = [c for c in codes if not by_code.get(c, {}).get("color")]
    print(f"目标 {len(codes)} 个，其中缺数据 {len(todo)} 个，并发 {args.workers}",
          flush=True)

    ok = fail = 0
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(fetch_one, c, index[c]): c for c in todo}
        for n, f in enumerate(as_completed(futs), 1):
            code, info, err = f.result()
            if info:
                rec = by_code.setdefault(code, {"code": code, "cid": "", "name": "",
                                                "img": "", "effect": ""})
                rec.update({
                    "name": info.get("name_official") or rec.get("name"),
                    "title_jp": info.get("title_jp"),
                    "kind": info.get("kind"),
                    "rarity": info.get("rarity"),
                    "color": info.get("color"),
                    "ex": info.get("ex"),
                    "cost": info.get("cost"),
                    "limit": info.get("limit"),
                    "ap": info.get("ap"), "dp": info.get("dp"),
                    "sp": info.get("sp"), "dmg": info.get("dmg"),
                    "type": info.get("type"),
                    "leader": info.get("is_leader", False),
                    "restriction": info.get("limit") or None,
                    "series": info.get("series"),
                    "illustrator": info.get("illustrator"),
                    "release": info.get("releaseInfo"),
                    "effect_jp": info.get("effect_jp"),
                    "source": "wayback",
                })
                ok += 1
            else:
                fail += 1
            if n % 50 == 0 or n == len(todo):
                sp = n / max(time.time() - t0, 1)
                left = (len(todo) - n) / sp if sp else 0
                print(f"  {n}/{len(todo)} 成功{ok} 失败{fail}  "
                      f"{sp:.2f}/s  预计还剩 {left/60:.0f} 分钟", flush=True)
                merge_save(list(by_code.values()))
    merge_save(list(by_code.values()))
    have = len([c for c in by_code.values() if c.get("color")])
    print(f"完成：本次成功 {ok}，失败 {fail}；库里有完整数据 {have}/{len(by_code)}")


if __name__ == "__main__":
    main()
