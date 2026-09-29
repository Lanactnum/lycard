"""生成 assets/data/search_keys.json —— 模糊搜索用的归一化检索键。

思路：把"归一化"这件事全部放到数据侧做一次，App 侧只做纯字符串匹配，
这样 Dart 端不需要引入拼音/繁简转换之类的依赖，也不会拖慢启动。

每张卡的检索键里同时塞进这些形式，所以不管用户怎么输都能命中：
  · 原文归一化（保留繁体 → 用户输繁体时命中）
  · 简体归一化（用户输简体时命中）
  · 假名 → 罗马字（用户输 romaji 时命中）
  · 汉字全拼 + 首字母（用户输 pinyin 时命中）

归一化 = 全角转半角 + 转小写 + 删掉空格与各种符号（・，。、《》…）。
"""
import json
import re
import unicodedata

from opencc import OpenCC
from pypinyin import Style, lazy_pinyin

CC = OpenCC('t2s')
CC_S2T = OpenCC('s2t')

# ── 假名 → 罗马字（够用就行：基本五十音 + 浊音 + 拗音）──
KANA = {
    'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
    'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
    'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
    'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
    'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
    'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
    'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
    'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
    'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
    'わ': 'wa', 'を': 'o', 'ん': 'n',
    'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
    'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
    'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
    'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
    'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
    'ぁ': 'a', 'ぃ': 'i', 'ぅ': 'u', 'ぇ': 'e', 'ぉ': 'o',
    'っ': '', 'ゃ': 'ya', 'ゅ': 'yu', 'ょ': 'yo', 'ー': '',
    'ヴ': 'bu', 'ゔ': 'bu',
}
# 拗音组合（先长后短地替换）
YOON = {
    'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
    'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
    'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
    'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
    'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
    'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
    'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
    'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
    'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
    'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
    'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
}

_KATA_START = ord('ァ')
_KATA_END = ord('ヶ')


def kata_to_hira(s: str) -> str:
    out = []
    for ch in s:
        o = ord(ch)
        if _KATA_START <= o <= _KATA_END:
            out.append(chr(o - 0x60))
        else:
            out.append(ch)
    return ''.join(out)


def kana_to_romaji(s: str) -> str:
    s = kata_to_hira(s)
    for k, v in YOON.items():
        s = s.replace(k, v)
    return ''.join(KANA.get(ch, ch) for ch in s)


_SYMBOLS = re.compile(
    r'[\s\u00a0\u3000・･·、。，,.\-—–_/／|｜:：;；!！?？'
    r'\'"“”‘’()（）\[\]【】{}｛｝~～^+=*#@$%&\\<>《》〈〉「」『』]'
)


def norm(s: str) -> str:
    """全角→半角、小写、去掉空格与符号"""
    if not s:
        return ''
    s = unicodedata.normalize('NFKC', s)
    s = s.lower()
    return _SYMBOLS.sub('', s)


def build_key(card: dict) -> str:
    parts = []
    raws = [
        card.get('name'),        # 日文卡名
        card.get('name_zh'),     # 中文卡名
        card.get('title_jp'),    # 作品名
        card.get('effect_jp'),   # 日文效果
        card.get('effect_zh'),   # 中文效果
    ]
    for raw in raws:
        if not raw:
            continue
        n = norm(raw)
        if n:
            parts.append(n)                       # 原样（含繁体，用户输繁体命中）
        t = norm(CC.convert(raw))
        if t and t != n:
            parts.append(t)                       # 简体版
        # 卡名的中文译文本身是简体，用户可能输繁体，所以再补一个繁体形式
        t2 = norm(CC_S2T.convert(raw))
        if t2 and t2 != n and t2 != t:
            parts.append(t2)
        r = norm(kana_to_romaji(raw))
        if r and r != n:
            parts.append(r)                       # 罗马字版
    # 拼音（只做卡名，效果文本太长没必要）
    for raw in [card.get('name_zh'), card.get('name')]:
        if not raw:
            continue
        try:
            # pypinyin 的输出里可能夹着空格/符号（分词留下的），必须再过一遍 norm，
            # 否则「bxna」这种首字母连写永远搜不到
            parts.append(norm(''.join(lazy_pinyin(raw))))
            parts.append(
                norm(''.join(lazy_pinyin(raw, style=Style.FIRST_LETTER))))
        except Exception:
            pass
    # 去重保序
    seen, out = set(), []
    for p in parts:
        if p and p not in seen:
            seen.add(p)
            out.append(p)
    return ' '.join(out)


def main() -> None:
    src = 'assets/data/cards_app.json'
    dst = 'assets/data/search_keys.json'
    d = json.load(open(src, encoding='utf-8'))
    cards = d if isinstance(d, list) else d.get('cards', [])
    keys = {}
    for c in cards:
        code = c.get('code')
        if code:
            keys[code] = build_key(c)
    json.dump(keys, open(dst, 'w', encoding='utf-8'),
              ensure_ascii=False, separators=(',', ':'))
    import os
    print(f'写入 {dst}: {len(keys)} 张卡, {os.path.getsize(dst)/1048576:.1f} MB')
    for code in list(keys)[:3]:
        print(f'  {code}: {keys[code][:110]}')


if __name__ == '__main__':
    main()
