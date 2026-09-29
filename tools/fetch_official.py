#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""抓取 lycee-tcg.com 官方卡详情（属性/AP/DP/SP/DMG/类型/作品/画家/初出）。

⚠️ 本机网络对 lycee-tcg.com 的 80/443 是被挡的（ping 通但连接超时），
   必须先开代理再用。支持三种给代理的方式：
     1) 环境变量 HTTPS_PROXY=http://127.0.0.1:10809
     2) 命令行 --proxy http://127.0.0.1:10809
     3) 都不给就直连（大概率超时）

用法：
    python tools/fetch_official.py --limit 20          # 先试 20 张
    python tools/fetch_official.py --all               # 全部（很慢，慢慢跑）
    python tools/fetch_official.py --all --proxy http://127.0.0.1:10809
    python tools/fetch_official.py --images            # 顺带下卡图

产出：
    assets/data/cards_full.json     带官方字段的卡表
    work/raw_html/{code}.html       原始页面（方便以后修解析）
    assets/cards/{code}.png         卡图（--images 时）
"""
import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
CARDS = os.path.join(DATA, "cards_raw.json")
FULL = os.path.join(DATA, "cards_full.json")
RAW_DIR = os.path.join(ROOT, "work", "raw_html")
IMG_DIR = os.path.join(ROOT, "assets", "cards")

DETAIL = "https://lycee-tcg.com/card/card_detail.pl?cardno={code}"
IMAGE = "https://lycee-tcg.com/card/image/{code}.png"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

CTX = ssl.create_default_context()
CTX.check_hostname = False
CTX.verify_mode = ssl.CERT_NONE


def opener(proxy: str | None):
    if proxy:
        h = urllib.request.ProxyHandler({"http": proxy, "https": proxy})
        return urllib.request.build_opener(h, urllib.request.HTTPSHandler(context=CTX))
    return urllib.request.build_opener(urllib.request.HTTPSHandler(context=CTX))


def cell_text(html_frag: str) -> str:
    t = re.sub(r"<br\s*/?>", "\n", html_frag)
    t = re.sub(r"<[^>]+>", "", t)
    t = t.replace("&nbsp;", " ").replace("&amp;", "&")
    return re.sub(r"[ \t\u3000]+", " ", t).strip()


def parse_detail(html: str) -> dict:
    """从卡详情页抽出字段。

    实测页面结构（每张卡一串 <tr>）：
      row0 : [_, 卡号, 卡名（含称号，\n 分隔）, 卡种(キャラクター等), 稀有度]
      row1 : 表头 [属性, EX, コスト, 制限, AP, DP, SP, DMG, タイプ]
      row2 : 数值 [雪, 2, 雪雪, , 3, 3, 2, 0, ]
      row3 : 效果文本（末尾跟着「初出 : …」「[このカードを使用した…]」）
      row4 : [Version : xxx, 系列略号, illust : 画家]
    """
    out: dict = {}
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S)
    cells_all = []
    for r in rows:
        cells = [cell_text(c) for c in re.findall(r"<td[^>]*>(.*?)</td>", r, re.S)]
        if cells:
            cells_all.append(cells)

    # row0：卡号/卡名/卡种/稀有度
    for cells in cells_all[:3]:
        if len(cells) >= 4 and cells[1].startswith(("LO-", "EX-", "PR-")):
            out["code_official"] = cells[1]
            raw_name = cells[2]
            parts = [p.strip() for p in raw_name.split("\n") if p.strip()]
            out["title_jp"] = parts[0] if len(parts) > 1 else ""
            out["name_official"] = parts[-1] if parts else raw_name
            out["kind"] = cells[3] if len(cells) > 3 else ""
            out["rarity"] = cells[4] if len(cells) > 4 else ""
            break

    # 找表头行，取下一行做数值
    stats = None
    for i, cells in enumerate(cells_all):
        if cells and cells[0] == "属性" and len(cells) >= 9:
            if i + 1 < len(cells_all):
                stats = cells_all[i + 1]
            if i + 2 < len(cells_all):
                eff = cells_all[i + 2][0] if cells_all[i + 2] else ""
                eff = re.split(r"\s*初出\s*:", eff)[0]
                eff = re.sub(r"\[このカードを使用した[^\]]*\]", "", eff).strip()
                out["effect_jp"] = eff[:3000]
            break

    if stats and len(stats) >= 8:
        out["color"] = stats[0]
        out["ex"] = stats[1]
        out["cost"] = stats[2]
        out["limit"] = stats[3]          # 制限栏：空 / －－－ / ●●● 之类
        out["ap"] = _num(stats[4])
        out["dp"] = _num(stats[5])
        out["sp"] = _num(stats[6])
        out["dmg"] = _num(stats[7])
        out["type"] = stats[8] if len(stats) > 8 else ""
        # 制限栏或类型栏出现「リーダー」即视为 leader 卡
        blob = f"{out['limit']} {out['type']} {out.get('effect_jp', '')}"
        out["is_leader"] = "リーダー" in blob

    plain = cell_text(html)
    m = re.search(r"Version\s*:?\s*([^\n]{0,80})", plain)
    if m:
        out["series"] = m.group(1).strip()
    m = re.search(r"初出\s*:?\s*([^\n]{0,80})", plain)
    if m:
        out["releaseInfo"] = m.group(1).strip()
    m = re.search(r"illust\s*:?\s*([^\n<]{0,60})", html)
    if m and m.group(1).strip():
        out["illustrator"] = m.group(1).strip()

    out["rows"] = cells_all[:6]
    return out


def _num(s: str):
    m = re.search(r"-?\d+", s or "")
    return int(m.group(0)) if m else None


def fetch_one(op, code: str, tries: int = 4, save_html: bool = True):
    url = DETAIL.format(code=code)
    # 断点续传：已经抓过的页面直接读本地，不重复请求
    if save_html:
        local = os.path.join(RAW_DIR, f"{code}.html")
        if os.path.exists(local) and os.path.getsize(local) > 500:
            try:
                with open(local, encoding="utf-8") as f:
                    return code, parse_detail(f.read()), None
            except Exception:  # noqa: BLE001
                pass
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with op.open(req, timeout=60) as r:
                html = r.read().decode("utf-8", "ignore")
            if len(html) < 500:
                raise RuntimeError(f"内容过短 {len(html)}")
            if save_html:
                os.makedirs(RAW_DIR, exist_ok=True)
                with open(os.path.join(RAW_DIR, f"{code}.html"), "w",
                          encoding="utf-8") as f:
                    f.write(html)
            return code, parse_detail(html), None
        except Exception as e:  # noqa: BLE001
            if i == tries - 1:
                return code, None, str(e)
            time.sleep(2 * (i + 1))
    return code, None, "unreachable"


def fetch_image(op, code: str):
    try:
        os.makedirs(IMG_DIR, exist_ok=True)
        dst = os.path.join(IMG_DIR, f"{code}.png")
        if os.path.exists(dst) and os.path.getsize(dst) > 1000:
            return code, True
        req = urllib.request.Request(IMAGE.format(code=code),
                                     headers={"User-Agent": UA})
        with op.open(req, timeout=60) as r:
            data = r.read()
        if len(data) < 1000:
            return code, False
        with open(dst, "wb") as f:
            f.write(data)
        return code, True
    except Exception:  # noqa: BLE001
        return code, False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proxy", default=os.environ.get("HTTPS_PROXY")
                    or os.environ.get("https_proxy"))
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--images", action="store_true")
    ap.add_argument("--workers", type=int, default=4)
    args = ap.parse_args()

    if not os.path.exists(CARDS):
        print(f"缺少卡表 {CARDS}，先跑 fetch_cards.py")
        sys.exit(1)

    base = json.load(open(CARDS, encoding="utf-8"))
    codes = [c["code"] for c in base]
    if args.limit:
        codes = codes[: args.limit]
    elif not args.all:
        print("只跑前 20 张做验证；确认没问题后用 --all 全量。")
        codes = codes[:20]

    op = opener(args.proxy)
    print(f"共 {len(codes)} 张，代理：{args.proxy or '（直连）'}")

    results = {}
    ok = fail = 0
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        futs = {ex.submit(fetch_one, op, c): c for c in codes}
        for n, f in enumerate(as_completed(futs), 1):
            code, parsed, err = f.result()
            if parsed:
                results[code] = parsed
                ok += 1
            else:
                fail += 1
            if n % 20 == 0 or n == len(codes):
                print(f"  {n}/{len(codes)}  成功 {ok}  失败 {fail}", flush=True)

    if args.images:
        with ThreadPoolExecutor(max_workers=6) as ex:
            list(ex.map(lambda c: fetch_image(op, c), codes))

    # 合并进卡表（字段名与 Dart 端 LyceeCard.fromJson 对齐）
    by_code = {c["code"]: c for c in base}
    for code, info in results.items():
        by_code[code].update({
            "name": info.get("name_official") or by_code[code].get("name"),
            "title_jp": info.get("title_jp"),
            "kind": info.get("kind"),
            "rarity": info.get("rarity"),
            "color": info.get("color"),
            "ex": info.get("ex"),
            "cost": info.get("cost"),
            "limit": info.get("limit"),
            "ap": info.get("ap"),
            "dp": info.get("dp"),
            "sp": info.get("sp"),
            "dmg": info.get("dmg"),
            "type": info.get("type"),
            "leader": info.get("is_leader", False),
            "restriction": info.get("limit") or None,
            "series": info.get("series"),
            "illustrator": info.get("illustrator"),
            "release": info.get("releaseInfo"),
            "effect_jp": info.get("effect_jp"),
        })
    with open(FULL, "w", encoding="utf-8") as f:
        json.dump(list(by_code.values()), f, ensure_ascii=False)

    print(f"完成：成功 {ok}，失败 {fail}")
    print(f"输出：{FULL}")
    if fail and not ok:
        print("提示：全部失败说明还是连不上 —— 先开代理，或用 --proxy 指定端口。")


if __name__ == "__main__":
    main()
