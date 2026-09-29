#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""标出「同一张卡，中文圈有的音译、有的留原名」的全部位置。

## 问题

外来语卡名（武器名、怪物名、人名）在中文圈没有统一口径：
  - 有的译成音译：`カラドボルグ` → 卡拉德波格
  - 有的直接用原名：`カラドボルグ` → カラドボルグ

同一个角色/武器在不同卡上（不同副标题）落在不同翻译批次里，就会出现
**这张卡叫「木叶咲耶」、那张卡还叫「コノハサクヤ」**。

## 判定方法（按名字分段，不用子串）

第一版用「假名词是不是出现在别的日文原名里」判定，误报严重 ——
`ニコラ・ケフェウス` 会匹配到 `ニコラ・テスラ`（都含 `ニコラ`），
`クロノ・クロック` 会匹配到「死灵之书」（毫无关系）。

改成**分段精确匹配**：

1. 把卡名按 `／` `/` 空格切成段（`Vanish コノハサクヤ` → `Vanish`, `コノハサクヤ`）
2. 对「译名里没有中文」的卡，取它含假名的**完整段**（不是子串）
3. 找其它卡：**同一个段**出现在它的日文原名里（也按段匹配），
   而它的中文译名**已经译了**（含中文字、且不等于日文原名）
4. 那些卡就是证据：同一个词，别处译了、这里没译

用法：
  python tools/check_name_mixing.py
  python tools/check_name_mixing.py --md <输出路径>
