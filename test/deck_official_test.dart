import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/deck_official.dart';

/// 官方卡组页的关键结构（照真实页面裁剪）：
/// · 「デッキ名」那一行给卡组名
/// · 卡表每行是 `<td>N枚</td><td>卡号</td>`
/// · 兜底用「このデッキから新しいデッキを作る」里的 deckline
const String _officialHtml = '''
<div class="title_inner">
<h2>おうちでリセフェスタ #19(2020年08月22日) 1位</h2>
</div>
<table border="1">
<tr><th width="150">デッキ名</th><td>おうちでリセフェスタ #19(2020年08月22日) 1位 </td></tr>
<tr><th>作者</th><td>明（あき）(PP005189)</td></tr>
</table>
<a href="/card/?f_deckon=1&deckmode=argvimport&deckline=1691:1,0701:4,0691:1,">[このデッキから新しいデッキを作る]</a>
<table border="1">
<TR><TH width="90px">枚数</TH><TH>カード番号</TH><TH colspan="5">カード情報</TH></TR>
\t<tr>
\t\t<td>1枚</td>
\t\t<td>LO-0691</td>
\t\t<td>マスコットガール 海老原 みなせ</td>
\t</tr>
\t<tr>
\t\t<td>4枚</td>
\t\t<td>LO-0701</td>
\t\t<td>- 光速のエビ</td>
\t</tr>
\t<tr>
\t\t<td>2枚</td>
\t\t<td>LO-2690-K</td>
\t\t<td>異画</td>
\t</tr>
</table>
''';

void main() {
  group('官方卡组链接识别', () {
    test('认短链 lyc.ee', () {
      expect(OfficialDeck.looksLike('https://lyc.ee/d200009005189'), isTrue);
      expect(OfficialDeck.deckId('https://lyc.ee/d200009005189'),
          '200009005189');
    });

    test('认长链 lycee-tcg.com', () {
      expect(
        OfficialDeck.deckId('https://lycee-tcg.com/d/?d=200009005189'),
        '200009005189',
      );
      expect(
        OfficialDeck.deckId('http://www.lycee-tcg.com/d/?d=200009005189'),
        '200009005189',
      );
    });

    test('认单独一串数字 ID', () {
      expect(OfficialDeck.deckId('200009005189'), '200009005189');
    });

    test('别的东西不会被当成官方链接', () {
      expect(OfficialDeck.looksLike('LYD1abc'), isFalse);
      expect(OfficialDeck.looksLike('随便一段文字'), isFalse);
      expect(OfficialDeck.looksLike('https://example.com/d/?d=123'), isFalse);
      // 太短的纯数字不当 ID，避免误判
      expect(OfficialDeck.looksLike('123'), isFalse);
    });

    test('抓取地址统一走长链', () {
      expect(
        OfficialDeck.fetchUrl('200009005189').toString(),
        'https://lycee-tcg.com/d/?d=200009005189',
      );
    });
  });

  group('官方卡组页解析', () {
    test('读出卡组名与卡表', () {
      final d = OfficialDeck.parse(_officialHtml);
      expect(d, isNotNull);
      expect(d!.name, contains('おうちでリセフェスタ #19'));
      expect(d.cards['LO-0691'], 1);
      expect(d.cards['LO-0701'], 4);
      // 异画后缀要保留（这是表格解析存在的意义）
      expect(d.cards['LO-2690-K'], 2);
      expect(d.total, 7);
    });

    test('没有表格时退回 deckline', () {
      const html = '<h2>测试卡组</h2>'
          '<a href="/card/?deckmode=argvimport&deckline=1691:1,0701:4,">x</a>';
      final d = OfficialDeck.parse(html);
      expect(d, isNotNull);
      expect(d!.name, '测试卡组');
      // deckline 只有纯数字，补成 4 位再拼 LO-
      expect(d.cards['LO-1691'], 1);
      expect(d.cards['LO-0701'], 4);
    });

    test('没有卡表就返回 null', () {
      expect(OfficialDeck.parse('<h2>空页面</h2>'), isNull);
      expect(OfficialDeck.parse(''), isNull);
    });

    test('同一卡号出现多次会累加', () {
      const html = '<td>1枚</td><td>LO-0001</td>'
          '<td>3枚</td><td>LO-0001</td>';
      final d = OfficialDeck.parse(html);
      expect(d!.cards['LO-0001'], 4);
    });
  });
}
