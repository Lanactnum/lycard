#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从官方卡表分页直接抓完整卡数据（比逐张进详情页快 30 倍）。

列表页每一张卡的结构（实测）：
    <td rowspan="5"><img src="./image/LO-6960-A.png">          ← 卡图
    <td>LO-6960-A</td>                                          ← 卡号
    <td colspan="7"><a href="./card_detail.pl?cardno=...">名字</a></td>
    <td>エリア</td><td>P</td>                                   ← 卡种 / 稀有度
    <tr class="menutitle"> 属性 EX コスト 制限 AP DP SP DMG タイプ
    <tr>                   月  2  月月月  _    _  _  _  _   _    ← 数值
    <tr>                   <td colspan="10">效果文本</td>
    后面还有 Version : / illust : / 初出 :

产出：assets/data/cards_full.json（含官方全部字段）
"""
import json
import os
import re
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "data", "cards_full.json")
CACHE = os.path.join(ROOT, "work", "list_html")
LIST = "https://lycee-tcg.com/card/?page={page}"
PROXY = os.environ.get("HTTPS_PROXY") or "http://127.0.0.1:10809"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def build_opener(proxy: str | None):
    """proxy=None 表示直连（换了出口 IP 时用这个）。"""
    handlers = [urllib.request.HTTPSHandler(context=CTX)]
    if proxy:
        handlers.insert(0, urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    else:
        handlers.insert(0, urllib.request.ProxyHandler({}))
    return urllib.request.build_opener(*handlers)


OP = build_opener(PROXY)


def clean(frag: str) -> str:
    t = re.sub(r"<br\s*/?>", "\n", frag)
    t = re.sub(r"<[^>]+>", "", t)
    t = t.replace("&nbsp;", " ").replace("&amp;", "&").replace("&#039;", "'")
    t = t.replace("&quot;", '"').replace("&lt;", "<").replace("&gt;", ">")
    return re.sub(r"[ \t\u3000]+", " ", t).strip()


def cells_of(row_html: str):
    return [clean(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", row_html, re.S)]


def num(s):
    m = re.search(r"-?\d+", s or "")
    return int(m.group(0)) if m else None


def parse_page(html: str):
    """返回本页所有卡的 dict 列表。"""
    cards = []
    starts = [m.start() for m in re.finditer(r'<td rowspan="5"', html)]
    for i, s in enumerate(starts):
        e = starts[i + 1] if i + 1 < len(starts) else len(html)
        blk = html[s:e]
        rows = re.findall(r"<tr[^>]*>(.*?)</tr>", blk, re.S)
        card = {}

        m = re.search(r"card_detail\.pl\?cardno=([A-Za-z0-9\-]+)", blk)
        if m:
            card["code"] = m.group(1)
        m = re.search(r'card_detail\.pl\?cardno=[^"]+"[^>]*>(.*?)</a>', blk, re.S)
        if m:
            raw = clean(m.group(1))
            parts = [p.strip() for p in raw.split("\n") if p.strip()]
            card["title_jp"] = parts[0] if len(parts) > 1 else ""
            card["name"] = parts[-1] if parts else raw
        m = re.search(r"\./image/([A-Za-z0-9\-_]+)\.png", blk)
        if m:
            card["img"] = f"https://lycee-tcg.com/card/image/{m.group(1)}.png"

        # 卡种 / 稀有度：名字行之后的两个 td
        for r in rows[:3]:
            cs = cells_of(r)
            if len(cs) >= 2 and cs[0] == card.get("code"):
                card["kind"] = cs[2] if len(cs) > 2 else ""
                card["rarity"] = cs[3] if len(cs) > 3 else ""
                break

        # 表头行 + 数值行
        for j, r in enumerate(rows):
            cs = cells_of(r)
            if cs and cs[0] == "属性" and j + 1 < len(rows):
                v = cells_of(rows[j + 1])
                if len(v) >= 8:
                    card["color"] = v[0]
                    card["ex"] = num(v[1])
                    card["cost"] = v[2]
                    card["limit"] = v[3]
                    card["ap"] = num(v[4])
                    card["dp"] = num(v[5])
                    card["sp"] = num(v[6])
                    card["dmg"] = num(v[7])
                    card["type"] = v[8] if len(v) > 8 else ""
                if j + 2 < len(rows):
                    eff = clean(rows[j + 2])
                    eff = re.split(r"\s*初出\s*:", eff)[0]
                    eff = re.sub(r"\[このカードを使用した[^\]]*\]", "", eff)
                    card["effect_jp"] = eff.strip()
                break

        text = clean(blk)
        m = re.search(r"Version\s*:?\s*([^\n]{0,80})", text)
        if m:
            card["series"] = m.group(1).strip()
        m = re.search(r"初出\s*:?\s*([^\n]{0,80})", text)
        if m:
            card["release"] = m.group(1).strip()
        m = re.search(r"illust\s*:?\s*([^\n]{0,60})", text)
        if m and m.group(1).strip():
            card["illustrator"] = m.group(1).strip()

        blob = f"{card.get('limit','')} {card.get('type','')} {card.get('effect_jp','')}"
        card["leader"] = "リーダー" in blob
        card["restriction"] = card.get("limit") or None

        if card.get("code"):
            cards.append(card)
    return cards


def fetch_page(page, tries=3):
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, f"{page}.html")
    if os.path.exists(f) and os.path.getsize(f) > 2000:
        return page, open(f, encoding="utf-8", errors="ignore").read(), None
    for i in range(tries):
        try:
            req = urllib.request.Request(LIST.format(page=page),
                                         headers={"User-Agent": UA})
            with _OP_REF[0].open(req, timeout=60) as r:
                html = r.read().decode("utf-8", "ignore")
            with open(f, "w", encoding="utf-8") as fh:
                fh.write(html)
            return page, html, None
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                return page, None, str(e)
            time.sleep(2.0 * (i + 1))
    return page, None, "unknown"


_OP_REF = [OP]


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--pages", type=int, default=1000)
    ap.add_argument("--workers", type=int, default=2,
                    help="并发数。官方站会被高频访问拉黑，建议 1~2")
    ap.add_argument("--delay", type=float, default=1.0,
                    help="每张页面之间的等待秒数")
    ap.add_argument("--proxy", default=PROXY,
                    help="代理地址；填 none 表示直连（换出口 IP 后用）")
    args = ap.parse_args()

    global _OP_REF
    _OP_REF[0] = build_opener(None if args.proxy.lower() in ("none", "", "off")
                              else args.proxy)
    print(f"网络：{'直连' if _OP_REF[0] is not None and args.proxy.lower() in ('none','','off') else args.proxy}")

    total_pages = args.pages
    all_cards = {}
    t0 = time.time()
    page = 1
    empty = 0

    while page <= total_pages and empty < 2:
        batch = list(range(page, min(page + args.workers, total_pages + 1)))
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            futs = {ex.submit(fetch_page, p): p for p in batch}
            got = {}
            for f in as_completed(futs):
                p, html, err = f.result()
                got[p] = html
        for p in batch:
            html = got.get(p)
            if not html:
                continue
            cs = parse_page(html)
            if cs:
                empty = 0
                for c in cs:
                    all_cards[c["code"]] = c
            else:
                empty += 1
        page += len(batch)
        if page % 20 < args.workers:
            print(f"  第 {page} 页，累计 {len(all_cards)} 张（{time.time()-t0:.0f}s）",
                  flush=True)
            # 边跑边落盘，被打断也不亏
            with open(OUT, "w", encoding="utf-8") as f:
                json.dump(sorted(all_cards.values(), key=lambda c: c["code"]),
                          f, ensure_ascii=False)
        time.sleep(args.delay)

    out = sorted(all_cards.values(), key=lambda c: c["code"])
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False)
    print(f"完成：{len(out)} 张 -> {OUT}（{time.time()-t0:.0f}s）")


if __name__ == "__main__":
    main()
