#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""检测官方站上「我们库里还没有」的新卡。

为什么要单独做一个工具
------------------------
`fetch_list.py` 是为「全量抓一遍」写的：它把列表页缓存到 `work/list_html/`，
**有缓存就直接读**（`if os.path.exists(f) ... return`）。拿它来检测新卡会永远
读到旧 HTML，看起来「没有新卡」——这是最容易误判的地方。

本工具的行为：
  · **不读缓存、不写缓存**（每次都取实时页面）
  · 从第 1 页往后顺，官方列表是**新卡在前**，所以只要连续 `--stop-after`
    页都没有新卡，就可以停（默认 3 页）
  · 只比卡号，不解析字段（快）；要补数据用 `tools/ingest_new_cards.py`

用法
----
    python tools/check_new_cards.py                 # 只看有没有新卡
    python tools/check_new_cards.py --json          # 顺便写 work/new_cards.json
    python tools/check_new_cards.py --stop-after 5  # 更保守（默认 3）
    python tools/check_new_cards.py --proxy none    # 直连（默认就是直连）

退出码
------
    0 = 没有新卡
    1 = 有新卡（方便挂 cron / CI 判断）
    2 = 抓取失败（网络/解析），**不代表没有新卡**
"""
import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CARDS = os.path.join(ROOT, "assets", "data", "cards_app.json")
OUT = os.path.join(ROOT, "work", "new_cards.json")
STATE = os.path.join(ROOT, "work", "new_cards_state.json")
# 检测时顺手把抓到的列表页存下来 —— 入库工具可以直接复用，
# 不用再向官网要同一批页面（官网一次只允许 ~17 个请求，省一次就是一整轮）
FRESH = os.path.join(ROOT, "work", "list_fresh")

LIST = "https://lycee-tcg.com/card/?page={page}"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

CTX = ssl.create_default_context()  # 官方站证书合法（实测 curl 不加 -k 也是 200），不做降级

# 卡号形态：LO-0001 / LO-0001A / LO-0001-S / LO-6960-A
CODE_RE = re.compile(r"\b(LO-\d{4}[A-Z]?(?:-[A-Z])?)\b")


def build_opener(proxy):
    handlers = [urllib.request.HTTPSHandler(context=CTX)]  # type: list
    if proxy and proxy.lower() not in ("none", "off", ""):
        handlers.insert(0, urllib.request.ProxyHandler({"http": proxy, "https": proxy}))
    else:
        handlers.insert(0, urllib.request.ProxyHandler({}))  # 强制直连
    return urllib.request.build_opener(*handlers)


def get(op, url, tries=2, timeout=20):
    """取一页。**走网络，不碰任何磁盘缓存。**

    超时故意压到 20 秒：官方站限流时单页可能一直挂着，
    45 秒 × 3 次 = 两分钟一页，整轮就像卡死。宁可快速失败重来。
    """
    last = None
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with op.open(req, timeout=timeout) as r:
                return r.read().decode("utf-8", "ignore"), None
        except Exception as e:  # noqa: BLE001
            last = e
            if i < tries - 1:
                time.sleep(2.0 * (i + 1))
    return None, str(last)


def parse_codes(html):
    """按文档顺序返回本页卡号（去重，保留顺序）。"""
    seen, out = set(), []
    for m in CODE_RE.finditer(html):
        c = m.group(1)
        if c not in seen:
            seen.add(c)
            out.append(c)
    return out


def parse_names(html):
    """卡号 -> 名字，用于让人看懂新卡是什么。"""
    names = {}
    for m in re.finditer(
            r'card_detail\.pl\?cardno=([A-Za-z0-9\-]+)"[^>]*>(.*?)</a>', html, re.S):
        code = m.group(1)
        raw = re.sub(r"<[^>]+>", "", m.group(2))
        raw = raw.replace("&nbsp;", " ").replace("&amp;", "&").strip()
        parts = [p.strip() for p in raw.split("\n") if p.strip()]
        names.setdefault(code, parts[-1] if parts else raw)
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stop-after", type=int, default=3,
                    help="连续多少页没有新卡就停（默认 3）")
    ap.add_argument("--max-pages", type=int, default=60,
                    help="最多翻多少页（安全上限，默认 60）")
    ap.add_argument("--delay", type=float, default=1.0, help="每页间隔秒数")
    ap.add_argument("--proxy", default="none",
                    help='代理地址；默认 none=直连（实测 2026-11 直连可通）')
    ap.add_argument("--budget", type=float, default=240,
                    help="整轮最多花多少秒（默认 240）；超了就带着已有结果收工，避免无限挂")
    ap.add_argument("--json", action="store_true", help="写 work/new_cards.json")
    ap.add_argument("--min-interval-hours", type=float, default=12,
                    help="距上次检查不足这么多小时就跳过（默认 12）。"
                         "官方站按 IP 限流，实测连跑几轮就会被握手超时封住。")
    ap.add_argument("--force", action="store_true", help="无视冷却期，立刻查")
    args = ap.parse_args()

    # ── 冷却期：官方站按 IP 限流，连续查会把自己封掉 ──
    state = {}
    if os.path.exists(STATE):
        try:
            state = json.load(open(STATE, encoding="utf-8"))
        except Exception:  # noqa: BLE001
            state = {}
    now = time.time()
    last = state.get("last_attempt_ts") or 0
    gap_h = (now - last) / 3600
    blocked_until = state.get("blocked_until_ts") or 0
    if not args.force:
        if now < blocked_until:
            print(f"站点上次把本机限流了，冷却到 "
                  f"{time.strftime('%H:%M', time.localtime(blocked_until))}；"
                  f"用 --force 可强行再试。")
            return 3
        if last and gap_h < args.min_interval_hours:
            print(f"距上次检查只有 {gap_h:.1f} 小时（要求 ≥ {args.min_interval_hours:g}），"
                  f"跳过。要立刻查加 --force。")
            return 3

    def save_state(**kw):
        state.update(kw)
        try:
            json.dump(state, open(STATE, "w", encoding="utf-8"),
                      ensure_ascii=False, indent=1)
        except Exception:  # noqa: BLE001
            pass

    save_state(last_attempt=time.strftime("%Y-%m-%dT%H:%M:%S"),
               last_attempt_ts=now)

    known = {c["code"] for c in json.load(open(CARDS, encoding="utf-8"))}
    print(f"库里 {len(known)} 张；开始翻官方列表（直连={args.proxy.lower() in ('none','off','')}）…")

    op = build_opener(args.proxy)
    new_codes = []
    names = {}
    known_streak = 0
    pages_done = 0
    last_new_page = 0
    failed = 0
    t0 = time.time()

    for page in range(1, args.max_pages + 1):
        if time.time() - t0 > args.budget:
            print(f"  ⏱ 已超预算 {args.budget:.0f}s，带着已有结果收工", flush=True)
            break
        html, err = get(op, LIST.format(page=page), timeout=20)
        if html is None:
            failed += 1
            print(f"  第 {page} 页抓取失败：{err}", flush=True)
            # 单页失败不直接判"没新卡"；连续失败太多才放弃
            if failed >= 3:
                until = time.time() + 30 * 60
                save_state(blocked_until=time.strftime("%Y-%m-%dT%H:%M:%S",
                                                       time.localtime(until)),
                           blocked_until_ts=until)
                print("  连续抓取失败（多半是被限流）。这**不代表**没有新卡；"
                      f"已记录冷却到 {time.strftime('%H:%M', time.localtime(until))}。",
                      file=sys.stderr)
                return 2
            time.sleep(args.delay * 2)
            continue
        failed = 0

        try:
            os.makedirs(FRESH, exist_ok=True)
            with open(os.path.join(FRESH, f"{page}.html"), "w", encoding="utf-8") as fh:
                fh.write(html)
        except Exception:  # noqa: BLE001
            pass

        codes = parse_codes(html)
        if not codes:
            print(f"  第 {page} 页解析不到卡号，视为列表到底", flush=True)
            break

        names.update(parse_names(html))
        fresh = [c for c in codes if c not in known]
        pages_done = page

        if fresh:
            known_streak = 0
            last_new_page = page
            new_codes.extend(fresh)
            print(f"  第 {page} 页：{len(codes)} 张，其中**新卡 {len(fresh)} 张** "
                  f"（{time.time()-t0:.0f}s）", flush=True)
        else:
            known_streak += 1
            print(f"  第 {page} 页：{len(codes)} 张，全是已知卡 "
                  f"（连续 {known_streak}/{args.stop_after}）", flush=True)
            if known_streak >= args.stop_after:
                print(f"  连续 {args.stop_after} 页没有新卡 → 停", flush=True)
                break

        time.sleep(args.delay)

    # ⚠️ 一页都没读到 = 检测失败，**绝不能**报「没有新卡」。
    # 假阴性的代价是：用户以为是最新，实际漏了一整个卡包。
    if pages_done == 0:
        until = time.time() + 30 * 60
        save_state(blocked_until=time.strftime("%Y-%m-%dT%H:%M:%S",
                                               time.localtime(until)),
                   blocked_until_ts=until)
        print()
        print("=" * 60, file=sys.stderr)
        print("检测失败：一页都没能读到。这**不代表**没有新卡。", file=sys.stderr)
        print(f"已记录冷却到 {time.strftime('%H:%M', time.localtime(until))}，"
              f"到点再试。", file=sys.stderr)
        return 2

    # 只有真读到过页面，才记「上次成功」
    save_state(last_success=time.strftime("%Y-%m-%dT%H:%M:%S"),
               last_success_ts=time.time(), last_count=len(new_codes),
               blocked_until=None, blocked_until_ts=0,
               pages_scanned=pages_done)

    # 去重：官网同一张卡可能出现在列表的多个位置（实测 358 条里有 90 个重复），
    # 不去重会把「新卡数」虚报一大截。保持出现顺序（最新的在前）。
    _seen = set()
    new_codes = [c for c in new_codes if not (c in _seen or _seen.add(c))]

    print()
    print("=" * 60)
    if not new_codes:
        print(f"没有新卡（翻了 {pages_done} 页，{time.time()-t0:.0f}s）")
        return 0

    print(f"发现 **{len(new_codes)} 张新卡**（翻了 {pages_done} 页，{time.time()-t0:.0f}s）")
    print("=" * 60)
    for c in new_codes:
        print(f"  {c:14s} {names.get(c, '')}")
    print()
    print(f"  最早一张：{new_codes[-1]}   最新一张：{new_codes[0]}")

    if args.json:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        payload = {
            "detected_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "count": len(new_codes),
            "pages_scanned": pages_done,
            "last_new_page": last_new_page,
            "codes": new_codes,
            "names": {c: names.get(c, "") for c in new_codes},
        }
        with open(OUT, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        print(f"  已写 {OUT}")

    return 1


if __name__ == "__main__":
    sys.exit(main())
