import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/l10n/l10n.dart';

/// 界面多语言（要求 L103）
void main() {
  tearDown(() => L10n.set(AppLang.zhHans));

  test('简体中文：表为空，直接返回原文', () {
    L10n.set(AppLang.zhHans);
    expect(tr('检索'), '检索');
    expect(tr('导出备份'), '导出备份');
    expect(L10n.translatedCount, 0, reason: '简中就是源码原文，不需要表');
  });

  test('每种语言都有译文，且不是原样返回中文', () {
    for (final lang in AppLang.values) {
      if (lang == AppLang.zhHans) continue;
      L10n.set(lang);
      expect(L10n.translatedCount, greaterThan(100),
          reason: '${lang.label} 的表太小，可能没生成成功');
      final s = tr('导出备份');
      expect(s, isNotEmpty);
      expect(s, isNot('导出备份'), reason: '${lang.label} 没翻这条');
    }
  });

  test('占位符按顺序填进去', () {
    L10n.set(AppLang.en);
    // 胜/负/胜率
    final s = tr('{0} 胜 {1} 负 · 胜率 {2}', [3, 1, '75%']);
    expect(s.contains('3'), isTrue);
    expect(s.contains('1'), isTrue);
    expect(s.contains('75%'), isTrue);
    expect(s.contains('{0}'), isFalse, reason: '占位符必须被替换掉');
    expect(s.contains('{2}'), isFalse);
  });

  test('占位符顺序不能被打乱（译文可以调位置）', () {
    for (final lang in AppLang.values) {
      if (lang == AppLang.zhHans) continue;
      L10n.set(lang);
      final s = tr('{0} · {1} 张', ['LO-0001', 4]);
      expect(s.contains('LO-0001'), isTrue, reason: '${lang.label} 丢了第一个参数');
      expect(s.contains('4'), isTrue, reason: '${lang.label} 丢了第二个参数');
    }
  });

  test('表里没有的文案：原样返回，不崩', () {
    L10n.set(AppLang.ja);
    expect(tr('这句文案不在表里'), '这句文案不在表里');
  });

  test('语言代码与 locale 对应', () {
    expect(AppLang.zhHant.code, 'zh-Hant');
    expect(AppLang.en.code, 'en');
    expect(appLangFrom('ja'), AppLang.ja);
    expect(appLangFrom('不认识'), AppLang.zhHans, reason: '认不出就回落到简中');
    expect(AppLang.ko.locale.languageCode, 'ko');
  });

  test('卡数据不参与界面翻译', () {
    // 卡名/效果是数据，不是界面文案 —— 表里不该出现它们
    L10n.set(AppLang.en);
    expect(tr('セイバー／アルトリア・ペンドラゴン'),
        'セイバー／アルトリア・ペンドラゴン',
        reason: '卡名不该被界面语言影响');
  });
}
