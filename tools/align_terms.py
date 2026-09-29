#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把教程 / 规则页 / 词条表 / 卡数据的术语统一到中文社区口径。

## 口径来源

按用户 2026-09-20 的决定：**采用萌卡社（Flagalac《基本能力及字段说明》）
的用词**；萌卡社没收录的少数词，用《LO 规则妙妙小解》补。

三个社区来源（玩家实际在用）：
  A. 魔都群《Lycee overture 中文版规则》（2019，萌卡社转载）
  B. 萌卡社 Flagalac《基本能力及字段说明》（2019）        ← 本次采用
  C. 《LO 规则妙妙小解》（lycee-toolbox.top）

对照表见 `D:\\Big Fat Fish\\笔记\\lycee术语对照\\术语对照表.md`，
对照脚本 `tools/compare_terms.py`。

## 两条必须小心的边界（都实测踩过）

1. **`主角` 的裸词是卡名**：「谜之女主角X」这类卡名里含「主角」，
   直接全局替换会把卡名改坏。所以卡数据里**只替换方括号形态** `[主角`。
2. **`步进` 的裸词藏在 `指令步进` 里**：`[指令步进:[0]]` 是
   `オーダーステップ` 的另一种译法，所以 `指令步进` 必须排在 `步进` 之前替换，
   否则会变成「指令移动」。

同理 **`恢复` 的裸词 997 处是普通用语**（「恢复为未行动」），
绝不能动 —— 卡数据里只替换 `[恢复`。

## 用户指定保留

「切札」保留原词（社区叫「必杀」），不采纳社区译法。

用法：python tools/align_terms.py [--write]
不加 --write 只报告差异。
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ============ ① 我自己的文案（教程 / 规则页 / 词条表）：可以整词替换 ============
RULES_AUTHORED = [
    # 长词排前面
    (r"回合恢复", "回合补正"),
    (r"指令步进", "竖移"),
    (r"指令步", "竖移"),
    (r"指令切换", "列交换"),
    (r"侧步", "横移"),
    (r"步进", "移动"),
    (r"激进", "进取心"),
    (r"交战", "迎战"),
    (r"毅力", "再起"),
    (r"辅助", "援助"),
    (r"跳跃", "跳"),
    (r"主角", "主演"),
    (r"恢复", "重振"),
    # 日语残留
    (r"行动済み", "已行动"),
    (r"行动済", "已行动"),
    (r"ダウン", "被击倒"),
    (r"サポート", "支援"),
    # 与卡数据口径不一致
    (r"攻击性", "进取心"),
    # 用户指定保留原词
    (r"杀手锏", "切札"),
    # 护盾（负向环视，避免「护盾置场」→「护护盾置场」）
    (r"(?<!护)盾置场", "护盾置场"),
    (r"(?<!护)盾＋", "护盾＋"),
    (r"(?<!护)盾\+", "护盾+"),
    (r"回合进行中玩家", "当前回合玩家"),
]

# ============ ② 卡数据：只替换方括号标记 + 已核对的散文引用 ============
RULES_CARD = [
    # 方括号标记（长词优先）
    (r"[\[［]回合恢复", "[回合补正"),
    (r"[\[［]指令步进", "[竖移"),
    (r"[\[［]指令步", "[竖移"),
    (r"[\[［]指令切换", "[列交换"),
    (r"[\[［]恢复", "[重振"),
    (r"[\[［]步进", "[移动"),
    (r"[\[［]侧步", "[横移"),
    (r"[\[［]跳跃", "[跳"),
    (r"[\[［]交战", "[迎战"),
    (r"[\[［]辅助", "[援助"),
    (r"[\[［]毅力", "[再起"),
    (r"[\[［]主角", "[主演"),      # ⚠ 只改方括号，卡名「谜之女主角X」不能动
    (r"[\[［]激进", "[进取心"),
    # 散文里对「交战」这个能力的引用（128 处，都是「因交战登场」「以交战登场以外」）
    (r"交战登场", "迎战登场"),
    # 之前几轮修的
    (r"杀手锏", "切札"),
    (r"因ダウン以外", "因被击倒以外"),
    (r"(?<!护)盾\+", "护盾+"),
    (r"[\[［]ターンリカバリー", "[回合补正"),
    (r"[\[［]リカバリー", "[重振"),
    (r"[\[［]プリンシパル", "[主演"),
    (r"[\[［]サプライズ", "[突袭"),
    (r"[\[［]ペナルティ", "[惩罚"),
    (r"[\[［]ボーナス", "[奖励"),
    (r"[\[［]ガッツ", "[再起"),
    (r"[\[［]コンバート", "[转换"),
    (r"[\[［]オーダーチェンジ", "[列交换"),
    (r"[\[［]リーダー", "[领导者"),
    (r"[\[［]コスト", "[费用"),
]