"""
import io
import json
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HAN = re.compile(r'[\u4e00-\u9fff]')
KANA = re.compile(r'[\u3041-\u309f\u30a1-\u30fa\u30fc-\u30ff]')
SPLIT = re.compile(r'[／/\s　]+')


def load(p):
    return json.load(io.open(os.path.join(ROOT, p), encoding='utf-8'))


def segments(name: str):
    return [s for s in SPLIT.split(name or '') if s]


# 作品名里表示会社的括号标记，如 `神姫PROJECT 1.0(KHP)` → KHP
BRAND_TAG = re.compile(r'\(([A-Z][A-Za-z ]{1,8})\)\s*$')


def work_ids(series: str):
    """取作品名的多个标识，任一相同即视为同作品。

    ⚠ 不能只取一个标识：数据里同一个会社写法不一致 ——
    `オーガスト 1.0`（无括号）和 `オーガスト 2.0(AUG)`（有括号），
    只取括号标记的话前者是 `オーガスト`、后者是 `AUG`，判成两部作品，
    于是「ベアトリーチェ」这种真混用会被漏掉。
    所以括号标记和「去掉版本号的名字」**都**收集起来做交集比对。
    """
    s = series or ''
    ids = set()
    m = BRAND_TAG.search(s)
    if m:
        ids.add(m.group(1).strip())
    base = re.sub(r'\s*[\d.]+.*$', '', s).strip()
    if base:
        ids.add(base)
    return ids


def same_work(a: str, b: str) -> bool:
    """两个作品是不是同一部（或至少同一会社）。

    ⚠ 这条约束不能省：同一个片假名在不同作品里往往是**不同角色**
    （`エデン` 在 ぱれっと 和 千年戦争アイギス 是两个人），
    只看名字会把「别处的伊甸」当成证据。
    """
    if not a or not b:
        return False
    if a == b:
        return True
    return bool(work_ids(a) & work_ids(b))


def my_series_of(codes, cards):
    out = set()
    for c in codes:
        v = cards[c].get('series') or ''
        if v:
            out.add(v)
    return out


def main():
    tr = load('assets/data/translations_zh.json')
    cards = {c['code']: c for c in load('assets/data/cards_app.json')}

    jp_of = {c: (cards[c].get('name') or '') for c in cards}
    zh_of = {c: ((tr.get(c) or {}).get('name') or '') for c in cards}

    # ① 译名里没有中文的卡 = 留了原名
    raw_codes = [c for c in cards
                 if zh_of[c] and not HAN.search(zh_of[c])]
    by_name = collections.defaultdict(list)
    for c in raw_codes:
        by_name[zh_of[c]].append(c)
    print(f'① 译名里没有中文的卡：{len(raw_codes)} 张'
          f'（去重 {len(by_name)} 个名字）')

    # ② 建「段 → 卡号」索引（只登记含假名的段，且该段在日文原名里是完整段）
    seg_index = collections.defaultdict(set)
    for c, jp in jp_of.items():
        for s in segments(jp):
            if KANA.search(s) and len(s) >= 3:
                seg_index[s].add(c)

    # ③ 逐条找证据
    mixed = []
    pure = []
    for name, codes in by_name.items():
        ev = []          # (段, 证据卡号, 它的中文译名, 它的作品)
        # 这些卡自己的作品集合（同名卡可能跨作品，任一命中即可）
        my_series = {jp_of[c] and (cards[c].get('series') or '') for c in codes}
        my_series.discard('')
        for s in segments(name):
            if not KANA.search(s) or len(s) < 3:
                continue
            for c2 in seg_index.get(s, ()):
                if c2 in codes:
                    continue
                z2 = zh_of[c2]
                # 证据卡的四个条件：
                #   ① 中文译名已译（含中文字）
                #   ② 不是原样照抄日文
                #   ③ **这个段本身在中文译名里已经消失** ——
                #      否则「绝体绝命致命伤终结 バールのようなもの」这种
                #      （只译了副标题、术语照留）会被当成「已译」的假证据。
                #   ④ **和留原名的卡同作品/同会社** —— 否则同名不同角色
                #      （`エデン` 在 ぱれっと 和 千年戦争アイギス 是两个人）
                #      会被误当证据。
                s2 = cards[c2].get('series') or ''
                if (z2 and HAN.search(z2) and z2 != jp_of[c2]
                        and s not in z2
                        and any(same_work(s2, ms) for ms in my_series)):
                    ev.append((s, c2, z2, s2))
        if ev:
            mixed.append((name, codes, ev))
        else:
            pure.append((name, codes))

    print(f'② 中文圈在别处有译法、这里却留原名的：{len(mixed)} 个名字')
    print(f'③ 全库都只用原名的：{len(pure)} 个名字')
    print()
    print('=' * 104)
    print('【混用清单】同一个词，别处译了、这里留原名')
    print('=' * 104)

    for name, codes, ev in sorted(mixed, key=lambda x: -len(x[1])):
        by_seg = collections.defaultdict(list)
        for s, c2, z2, s2 in ev:
            by_seg[s].append((c2, z2, s2))
        print(f'\n  ▸ {name}')
        print(f'     留原名的卡（{len(codes)} 张）：{", ".join(codes[:5])}'
              f'{"…" if len(codes) > 5 else ""}')
        print(f'     作品：{", ".join(sorted(my_series_of(codes, cards)))}')
        for s, lst in by_seg.items():
            print(f'     段「{s}」在同作品里已译：')
            seen = set()
            for c2, z2, s2 in lst:
                if z2 in seen:
                    continue
                seen.add(z2)
                print(f'         {c2} → {z2}   [{s2}]')
                if len(seen) >= 3:
                    break

    print()
    print('=' * 104)
    print('【只用原名】全库找不到任何已译写法')
    print('=' * 104)
    for name, codes in sorted(pure):
        print(f'  {name}   （{len(codes)} 张）')

    if '--md' in sys.argv:
        p = sys.argv[sys.argv.index('--md') + 1]
        L = ['# 卡名「音译 / 原名」混用清单', '',
             f'- 译名里没有中文的卡：**{len(raw_codes)} 张**（{len(by_name)} 个名字）',
             f'- 其中「中文圈别处已译、这里留原名」：**{len(mixed)} 个名字**',
             f'- 全库都只用原名：**{len(pure)} 个名字**', '',
             '> 判定：按名字分段精确匹配（不用子串），证据是「同一个段在别的卡上已被译成中文」。',
             '', '---', '', '## 一、混用清单（别处译了、这里没译）', '']
        for name, codes, ev in sorted(mixed, key=lambda x: -len(x[1])):
            L.append(f'### {name}')
            L.append('')
            L.append(f'**留原名的卡**（{len(codes)} 张）：`{", ".join(codes)}`')
            L.append('')
            by_seg = collections.defaultdict(list)
            for s, c2, z2, s2 in ev:
                by_seg[s].append((c2, z2, s2))
            L.append(f'作品：{", ".join(sorted(my_series_of(codes, cards)))}')
            L.append('')
            for s, lst in by_seg.items():
                L.append(f'- 段「{s}」在同作品里已译：')
                seen = set()
                for c2, z2, s2 in lst:
                    if z2 in seen:
                        continue
                    seen.add(z2)
                    L.append(f'  - `{c2}` → {z2}')
            L.append('')
        L += ['---', '', '## 二、全库只用原名（无从判断该音译成什么）', '']
        for name, codes in sorted(pure):
            L.append(f'- {name}（{len(codes)} 张：`{", ".join(codes[:4])}`）')
        io.open(p, 'w', encoding='utf-8').write('\n'.join(L) + '\n')
        print()
        print(f'✅ 已存 {p}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
