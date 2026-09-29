#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""全面体检：找出所有还没译干净的日文、术语不一致、以及误伤。

比 align_terms.py 的扫描更宽：
  1. 卡数据里**所有**假名残留（不只方括号）—— 分「该译的」和「专有名词」
  2. 卡名里的假名（可能是漏译的卡名）
  3. 教程 / 词条表 / 界面文案里的假名
  4. 旧术语（本轮已淘汰的说法）残留
  5. 误伤检查（卡名、普通用语）
  6. 各文件之间术语是否一致

用法：python tools/full_check.py
"""
import io
import json
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KANA = re.compile(r'[\u3040-\u309f\u30a0-\u30ffー]')

# 本轮已淘汰的旧术语
OLD_TERMS = ['激进', '步进', '侧步', '指令步', '指令切换', '跳跃', '辅助',
             '交战', '恢复', '毅力', '主角', '回合恢复', '杀手锏']

# 误伤检查：这些必须还在
MUST_KEEP = ['谜之女主角X', '时间跳跃', '恢复为未行动', '护盾+', '切札']


def load(p):
    return io.open(os.path.join(ROOT, p), encoding='utf-8').read()


def main():
    problems = []
    print('=' * 78)
    print('① 卡数据：假名残留总览')
    print('=' * 78)
    tr = json.loads(load('assets/data/translations_zh.json'))
    eff = {c: (v.get('effect') or '') for c, v in tr.items() if isinstance(v, dict)}
    names = {c: (v.get('name') or '') for c, v in tr.items() if isinstance(v, dict)}

    # 效果文本里的假名，按片段归类
    c1 = collections.Counter()
    ctx1 = {}
    for code, s in eff.items():
        for m in re.finditer(r'[\u30a0-\u30ffー]{2,}', s):
            w = m.group(0)
            c1[w] += 1
            ctx1.setdefault(w, (code, s[max(0, m.start() - 35):m.end() + 25]))
        for m in re.finditer(r'[\u3040-\u309f]{2,}', s):
            w = m.group(0)
            c1['(平)' + w] += 1
            ctx1.setdefault('(平)' + w, (code, s[max(0, m.start() - 35):m.end() + 25]))

    # 方括号内的假名 = 一定是没译的标记
    bracket = collections.Counter()
    for code, s in eff.items():
        for m in re.finditer(r'[\[［]([^\]］]{1,40})[\]］]', s):
            if KANA.search(m.group(1)):
                bracket[m.group(1).split(':')[0].split('：')[0]] += 1
    print(f'  效果文本里的假名片段：{len(c1)} 种 / {sum(c1.values())} 处')
    print(f'  其中**方括号内**（必为漏译）：{len(bracket)} 种 / {sum(bracket.values())} 处')
    for w, n in bracket.most_common(15):
        code, ctx = ctx1.get(w, ('', ''))
        print(f'    [{w[:40]}] ×{n}')
    if not bracket:
        print('    ✅ 方括号内已无假名')

    print()
    print('=' * 78)
    print('② 卡名里的假名（可能是漏译的卡名）')
    print('=' * 78)
    kana_names = {c: n for c, n in names.items() if KANA.search(n)}
    print(f'  含假名的卡名：{len(kana_names)} / {len(names)}')
    # 分类：纯日文名 vs 含中文的混合
    pure = {c: n for c, n in kana_names.items() if not re.search(r'[\u4e00-\u9fff]', n)}
    mixed = {c: n for c, n in kana_names.items() if re.search(r'[\u4e00-\u9fff]', n)}
    print(f'    纯日文/假名卡名：{len(pure)} 张')
    for c, n in list(pure.items())[:8]:
        print(f'      {c}: {n}')
    print(f'    中英混排：{len(mixed)} 张')
    for c, n in list(mixed.items())[:5]:
        print(f'      {c}: {n}')

    print()
    print('=' * 78)
    print('③ 教程 / 词条表 / 界面文案的假名')
    print('=' * 78)
    tut = load('assets/data/tutorial.json')
    n = len(KANA.findall(tut))
    print(f'  教程：{n} 处假名' + ('  ✅' if n == 0 else '  ← 要清'))
    if n:
        problems.append('教程里有假名')

    kw = json.loads(load('assets/data/keywords.json'))
    bad_kw = []
    for x in kw:
        for f in ('zh', 'cond', 'desc'):
            v = x.get(f) or ''
            if KANA.search(v):
                bad_kw.append((x.get('jp'), f, v[:60]))
    print(f'  词条表中文侧：{len(bad_kw)} 处' + ('  ✅' if not bad_kw else ''))
    for jp, f, v in bad_kw[:5]:
        print(f'      [{jp}] {f}: {v}')

    ui_kana = []
    for base, _d, fs in os.walk(os.path.join(ROOT, 'lib')):
        for fn in fs:
            if not fn.endswith('.dart'):
                continue
            p = os.path.join(base, fn)
            rel = os.path.relpath(p, ROOT).replace('\\', '/')
            for i, line in enumerate(io.open(p, encoding='utf-8'), 1):
                for m in re.finditer(r"tr\('([^']*)'", line):
                    if KANA.search(m.group(1)):
                        ui_kana.append((rel, i, m.group(1)[:60]))
    print(f'  界面文案 tr() 里：{len(ui_kana)} 处')
    for rel, i, s in ui_kana[:8]:
        print(f'      {rel}:{i}  {s}')

    print()
    print('=' * 78)
    print('④ 旧术语残留')
    print('=' * 78)
    allblob = tut + load('assets/data/keywords.json') + load('assets/data/translations_zh.json')
    for w in OLD_TERMS:
        br = len(re.findall(r'[\[［]' + re.escape(w), allblob))
        tot = len(re.findall(re.escape(w), allblob))
        if br:
            problems.append(f'卡数据里还有旧标记 [{w}')
            print(f'  [{w}: {br}  ← 残留!')
        elif tot:
            print(f'  {w}: 方括号 0 ✅（裸词 {tot} 处，需人工确认是否专有名词）')
    print('  ✅ 无旧标记残留' if not any(re.findall(r'[\[［]' + re.escape(w), allblob)
                                     for w in OLD_TERMS) else '')

    print()
    print('=' * 78)
    print('⑤ 误伤检查')
    print('=' * 78)
    for w in MUST_KEEP:
        n = allblob.count(w)
        ok = n > 0
        print(f'  {w}: {n}' + ('  ✅' if ok else '  ← 被误改了!'))
        if not ok:
            problems.append(f'误伤：{w} 没了')

    print()
    print('=' * 78)
    print('⑥ 术语一致性（教程 / 词条表 是否都用新口径）')
    print('=' * 78)
    kwmap = {}
    for x in kw:
        if x.get('zh'):
            kwmap[x['jp']] = x['zh']
    new_terms = ['进取心', '移动', '横移', '竖移', '列交换', '跳', '援助',
                 '迎战', '重振', '再起', '主演', '回合补正']
    for t in new_terms:
        in_tut = tut.count(t)
        in_kw = sum(1 for v in kwmap.values() if v == t)
        print(f'  {t:8s} 教程×{in_tut:3d}  词条表×{in_kw}')

    print()
    print('=' * 78)
    print('结论')
    print('=' * 78)
    if problems:
        for p in problems:
            print(f'  ✗ {p}')
    else:
        print('  ✅ 未发现遗留问题')
    return 0


if __name__ == '__main__':
    sys.exit(main())
