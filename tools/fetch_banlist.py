#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取并解析官方「正誤訂正・禁止・制限カード一覧」（要求 L83-84）。

官方页面（无需登录，直连可达）：
    https://lycee-tcg.com/pages/page_0007893.html

页面分四个区块，本脚本取后三个（勘误跟构筑合法性无关）：

    構築制限カード  —— 「同バージョン（同ブランド）のカードのみで構築された
                       デッキ」に限り入れられる。也就是：**只能在单一作品/
                       单一会社的卡组里用**。
    枚数制限カード  —— 同名卡最多几张（官方目前写「無し」）。
    使用禁止カード  —— 任何卡组都不能放。

产出 assets/data/banlist.json：
    {
      "source": "https://lycee-tcg.com/pages/page_0007893.html",
      "fetchedAt": "2026-09-15T...",
      "updatedAt": "2026/06/22",          # 官方页面上写的更新日期
      "history": [{"date": "...", "text": "..."}],
      "forbidden": ["LO-0778", ...],
      "constructionLimited": ["LO-0134", ...],
      "copyLimited": {"LO-xxxx": 1, ...}
    }

用法：
    python tools/fetch_banlist.py                 # 抓官方 + 写入
    python tools/fetch_banlist.py --from-file X   # 解析本地已存的 HTML
    python tools/fetch_banlist.py --dry           # 只打印不写