TARGETS = {
    "assets/data/tutorial.json": RULES_AUTHORED,
    "assets/data/keywords.json": RULES_AUTHORED,
    "assets/data/translations_zh.json": RULES_CARD,
    "lib/pages/rules_page.dart": RULES_AUTHORED,
    "lib/pages/tutorial_page.dart": RULES_AUTHORED,
}


def count_hits(s, rules):
    return sum(len(re.findall(pat, s)) for pat, _ in rules)


def apply_rules(s, rules):
    for pat, rep in rules:
        s = re.sub(pat, rep, s)
    return s


def fix_card_fields(path, write=True):
    """卡数据里需要**按字段**处理的问题。

    有些字只能改 effect、不能改 name：
      - `無`：效果文本里是费用/属性标记（`[無無無]`），简体应作「无」，
        实测 496 处，而同一批数据里另有 1080 处写作「无」—— 19 张卡里
        两种写法同时出现，用户看到的就是「同一张卡里不一致」。
        但**卡名里**的「水無月」是日本人名（13 处），必须保留。
      - 日文汉字「見/結/間/護/場/勝/條/來/過/種」等：全都在卡名的书名号
        引用里（「氷見山 玲」「黒姫 結灯」），同样保留。

    ⚠ 写回必须保持**原文件的单行紧凑格式** —— 原文件是
    `json.dumps(..., ensure_ascii=False, separators=(', ', ': '))` 一行到底
    （1.6MB / 0 个换行）。用 `indent=N` 会把它撑成几万行、体积也变。

    返回改动的处数。
    """
    doc = json.load(io.open(path, encoding="utf-8"))
    n = 0
    for code, v in doc.items():
        if not isinstance(v, dict):
            continue
        e = v.get("effect") or ""
        if "無" in e:
            n += e.count("無")
            v["effect"] = e.replace("無", "无")
    if n and write:
        with io.open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(doc, ensure_ascii=False,
                               separators=(", ", ": ")))
    return n


def main():
    write = "--write" in sys.argv
    print("术语对齐（口径：萌卡社 Flagalac《基本能力及字段说明》）")
    total = 0
    for rel, rules in TARGETS.items():
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            print(f"  !! 缺 {rel}")
            continue
        s = io.open(p, encoding="utf-8").read()
        n = count_hits(s, rules)
        total += n
        print(f"  {rel}：{n} 处")
        if n and write:
            new = apply_rules(s, rules)
            if p.endswith(".json"):
                json.loads(new)      # 写回前校验，别把数据文件写坏
            io.open(p, "w", encoding="utf-8").write(new)

    # 卡数据的按字段处理（见 fix_card_fields 的说明）
    cp = os.path.join(ROOT, "assets/data/translations_zh.json")
    if os.path.exists(cp):
        n = fix_card_fields(cp, write=write)
        print(f"  translations_zh.json（按字段：effect 里的 無→无）：{n} 处")
        total += n

    print(f"合计 {total} 处" + ("（已写入）" if write and total else "（只报告，加 --write 才写）"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
