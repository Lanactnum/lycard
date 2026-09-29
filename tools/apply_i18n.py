#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把界面文案包成 t(...) 调用（要求 L103）。

    '检索'                    →  t('检索')
    '还有 ${n} 天'            →  t('还有 {0} 天', [n])

设计取舍：
  * **以中文原文为 key**，代码里不用发明 key 名；中文时表是空的，
    直接返回原文。
  * Dart 里相邻字符串字面量会自动拼接（多行长文案的常见写法），
    所以扫描时要把它们当成**一个逻辑字符串**处理，否则拆开查表
    就查不到译文了。
  * `const Text('x')` 里的字符串改成 t() 后不再是编译期常量，
    脚本会把这种情况记下来，交给后面清 const 的步骤处理。

用法：
    python tools/apply_i18n.py            # 只看计划
    python tools/apply_i18n.py --write    # 真改
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")
IDIR = os.path.join(ROOT, "work", "i18n")


def split_template(text):
    """Dart 插值 → {N} 占位符（与 make_i18n_templates.py 同一套规则）"""
    args, out, i, n = [], [], 0, len(text)
    while i < n:
        ch = text[i]
        if ch == "\\" and i + 1 < n:
            out.append(text[i:i + 2]); i += 2; continue
        if ch != "$":
            out.append(ch); i += 1; continue
        if i + 1 < n and text[i + 1] == "{":
            k = i + 2; depth = 1
            while k < n and depth:
                if text[k] == "{": depth += 1
                elif text[k] == "}": depth -= 1
                k += 1
            if depth != 0:
                return None, None
            expr = text[i + 2:k - 1]
            if "'" in expr or '"' in expr:
                return None, None
            args.append(expr)
            out.append("{%d}" % (len(args) - 1))
            i = k; continue
        m = re.match(r"\$([A-Za-z_][A-Za-z0-9_]*)", text[i:])
        if m:
            args.append(m.group(1))
            out.append("{%d}" % (len(args) - 1))
            i += m.end(); continue
        out.append(ch); i += 1
    return "".join(out), args


