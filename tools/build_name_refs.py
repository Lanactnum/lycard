#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""预计算「效果文本里引用的名字 → 卡号」，解决点效果里的卡名跳不过去的问题。

## 问题

效果文本里经常只写**角色名**，不写完整卡名：

    [诱发]这张角色登场时，将自己的弃牌堆中的1张“御坂美琴”加入手牌。

而卡名是「超电磁炮 御坂美琴」（副标题 + 空格 + 角色名）。
app 的 `_ensureNameIndex` 只按 `／` 拆分卡名登记片段，**没按空格拆**，
所以「御坂美琴」不在索引里 → 效果里这个名字点不动、不标蓝。

实测这类对不上的引用有 800+ 种，其中真正的卡名引用（排除放置区名、
作品名、特征片段）约 200 种。

## 做法

**构建时**扫全部效果文本，把引号里的名字逐个拿去匹配卡名（完整名、
日文原名、按 ／ 和空格拆出的片段），能匹配上的写进
`assets/data/name_refs.json`。运行时 app 启动时加载，把这些名字并进
名字索引 —— 匹配逻辑完全复用现有的，零新增代码路径。

只登记**在效果里真实出现过**的名字，所以不会凭空多出误标。

用法：python tools/build_name_refs.py
"""
import io
import json
import os
import re
import sys
import collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 引号类：中日文各种引号
QUOTE_RE = re.compile(r'[「“"『]([^」”"』]{2,40})[」”"』]')
# 「XX放置区/区域/置场」这类是效果指定的特殊区域名，不是卡名
ZONE_TAIL = re.compile(r'^\s*(放置区|放置场|区域|置场|下方|之下)')


def norm(s: str) -> str:
    return re.sub(r'\s+', '', s or '')


def to_simplified(s: str) -> str:
    """繁体/日文汉字 → 简体。

    效果文本里的引用常写日文汉字，而卡名是简体：
    「大藏**遊**星」（引用）vs「大藏**游**星」（卡名）→ 对不上。
    用 opencc 归一化后再比对；表里存的仍是**原文**（app 要按原文查）。
    """
    try:
        import opencc
        return _CC.convert(s)
    except Exception:
        return s


try:
    import opencc as _oc
    _CC = _oc.OpenCC('t2s')
except Exception:
    _CC = None


def close_quotes(t: str) -> str:
    """补全未闭合的引号。

    卡名本身可能带引号（`灵式机巧刀「折纸」`、`『意志』`），效果文本引用它
    时就变成嵌套引号 `「灵式机巧刀「折纸」」` —— 正则扫到第一个 `」` 就停，
    提取出半截 `灵式机巧刀「折纸`。补上缺失的闭合引号就能对上。
    """
    out = t
    for o, c in (('「', '」'), ('『', '』'), ('“', '”')):
        n = out.count(o) - out.count(c)
        if n > 0:
            out += c * n
    return out


def main():
    tr = json.load(io.open(os.path.join(ROOT, 'assets/data/translations_zh.json'),
                           encoding='utf-8'))
    cards = json.load(io.open(os.path.join(ROOT, 'assets/data/cards_app.json'),
                              encoding='utf-8'))
    cards = {c['code']: c for c in cards}

    # ① 建「名字 → 卡号集合」索引（完整名 + ／ 拆分 + 空格拆分）
    index = collections.defaultdict(set)

    def put(name: str, code: str):
        n = norm(name)
        if len(n) >= 2:
            index[n].add(code)
            s = to_simplified(n)
            if s != n:
                index[s].add(code)      # 归一化 key 也登记，供繁简不同的引用命中

    def lookup(t: str):
        """按原文 → 补全引号 → 繁简归一，逐级尝试。

        返回 (app 会扫出的片段, 卡号集合)。

        ⚠ 第一个返回值是**表要用的 key**，必须和 app 运行时扫出来的片段
        一致 —— app 的 `scanCardNames` 是「从文本某位置开始做最长匹配」，
        不受引号限制，所以嵌套引号那种它扫到的是**完整形式**
        （`灵式机巧刀「折纸」`），而不是引号提取截断的 `灵式机巧刀「折纸`。
        繁简归一的情况则相反：app 扫到的是**原文**（`大藏遊星`），
        所以 key 也用原文。
        """
        for cand in (t, to_simplified(t)):
            h = index.get(cand)
            if h:
                return t, h
        cq = close_quotes(t)
        for cand in (cq, to_simplified(cq)):
            h = index.get(cand)
            if h:
                return cq, h
        return None, None

    for code, c in cards.items():
        jp = c.get('name') or ''
        zh = (tr.get(code) or {}).get('name') or ''
        put(jp, code)
        put(zh, code)
        for part in re.split(r'[／/]', jp):
            put(part, code)
        for part in re.split(r'[／/]', zh):
            put(part, code)
        # ⚠ 关键：卡名是「副标题 角色名」格式，按空格拆出角色名。
        # 只取**最后一段**（角色名），不取副标题 —— 副标题太像普通短语，
        # 拿去索引会让效果文本里一堆普通词被标蓝。
        #
        # 但角色名**自己也可能带空格**：卡名「露娜大人的侍从 小仓 朝日」，
        # 效果引用写「小仓朝日」（去掉空格）。所以 parts[-1:] 和 parts[-2:]
        # 都要登记 —— 前者覆盖「沉睡的力量 御坂美琴」这种，后者覆盖
        # 「… 小仓 朝日」这种。再往前（parts[-3:]）会开始把副标题的尾字
        # 卷进来（「侍从小仓朝日」），所以到此为止。
        for src in (jp, zh):
            parts = [p for p in src.split(' ') if p]
            if len(parts) >= 2:
                put(parts[-1], code)
                put(''.join(parts[-2:]), code)

    # ② 扫效果文本里出现过的引用名，逐个匹配
    series_of = {c['code']: (c.get('series') or '') for c in cards.values()}
    out = {}
    unresolved = collections.Counter()

    for code, v in tr.items():
        if not isinstance(v, dict):
            continue
        e = v.get('effect') or ''
        for m in QUOTE_RE.finditer(e):
            raw = m.group(1)
            if ZONE_TAIL.match(e[m.end():m.end() + 4]):
                continue                       # 放置区名，跳过
            t = norm(raw)
            if len(t) < 2:
                continue
            key, hits = lookup(t)
            if hits:
                # 排序：同系列优先，然后按卡号（与 app 的 _seriesRank 口径一致）
                self_series = series_of.get(code, '')
                ordered = sorted(
                    hits,
                    key=lambda h: (0 if series_of.get(h) == self_series else 1, h),
                )
                out[key] = ordered
            else:
                unresolved[t] += 1

    # ③ 写出
    dst = os.path.join(ROOT, 'assets/data/name_refs.json')
    with io.open(dst, 'w', encoding='utf-8') as f:
        f.write(json.dumps(out, ensure_ascii=False, separators=(',', ':')))

    size = os.path.getsize(dst)
    print(f'引用名表：{len(out)} 个名字 → {dst}（{size / 1024:.1f} KB）')
    print()
    print('抽样：')
    for t in list(out)[:8]:
        print(f'  {t} → {out[t][:3]}{" ..." if len(out[t]) > 3 else ""}')
    print()
    print(f'仍对不上的引用名：{len(unresolved)} 种（多为放置区名/作品名/特征片段）')
    for t, n in unresolved.most_common(8):
        print(f'  {t[:30]:32s} ×{n}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
