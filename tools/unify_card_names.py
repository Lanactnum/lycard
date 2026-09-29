#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""找出「同一日文原名 → 多个中文译名」的卡，并给出统一建议。

问题：批量翻译分批次跑，同一张卡的不同版本（-A/-K/-S 变体）落在不同批次里，
职阶名、标点、简称/全名各自译法不同 —— 用户看到的是「同一张卡名字不一样」。
实测 9952 张里 89 组不一致。

用法：
  python tools/unify_card_names.py            # 只报告
  python tools/unify_card_names.py --write    # 写入（按下面的规则统一）
"""
import io
import json
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# FGO 职阶：国服官方用**英文**，所以这些统一成英文
CLASS_EN = {
    'セイバー': 'Saber', 'アーチャー': 'Archer', 'ランサー': 'Lancer',
    'ライダー': 'Rider', 'キャスター': 'Caster', 'アサシン': 'Assassin',
    'バーサーカー': 'Berserker', 'ルーラー': 'Ruler', 'シールダー': 'Shielder',
    'アヴェンジャー': 'Avenger', 'アルターエゴ': 'Alterego',
    'ムーンキャンサー': 'MoonCancer', 'フォーリナー': 'Foreigner',
    'プリテンダー': 'Pretender',
}
# 中文侧的职阶说法 → 英文。含 FGO 国服历史上出现过的几种译法
CLASS_ZH = {
    '剑士': 'Saber', '弓兵': 'Archer', '枪兵': 'Lancer', '骑兵': 'Rider',
    '魔术师': 'Caster', '术师': 'Caster', '术士': 'Caster', '法师': 'Caster',
    '暗杀者': 'Assassin', '暗匿者': 'Assassin', '刺客': 'Assassin',
    '狂战士': 'Berserker', '盾兵': 'Shielder', '裁定者': 'Ruler',
    '复仇者': 'Avenger', '降临者': 'Foreigner', '月之癌': 'MoonCancer',
    '丑阶': 'Alterego', '分灵': 'Alterego', '伪装者': 'Pretender',
}


def load(p):
    return json.load(io.open(os.path.join(ROOT, p), encoding='utf-8'))


def normalize_class(z: str) -> str:
    """把卡名里的职阶写法统一成英文。

    卡名有三种格式，都要处理：
      - `セイバー／アルトリア`              职阶在开头
      - `龙之魔女 复仇者／贞德〔Alter〕`       职阶在**中间**（副标题 + 空格 + 职阶／）
      - `未知への探求 キャスター`            职阶在结尾（副标题 + 空格 + 职阶）

    用正则一次覆盖：职阶必须出现在**开头、空格之后、或引号之后**，
    且后面紧跟 ／ 或结束。
    「开头或空格后」这个约束很关键 —— 否则「大魔术师」里的「魔术师」、
    「剑术师」里的「术师」都会被误伤。
    引号那一支是为了效果文本里的**卡名引用**：`将弃牌堆中的1张“剑士／罗摩”加入手牌`
    —— 引用的卡名也必须和卡名本身一致。
    """
    for src, en in {**CLASS_EN, **CLASS_ZH}.items():
        z = re.sub(
            r'(^|[\s"“”「」『』])' + re.escape(src) + r'(?=／|/|$)',
            lambda m: m.group(1) + en,
            z,
        )
    return z


def suggest(jp: str, variants: collections.Counter) -> str:
    """在多个译名里挑一个作为统一结果。

    规则（按优先级）：
      1. 职阶名统一成英文（FGO 国服口径）
      2. 全角连接符统一（＝/・ → ·）
      3. 含中文的优先于纯日文的（用户要的是中文）
      4. 出现次数多的优先（说明是主流译法）
      5. 同分时取更长的（信息更全，比如全名优于简称）
    """
    merged = collections.Counter()
    for z, n in variants.items():
        z2 = normalize_class(z)
        z2 = z2.replace('＝', '·').replace('・', '·')
        merged[z2] += n
    if len(merged) == 1:
        return next(iter(merged))

    han = re.compile(r'[\u4e00-\u9fff]')
    kana = re.compile(r'[\u3041-\u309f\u30a1-\u30fa\u30fc-\u30ff]')

    def score(item):
        z, n = item
        s = 2 if han.search(z) else 0
        if kana.search(z) and not han.search(z):
            s -= 2
        return (s, n, len(z))

    return max(merged.items(), key=score)[0]


def main():
    write = '--write' in sys.argv
    tr = load('assets/data/translations_zh.json')
    cards = {c['code']: c for c in load('assets/data/cards_app.json')}

    by_jp = collections.defaultdict(collections.Counter)
    for code, v in tr.items():
        if not isinstance(v, dict):
            continue
        jp = cards.get(code, {}).get('name') or ''
        zh = v.get('name') or ''
        if jp and zh:
            by_jp[jp][zh] += 1

    inc = {jp: c for jp, c in by_jp.items() if len(c) > 1}
    print(f'同一日文原名有多种译名：{len(inc)} 组')

    changes = 0
    detail = []
    for jp, variants in sorted(inc.items()):
        target = suggest(jp, variants)
        # 统计要改多少张
        n = sum(cnt for z, cnt in variants.items() if z != target)
        if n:
            changes += n
            detail.append((jp, dict(variants), target, n))

    print(f'需要改动的卡：{changes} 张')
    print()
    for jp, vs, target, n in detail:
        print(f'  {jp}')
        for z, cnt in sorted(vs.items(), key=lambda x: -x[1]):
            nz = normalize_class(z).replace('＝', '·').replace('・', '·')
            if nz == target:
                print(f'      {z}  ×{cnt}   ✅ 保留（统一后：{target}）')
            else:
                print(f'      {z}  ×{cnt}   → 改成「{target}」')

    if write and changes:
        # 反向索引：日文原名 → 统一后的中文
        target_of = {jp: t for jp, _vs, t, _n in detail}
        for code, v in tr.items():
            if not isinstance(v, dict):
                continue
            jp = cards.get(code, {}).get('name') or ''
            if jp in target_of:
                v['name'] = target_of[jp]
        print()
        print(f'✅ 同名不一致已统一（{changes} 张）')

    # ---- 全局职阶统一 ----
    # 上面只处理了「同一日文原名有多译名」的组。但职阶写法不统一是**全局**
    # 问题：`剑士／阿蒂拉` 如果只有这一种译法，就不在那 89 组里，却仍然
    # 该统一成 `Saber／阿蒂拉`（FGO 国服用英文职阶）。
    # 效果文本里引用卡名的地方（`将弃牌堆中的1张“剑士／罗摩”加入手牌`）
    # 也要一起改 —— 否则卡名改了、引用还留着旧写法，用户点引用会找不到卡。
    g_name = g_eff = 0
    for code, v in tr.items():
        if not isinstance(v, dict):
            continue
        z = v.get('name') or ''
        nz = normalize_class(z)
        if nz != z:
            g_name += 1
            if write:
                v['name'] = nz
        e = v.get('effect') or ''
        ne = normalize_class(e)
        if ne != e:
            g_eff += 1
            if write:
                v['effect'] = ne
    print(f'全局职阶统一：卡名 {g_name} 张 / 效果里的引用 {g_eff} 张'
          + ('（已写入）' if write and (g_name or g_eff) else ''))

    if write and (changes or g_name or g_eff):
        with io.open(os.path.join(ROOT, 'assets/data/translations_zh.json'),
                     'w', encoding='utf-8') as f:
            f.write(json.dumps(tr, ensure_ascii=False, separators=(', ', ': ')))
        print(f'✅ 共写入 {changes + g_name + g_eff} 处')
    return 0


if __name__ == '__main__':
    sys.exit(main())