def scan_strings(src):
    """扫出所有字符串字面量：(start, end, quote, content)

    会跳过注释，并把 ${...} 整段跨过去（里面可能有引号）。
    """
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n:
            if src[i + 1] == "/":
                j = src.find("\n", i)
                i = n if j < 0 else j
                continue
            if src[i + 1] == "*":
                j = src.find("*/", i + 2)
                i = n if j < 0 else j + 2
                continue
        if c in "'\"":
            raw = (i > 0 and src[i - 1] == "r" and
                   (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == "_")))
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\" and not raw:
                    j += 2; continue
                if src[j] == q:
                    break
                if src[j] == "$" and j + 1 < n and src[j + 1] == "{":
                    depth, k = 1, j + 2
                    while k < n and depth:
                        if src[k] == "{": depth += 1
                        elif src[k] == "}": depth -= 1
                        k += 1
                    j = k; continue
                j += 1
            if j < n:
                out.append((i, j, q, src[i + 1:j]))
                i = j + 1
                continue
        i += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--emit-templates", action="store_true",
                    help="按同一套扫描逻辑产出 templates.json（覆盖）")
    args = ap.parse_args()

    templates = json.load(open(os.path.join(IDIR, "templates.json"),
                               encoding="utf-8"))
    keys = {t["key"] for t in templates}

    # 这些文件里的中日文串是**数据或查找用的锚点**，翻了会坏：
    #   search_index.dart —— 假名罗马字映射表（'きゃ'→'kya'）
    #   banlist_page.dart —— 官方页面区块标题（'使用禁止カード'），
    #                        翻了就定位不到区块
    SKIP_FILES = {
        os.path.join(LIB, "data", "search_index.dart"),  # 假名映射表（数据）
        os.path.join(LIB, "data", "banlist.dart"),       # 含官方页面锚点常量
        os.path.join(LIB, "l10n", "l10n.dart"),          # 语言名（用自己语言写）
        # theme_page：色板 key 是**查找用的标识**不能翻，但显示时要翻 ——
        # 自动改写分不清这两者，会写成 tr('琉璃蓝'): [...]（key 跟着语言变
        # 就查不到了）。人工处理。
        os.path.join(LIB, "pages", "theme_page.dart"),
    }

    files = []
    for base, _d, names in os.walk(LIB):
        # ⚠ 必须排除 lib/l10n：那里的 table_*.dart 是**译文表**，
        # 扫进去会把日文/繁中译文当成"待翻的中文文案"（实测踩过：
        # 968 条里混进一堆 'MITライセンスでオープンソース化'）
        if os.path.join(LIB, "l10n") == base or base.startswith(
                os.path.join(LIB, "l10n") + os.sep):
            continue
        for n in sorted(names):
            if not n.endswith(".dart"):
                continue
            full = os.path.join(base, n)
            if full in SKIP_FILES:
                continue
            files.append(full)

    plan = []       # (path, start, end, new_text, old_snippet)
    skipped_const = []
    stats = {"hit": 0, "files": set()}

    for path in files:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
        src = open(path, encoding="utf-8").read()
        lits = scan_strings(src)

        # 把相邻字符串字面量合并成一个逻辑串
        groups = []
        for idx, (s, e, q, content) in enumerate(lits):
            if groups:
                ps, pe, pq, pc, pend = groups[-1]
                between = src[pe + 1:s]
                if between.strip() == "" and "\n" in between:
                    # 紧邻（中间只有空白）→ 拼进去
                    groups[-1] = (ps, e, pq, pc + content, e)
                    continue
            groups.append((s, e, q, content, e))

        # emit 模式下先不按 keys 过滤：要收集所有候选
        # （否则"相邻拼接"出来的整句永远进不了表 —— keys 依赖命中、
        #  命中又依赖 keys，死循环）
        emit = args.emit_templates
        for (s, e, q, content, _end) in groups:
            tpl, arglist = split_template(content)
            if tpl is None:
                continue
            if not emit and tpl not in keys:
                continue
            # ⚠ 这些保护规则**两种模式都要跑**。
            # 一开始我写在 if emit: 里面，结果 --write 时它们全不生效 ——
            # 于是 brandOther、色板 key 这类「static 初始化值」被反复包成 tr()，
            # 每跑一次回写就坏一次（实测踩了好几轮）。
            if not plausible_ui(tpl, path, s):
                continue
            if should_keep_as_is(tpl):
                continue
            if looks_like_logic(src, s):
                continue
            if looks_like_data(src, s):
                continue
            if is_switch_case_pattern(src, s, e):
                continue
            if in_static_initializer(src, s):
                continue
            # 已经在 tr(...) 里了就别再包一层。
            # ⚠ 只在**真正改写**时跳过；emit 阶段必须照样收集 ——
            # 否则 templates.json 会越来越小（已包的文案全丢了），
            # 实测踩过：535 条被覆盖成 62 条。
            before = src[:s].rstrip()
            if not emit and (before.endswith("tr(") or
                             before.endswith("L10n.tr(")):
                continue

            if arglist:
                call = "tr(%s, [%s])" % (dart_str(tpl), ", ".join(arglist))
            else:
                call = "tr(%s)" % dart_str(tpl)

            # const 上下文：改成 t() 后不再是常量
            line_start = src.rfind("\n", 0, s) + 1
            if "const " in src[line_start:s]:
                skipped_const.append((rel, src[:s].count("\n") + 1))

            plan.append((path, rel, s, e + 1, call, content))
            stats["hit"] += 1
            stats["files"].add(rel)

    if args.emit_templates:
        uniq = {}
        for path, rel, s0, e0, call, old in plan:
            tpl, arglist = split_template(old)
            if tpl is None:
                continue
            uniq.setdefault(tpl, {
                "key": tpl,
                "args": arglist or [],
                "orig": old,
                "where": [],
            })
            uniq[tpl]["where"].append(f"{rel}:{src_line(path, s0)}")
        # ⚠ **合并**而不是覆盖：手工补进去的条目（色板名、find_missing_tr
        # 找到的）不在扫描结果里，覆盖会丢掉它们（实测：34 条被冲掉）。
        # 多余的条目只是表里多几个没人用的 key，无害。
        tpath = os.path.join(IDIR, "templates.json")
        existing = []
        if os.path.exists(tpath):
            try:
                existing = json.load(open(tpath, encoding="utf-8"))
            except Exception:      # noqa: BLE001
                existing = []
        by_key = {e["key"]: e for e in existing}
        added = 0
        for e in uniq.values():
            if e["key"] in by_key:
                # 已在表里：把位置信息补全（便于人工排查）
                cur = by_key[e["key"]].get("where") or []
                for w in e["where"]:
                    if w not in cur:
                        cur.append(w)
                by_key[e["key"]]["where"] = cur
            else:
                by_key[e["key"]] = e
                added += 1
        out = sorted(by_key.values(), key=lambda x: x["key"])
        json.dump(out, open(tpath, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=1)
        print(f"templates.json 已合并：扫描命中 {len(uniq)} 条，"
              f"新增 {added} 条，共 {len(out)} 条")
        return 0

    print(f"命中 {stats['hit']} 处，涉及 {len(stats['files'])} 个文件")
    if skipped_const:
        print(f"其中 {len(skipped_const)} 处所在行有 const（改完要清 const）")
    print("\n--- 前 25 条预览 ---")
    for path, rel, s, e, call, old in plan[:25]:
        print(f"  {rel}")
        print(f"    旧: {old[:70]!r}")
        print(f"    新: {call[:80]!r}")

    json.dump(
        [{"file": p[1], "start": p[2], "end": p[3], "call": p[4], "old": p[5]}
         for p in plan],
        open(os.path.join(IDIR, "plan.json"), "w", encoding="utf-8"),
        ensure_ascii=False, indent=1)
    print(f"\n计划写到 work/i18n/plan.json")

    if not args.write:
        print("（这是预览，加 --write 才真改）")
        return 0

    # 按文件从后往前替换，避免偏移错乱
    byfile = {}
    for path, rel, s, e, call, old in plan:
        byfile.setdefault(path, []).append((s, e, call))
    for path, items in byfile.items():
        src = open(path, encoding="utf-8").read()
        for s, e, call in sorted(items, key=lambda x: -x[0]):
            src = src[:s] + call + src[e:]
        # 补 import —— 但 part 文件不能有 import（Dart 规定），
        # 它们靠主文件的 import 生效
        # part of 不一定在第一行（前面可能有注释/import），要用正则找
        is_part = re.search(r"^\s*part of ", src, re.M) is not None
        if not is_part and "l10n/l10n.dart" not in src:
            depth = os.path.relpath(path, LIB).count(os.sep)
            up = "../" * depth if depth else ""
            imp = "import '%sl10n/l10n.dart';\n" % up
            lines = src.split("\n")
            last = max([k for k, l in enumerate(lines) if l.startswith("import ")],
                       default=-1)
            lines.insert(last + 1, imp.rstrip("\n"))
            src = "\n".join(lines)
        open(path, "w", encoding="utf-8").write(src)
    print(f"已改写 {len(byfile)} 个文件")
    return 0


# ⚠ 判断思路是**黑名单**，不是白名单。
#
# 一开始我用白名单（"前面必须出现 Text( / title: 才算界面文案"），
# 结果漏掉了 600 多处 —— 因为项目里大量文案是喂给自定义组件的
# （_seg('卡组', ...)、_kv('会社/品牌', ...)），白名单根本认不出来。
#
# 现在反过来：**默认认为中文串就是界面文案**，只排除明确不能翻的。

# 参与比较/分支的字符串：翻了会让逻辑悄悄失效
LOGIC_MARKERS = (
    "case ", "== ", "!= ", ".contains(", ".indexOf(", ".startsWith(",
    ".endsWith(", "switch (", "keys.contains(", "===", "where(", "firstWhere(",
    "removeWhere(", "any(", "every(", "indexWhere(",
)

# 这些位置的字符串是**数据/格式**，不是界面文案
DATA_MARKERS = (
    "RegExp(", "replaceAll(", "replaceFirst(", "split(",
    "Uri.parse", "http://", "https://", "assets/",
    "StringBuffer(", "toIso8601String", "jsonEncode", "jsonDecode",
    "debugPrint", "key:", "prefs.set", "prefs.get", "getString(",
    "setString(", "SharedPreferences",
)

# 这些是"用自己语言写的名字"，本来就不该跟着界面语言变
KEEP_AS_IS = (
    "简体中文", "繁體中文", "English", "日本語", "Русский", "한국어",
)


def plausible_ui(tpl, path, offset):
    """粗筛：这条像不像给人看的界面文案"""
    if len(tpl) > 260 or len(tpl.strip()) < 2:
        return False
    # 跨行的多半是提取时把代码片段当成了字符串
    if chr(10) in tpl or ";" in tpl:
        return False
    # 至少要有一个中日文字符，否则是技术字符串
    if not re.search(r"[一-鿿぀-ヿ]", tpl):
        return False
    # 明显是正则/格式串
    if re.search(r"\\s|\\w|\\d|\[\]", tpl):
        return False
    return True


def _same_line_head(src, offset, limit=70):
    """取字符串**所在行**、且在它之前的那一段（最多 limit 字符）。

    为什么限定同一行：一开始我用"往前看 110 字符"，结果跨行把**相邻参数**
    里的东西也算进来了 —— 比如
        _copy(context, CardRepository.exportText(card), '卡片信息已复制')
    那条 SnackBar 消息被 exportText 误判成"数据"，白白漏翻。
    """
    start = src.rfind(chr(10), 0, offset) + 1
    seg = src[start:offset]
    return seg[-limit:]


def _is_collection_kw(stripped, kw):
    """判断这一段是不是以集合 if/for 结尾（`if (cond) ` / `for (x in y) `）。

    用纯字符串判断而不是正则：这个环境里 `` 经过 bash heredoc +
    Python 转义会变成退格符 0x08，正则静默失效（踩过两次）。
    """
    tail = stripped.rsplit(kw, 1)
    if len(tail) != 2:
        return False
    last = tail[1].strip()
    # 形如 "(cond)" 或 "(cond) " —— 必须是完整的括号段
    return last.startswith("(") and last.endswith(")")


def looks_like_logic(src, offset):
    """字符串是不是在参与逻辑比较？

    这条很关键：像 `kind == '角色'` 这种，如果把 '角色' 翻译成
    'Character'，比较就永远不成立 —— 界面看着没问题，功能悄悄坏了。

    但要注意**三元表达式**的误伤：

        contains(code) ? '取消 MVP 标记' : '标记为 MVP'
        _selected.length == _results.length ? '取消全选' : '全选'

    这两个字符串是**显示值**，该翻；而前面的 `contains(` / `==` 只是
    条件，不是拿它们去比较。判据：字符串紧跟在 `?` 或 `:` 后面 → UI。
    """
    head = _same_line_head(src, offset)
    stripped = head.rstrip()
    # 三元分支的值 → 是文案，要翻
    if stripped.endswith("?") or stripped.endswith(":"):
        return False
    # 集合 if / for 的元素值 → 也是文案，要翻：
    #     [ if (e.nameZh != null) '名字已改', ... ]
    # 这里的 `!=` 只是条件，不是拿字符串去比较。
    # 集合 if 的元素值（如 `if (cond) '文案'`）→ 是文案
    if _is_collection_kw(stripped, "if"):
        return False
        return False
    # 集合 if 的元素值（如 `if (cond) '文案'`）→ 是文案
    if _is_collection_kw(stripped, "if"):
        return False
        return False
    for m in LOGIC_MARKERS:
        if m in head:
            return True
    return False


def looks_like_data(src, offset):
    """字符串是不是数据/格式串（路径、正则、prefs 键…）"""
    head = _same_line_head(src, offset)
    for m in DATA_MARKERS:
        if m in head:
            return True
    return False


def in_static_initializer(src, offset):
    """字符串是不是 **static 字段的初始化值**？

    这种绝不能翻，两个原因：
      1. static 字段在**类加载时**求值，那时 L10n 可能还没 set，
         拿到的是默认语言的值，之后再切语言也不会重算；
      2. 这类字段常被用作**分组 key / 排序键 / 比较基准**
         （如 LyceeCard.brandOther），跟着语言变会让逻辑错乱。
    显示用的文案在显示处套 tr() 即可。
    """
    head = _same_line_head(src, offset, limit=200)
    head = head.replace(chr(9), " ")
    return ("static " in head or head.strip().startswith("static")) and "=" in head


def in_default_param(src, offset):
    """字符串是不是**函数默认参数值**？

        Future<void> f({String label = '关闭'}) { ... }

    Dart 要求默认参数是编译期常量，包成 tr('关闭') 会直接编译不过
    （const_eval_method_invocation）。这类文案在函数体里兜底即可：
        final label = barrierLabel ?? tr('关闭');
    """
    head = _same_line_head(src, offset, limit=200)
    # 形如  String xxx = '  或  {String xxx = '
    return bool(re.search(r"[\w\]>]\s+\w+\s*=\s*$", head))


def is_switch_case_pattern(src, start, end):
    """字符串是不是 switch 表达式的**匹配模式**？

        String? kKindZh(String? kind) => switch (kind) {
              'キャラクター' => '角色',      ← 这个不能翻
              'イベント'     => '事件',
            };

    左边的 'キャラクター' 是用来和 c.kind 比较的日文常量，翻了就永远
    匹配不上；右边的 '角色' 才是给用户看的，要翻。
    判据：字符串**后面**紧跟 `=>`。箭头函数的 `() => foo('x')` 里
    字符串后面是 `)`，不会误伤。
    """
    # 注意：end 指向的是**结尾引号本身**（scan_strings 返回的 j），
    # 所以要从 end+1 开始看，否则第一个字符是引号，永远判不中。
    rest = src[end + 1:end + 8].lstrip()
    return rest.startswith("=>")


def should_keep_as_is(tpl):
    return tpl.strip() in KEEP_AS_IS


def plausible_ui(tpl, path, offset):
    """粗筛：这条像不像给人看的界面文案（emit 模式下用）"""
    if len(tpl) > 220 or len(tpl.strip()) < 2:
        return False
    # 至少要有一个中日文字符，否则是技术字符串
    if not re.search(r"[一-鿿぀-ヿ]", tpl):
        return False
    # 调试输出不是界面文案
    NL = chr(10)
    line = open(path, encoding="utf-8").read()[:offset].split(NL)[-1]
    if "debugPrint" in line:
        return False
    # 明显是正则/格式串
    if re.search(r"\\s|\\w|\\d|\[\]", tpl):
        return False
    return True


def src_line(path, offset):
    """offset 在文件里是第几行（给人工排查用）"""
    NL = chr(10)   # 别写字面量转义：这个环境里会被三层转义吃掉
    try:
        return open(path, encoding="utf-8").read()[:offset].count(NL) + 1
    except OSError:
        return 0


def dart_str(s):
    s = s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
    s = s.replace("\n", "\\n").replace("\r", "")
    return "'" + s + "'"


if __name__ == "__main__":
    sys.exit(main())
