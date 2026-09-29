#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""判定卡数据效果文本里的假名，到底是「该保留的专有名词」还是「漏译」。

背景：效果文本里 2000+ 处假名，绝大多数是**作品名/会社名**（构筑限制里会写
『うたわれるもの ロストフラグ』这类），这些必须保留原文。但直接用「是否在
引号内」判定不可靠 —— 构筑限制写成 `构筑限制:[雪]或『WHITE ALBUM シリーズ』`，
书名号离假名很远，窗口法抓不到。

正确做法：**拿 series 字段当白名单**。卡数据里每张卡都有 series（作品名），
把这些作品名里的假名片段全收集起来，效果文本里的假名如果在白名单里，就是
专有名词；不在的才可疑。

用法：python tools/check_kana.py
"""
import json
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KANA = re.compile(r'[\u3041-\u309f\u30a1-\u30fa\u30fc-\u30ff]+')


def load(p):
    return json.load(open(os.path.join(ROOT, p), encoding='utf-8'))


def main():
    tr = load('assets/data/translations_zh.json')
    cards = {c['code']: c for c in load('assets/data/cards_app.json')}

    # ① 白名单：所有 series（作品名）+ 会社名里出现过的假名片段
    white = set()
    for c in cards.values():
        for f in ('series', 'title_jp', 'brand'):
            v = c.get(f) or ''
            for m in KANA.finditer(v):
                white.add(m.group(0))
    # 卡名（原名）里的假名也是专有名词
    for c in cards.values():
        for m in KANA.finditer(c.get('name') or ''):
            white.add(m.group(0))
    # 卡名（译名）里保留的假名同样算
    for v in tr.values():
        if isinstance(v, dict):
            for m in KANA.finditer(v.get('name') or ''):
                white.add(m.group(0))

    print(f'白名单（作品名/会社名/卡名里的假名片段）：{len(white)} 个')
    print()

    # ② 扫效果文本，白名单外的才可疑
    suspect = collections.Counter()
    ctx = {}
    total = 0
    for code, v in tr.items():
        if not isinstance(v, dict):
            continue
        s = v.get('effect') or ''
        for m in KANA.finditer(s):
            total += 1
            w = m.group(0)
            if w in white:
                continue
            suspect[w] += 1
            ctx.setdefault(w, (code, s[max(0, m.start() - 40):m.end() + 30]))

    print(f'效果文本里的假名总出现：{total} 处')
    print(f'白名单外（可疑）：{sum(suspect.values())} 处 / {len(suspect)} 种')
    print()
    if suspect:
        for w, n in suspect.most_common(40):
            code, c = ctx[w]
            print(f'  {w[:34]:36s} ×{n:4d}  ({code}) …{c[-60:]}…')
    else:
        print('  ✅ 没有可疑的假名残留')

    # ③ 顺便：译文里仍是纯日文的卡名
    print()
    print('=' * 70)
    print('译文里仍是纯日文的卡名（没有中文）')
    print('=' * 70)
    han = re.compile(r'[\u4e00-\u9fff]')
    pure = [(c, (v.get('name') or '')) for c, v in tr.items()
            if isinstance(v, dict)
            and KANA.search(v.get('name') or '')
            and not han.search(v.get('name') or '')]
    print(f'  {len(pure)} 张 / {len(tr)}')
    # 按作品归类
    by_series = collections.Counter()
    for c, _n in pure:
        by_series[cards.get(c, {}).get('series', '?')] += 1
    for s, n in by_series.most_common(10):
        print(f'    {n:4d}  {s}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
