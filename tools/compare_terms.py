#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把本 App 的术语译法和中文社区公认译法做对照。

三个社区来源（都是玩家实际在用的）：

  A. 魔都群《Lycee overture 中文版规则》（2019，萌卡社转载）
     https://moetcg.club/Public/upload/file/20190910/1568109452613117.pdf
  B. 萌卡社 Flagalac《基本能力及字段说明》（2019）
     https://moetcg.club/news/detail/aid/19.html
  C. 《LO 规则妙妙小解》（lycee-toolbox.top）
     https://lycee-toolbox.top/assets/lo-rules.pdf

⚠ 这些来源只用于**核对术语**，不把原文写进 App（用户要求 App 内不含萌卡社原文）。

用法：python tools/compare_terms.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 日文 → (魔都群, 萌卡社, 妙妙小解)   '—' = 该来源没提
REF = {
    'アグレッシブ':   ('进取心', '进取心', '进取心'),
    'ステップ':       ('移动', '移动', '移动'),
    'サイドステップ': ('侧移', '横移', '横向侧移'),
    'オーダーステップ': ('纵移', '竖移', '纵向移动'),
    'オーダーチェンジ': ('—', '列交换', '位置交换'),
    'ジャンプ':       ('—', '跳', '跳跃'),
    'ペナルティ':     ('—', '惩罚', '离场惩罚'),
    'アシスト':       ('—', '援助', '辅助'),
    'エンゲージ':     ('—', '迎战', '结合'),
    'リカバリー':     ('—', '重振', '补正'),
    'ガッツ':         ('—', '再起', '斗志'),
    'ボーナス':       ('—', '奖励', '奖励'),
    'チャージ':       ('—', '充能', '充能'),
    'サポーター':     ('—', '支援者', '支援者'),
    'リーダー':       ('—', '领导者', '领导'),
    'ターンリカバリー': ('—', '—', '回合补正'),
    'プリンシパル':   ('—', '—', '主演'),
    'サプライズ':     ('—', '—', '突袭'),
    '切札':          ('—', '必杀', '—'),
    '手札宣言':       ('—', '手牌宣言', '—'),
}

# 本 App 现在的译法（keywords.json + translations_zh.json 的口径）
MINE = {
    'アグレッシブ': '激进',
    'ステップ': '步进',
    'サイドステップ': '侧步',
    'オーダーステップ': '指令步',
    'オーダーチェンジ': '指令切换',
    'ジャンプ': '跳跃',
    'ペナルティ': '惩罚',
    'アシスト': '辅助',
    'エンゲージ': '交战',
    'リカバリー': '恢复',
    'ガッツ': '毅力',
    'ボーナス': '奖励',
    'チャージ': '充能',
    'サポーター': '支援者',
    'リーダー': '领导者',
    'ターンリカバリー': '回合恢复',
    'プリンシパル': '主角',
    'サプライズ': '突袭',
    '切札': '切札',
    '手札宣言': '手牌宣言',
}


def count_tag(blob: str, zh: str) -> int:
    """方括号里的能力标记出现次数"""
    return len(re.findall(r'[\[［]' + re.escape(zh), blob))


def main():
    p = os.path.join(ROOT, 'assets', 'data', 'translations_zh.json')
    blob = open(p, encoding='utf-8').read()

    print('=' * 96)
    print('日文'.ljust(20), '本App'.ljust(10), '魔都群'.ljust(8), '萌卡社'.ljust(8),
          '妙妙小解'.ljust(10), '结论')
    print('=' * 96)
    unanimous, conflict, same = [], [], []
    for jp, (a, b, c) in REF.items():
        mine = MINE.get(jp, '?')
        votes = [x for x in (a, b, c) if x != '—']
        if not votes:
            verdict = '（社区无译法）'
        elif all(v == mine for v in votes):
            verdict = '✅ 一致'
            same.append(jp)
        elif len(set(votes)) == 1 and votes[0] != mine:
            verdict = f'⚠ 社区一致作「{votes[0]}」'
            unanimous.append((jp, mine, votes[0]))
        else:
            verdict = '△ 社区自己也不统一'
            conflict.append((jp, mine, votes))
        print(jp.ljust(20), mine.ljust(10), a.ljust(8), b.ljust(8), c.ljust(10), verdict)

    print()
    print('【社区一致、但和本 App 不同】—— 建议改')
    for jp, mine, ref in unanimous:
        n = count_tag(blob, mine)
        print(f'  {jp:16s} {mine} → {ref:8s}  （卡数据里 [{mine}] 出现 {n} 次）')

    print()
    print('【社区自己就不统一】—— 需要你定')
    for jp, mine, votes in conflict:
        n = count_tag(blob, mine)
        print(f'  {jp:16s} 本App={mine:8s} 社区各说各的: {"/".join(votes)}  （[{mine}] {n} 次）')

    print()
    print(f'一致 {len(same)} 项 / 社区一致但与App不同 {len(unanimous)} 项 / 社区内部分歧 {len(conflict)} 项')

    # 顺手核对之前改过的两处（EX / SP）在社区来源里的说法
    print()
    print('【顺带核对】之前修正过的两处：')
    print('  EX  = 当作费用弃掉时能支付的费用量  ← 魔都群原文：「这个角色从手卡废弃时能够支付的费用量」✅')
    print('  SP  = 支援力                        ← 魔都群原文：「角色的支援力」✅')
    print('  即：EX 不是稀有度、SP 不是先手权，两处修正与社区口径一致。')
    return 0


if __name__ == '__main__':
    sys.exit(main())