"""
import argparse
import json
import os
import re
import ssl
import sys
import urllib.request
from datetime import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "data", "banlist.json")
URL = "https://lycee-tcg.com/pages/page_0007893.html"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "Chrome/131.0 Safari/537.36")
PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"

# 页面上四个区块的标题（用来切段）
SECTIONS = {
    "forbidden": "使用禁止カード",
    "constructionLimited": "構築制限カード",
    "copyLimited": "枚数制限カード",
}


def fetch(url=URL, use_proxy=False):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    handlers = [urllib.request.HTTPSHandler(context=ctx)]
    if use_proxy:
        handlers.insert(0, urllib.request.ProxyHandler(
            {"http": PROXY, "https": PROXY}))
    op = urllib.request.build_opener(*handlers)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with op.open(req, timeout=60) as r:
        return r.read().decode("utf-8", "ignore")


def text_of(html):
    t = re.sub(r"<br\s*/?>", "\n", html)
    t = re.sub(r"<[^>]+>", " ", t)
    t = t.replace("&nbsp;", " ").replace("&dagger;", "†")
    return re.sub(r"[ \t]+", " ", t)


def split_sections(html):
    """按正文中最后一次区块标题切段。

    更新履历和勘误文本会提到限制区块标题，不能从页面第一次出现的
    位置开始抓，否则会把勘误卡误收进禁限表。正文正式区块标题取
    各标题最后一次出现的位置。
    """
    marks = []
    for key, title in SECTIONS.items():
        hits = list(re.finditer(re.escape(title), html))
        if hits:
            marks.append((hits[-1].start(), key))
    marks.sort()
    out = {}
    for i, (pos, key) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(html)
        out[key] = html[pos:end]
    return out


def _tables(seg):
    """取区块内所有正式表格；一个区块可能按生效日拆成多张表。"""
    tables = [m.group(0) for m in re.finditer(
        r"<table\b[^>]*>.*?</table>", seg, re.S | re.I)]
    return tables or [seg]


def parse_codes(seg):
    """从正式区块表格里取卡号 + 卡名 + 生效日期。"""
    rows = []
    for table in _tables(seg):
        for tr in re.finditer(r"<tr>(.*?)</tr>", table, re.S):

            cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", tr.group(1), re.S)
            cells = [re.sub(r"\s+", " ", text_of(c)).strip() for c in cells]
            cells = [c for c in cells if c]
            if not cells:
                continue
            code = None
            for c in cells:
                m = re.search(r"\b(LO-\d{3,5}(?:-[A-Z]{1,2})?)\b", c)
                if m:
                    code = m.group(1)
                    break
            if not code:
                continue
            name = ""
            for c in cells:
                if code not in c and not re.match(r"^\d{4}/\d{1,2}/\d{1,2}$", c):
                    name = c
                    break
            date = ""
            for c in cells:
                if re.match(r"^\d{4}/\d{1,2}/\d{1,2}$", c):
                    date = c
                    break
            rows.append({"code": code, "name": name, "date": date})
    return rows


def parse_copy_limits(seg):
    """枚数制限：表格里通常写「同名卡最多 N 张」"""
    limits = {}
    plain = text_of(seg)
    if re.search(r"無し|なし", plain) and not re.search(r"<table", seg):
        return limits
    for tr in re.finditer(r"<tr>(.*?)</tr>", seg, re.S):
        cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", tr.group(1), re.S)
        cells = [re.sub(r"\s+", " ", text_of(c)).strip() for c in cells]
        cells = [c for c in cells if c]
        if not cells:
            continue
        code = None
        n = None
        for c in cells:
            m = re.search(r"\b(LO-\d{3,5}(?:-[A-Z]{1,2})?)\b", c)
            if m and code is None:
                code = m.group(1)
            mn = re.search(r"(\d+)\s*枚", c)
            if mn:
                n = int(mn.group(1))
        if code and n:
            limits[code] = n
    return limits


def parse_history(html):
    """更新履歴：形如 2026/6/22 構築制限カード一覧を更新しました。…"""
    hist = []
    plain = text_of(html)
    for m in re.finditer(r"(\d{4}/\d{1,2}/\d{1,2})\s*([^\d]{0,220})", plain):
        d, body = m.group(1), m.group(2).strip()
        body = re.sub(r"\s+", " ", body)
        if "更新" in body or "対象カード" in body:
            hist.append({"date": d, "text": body[:200]})
    # 去重 + 按日期倒序
    seen, uniq = set(), []
    for h in hist:
        k = (h["date"], h["text"][:40])
        if k in seen:
            continue
        seen.add(k)
        uniq.append(h)

    def key(h):
        y, mo, dd = h["date"].split("/")
        return (int(y), int(mo), int(dd))

    uniq.sort(key=key, reverse=True)
    return uniq


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-file")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--proxy", action="store_true",
                    help="走本地代理（默认直连）")
    args = ap.parse_args()

    if args.from_file:
        html = open(args.from_file, encoding="utf-8").read()
    else:
        try:
            html = fetch(use_proxy=args.proxy)
        except Exception as e:      # noqa: BLE001
            print(f"抓取失败：{e}")
            print("提示：官方站多数时候可直连；若被挡可加 --proxy")
            return 1

    secs = split_sections(html)
    data = {
        "source": URL,
        "fetchedAt": datetime.now().isoformat(timespec="seconds"),
        "forbidden": [],
        "constructionLimited": [],
        "copyLimited": {},
        "history": parse_history(html),
    }

    detail = {}
    for key in ("forbidden", "constructionLimited"):
        seg = secs.get(key, "")
        rows = parse_codes(seg)
        data[key] = sorted({r["code"] for r in rows})
        detail[key] = rows
    data["copyLimited"] = parse_copy_limits(secs.get("copyLimited", ""))

    # 官方页面上的"更新日"
    plain = text_of(html)
    m = re.search(r"（(\d{4}/\d{2}/\d{2})現在）", plain)
    if m:
        data["updatedAt"] = m.group(1)

    print(f"使用禁止    : {len(data['forbidden'])} 张")
    for c in data["forbidden"][:6]:
        print(f"    {c}")
    print(f"構築制限    : {len(data['constructionLimited'])} 张")
    for c in data["constructionLimited"][:6]:
        print(f"    {c}")
    print(f"枚数制限    : {data['copyLimited'] or '（无）'}")
    print(f"更新履歴    : {len(data['history'])} 条")
    for h in data["history"][:3]:
        print(f"    {h['date']}  {h['text'][:70]}")
    if data.get("updatedAt"):
        print(f"官方更新日  : {data['updatedAt']}")

    if args.dry:
        print("\n（--dry，没写文件）")
        return 0

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(data, open(OUT, "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"\n写到 {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
