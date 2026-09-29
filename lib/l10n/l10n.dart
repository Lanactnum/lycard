import 'package:flutter/widgets.dart';

import 'table_en.dart';
import 'table_ja.dart';
import 'table_ko.dart';
import 'table_ru.dart';
import 'table_zh_hant.dart';

/// 界面语言（要求 L103）。
///
/// 只覆盖 **App 本体**的文案 —— 卡名、效果文本属于卡数据，
/// 不参与翻译（那些是官方日文 + 自译中文，跟界面语言无关）。
enum AppLang {
  zhHans, // 简体中文（原文，不需要表）
  zhHant, // 繁體中文
  en, // English
  ja, // 日本語
  ru, // Русский
  ko, // 한국어
}

extension AppLangX on AppLang {
  /// 存进 prefs 用的键
  String get code => switch (this) {
        AppLang.zhHans => 'zh-Hans',
        AppLang.zhHant => 'zh-Hant',
        AppLang.en => 'en',
        AppLang.ja => 'ja',
        AppLang.ru => 'ru',
        AppLang.ko => 'ko',
      };

  /// 语言选择里显示的名字（用它自己的语言写，方便辨认）
  String get label => switch (this) {
        AppLang.zhHans => '简体中文',
        AppLang.zhHant => '繁體中文',
        AppLang.en => 'English',
        AppLang.ja => '日本語',
        AppLang.ru => 'Русский',
        AppLang.ko => '한국어',
      };

  /// 用于 MaterialApp.locale（影响系统控件、日期格式等）
  Locale get locale => switch (this) {
        AppLang.zhHans => const Locale('zh', 'CN'),
        AppLang.zhHant => const Locale('zh', 'TW'),
        AppLang.en => const Locale('en'),
        AppLang.ja => const Locale('ja'),
        AppLang.ru => const Locale('ru'),
        AppLang.ko => const Locale('ko'),
      };

  Map<String, String> get table => switch (this) {
        AppLang.zhHans => const {}, // 中文就是源码里的原文
        AppLang.zhHant => kZhHant,
        AppLang.en => kEn,
        AppLang.ja => kJa,
        AppLang.ru => kRu,
        AppLang.ko => kKo,
      };
}

AppLang appLangFrom(String? code) => AppLang.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLang.zhHans,
    );

/// 界面文案查表。
///
/// **以中文原文为 key** —— 这样代码里写 `tr('检索')` 就行，
/// 不用为每条文案发明一个 key 名；中文（简中）时表是空的，
/// 直接返回原文，等于零开销。
///
/// 带变量的文案用占位符：
///     tr('胜负记录 · {0} 胜 {1} 负', [deck.wins, deck.losses])
class L10n {
  L10n._();

  static AppLang _lang = AppLang.zhHans;
  static Map<String, String> _table = const {};

  static AppLang get lang => _lang;

  static void set(AppLang l) {
    _lang = l;
    _table = l.table;
  }

  /// 翻译一条界面文案。[args] 按顺序填进 `{0}` `{1}`。
  static String tr(String zh, [List<Object?>? args]) {
    var s = _table[zh] ?? zh;
    if (args != null && args.isNotEmpty) {
      for (var i = 0; i < args.length; i++) {
        s = s.replaceAll('{$i}', '${args[i]}');
      }
    }
    return s;
  }

  /// 当前语言的表里有多少条（给设置页显示进度用）
  static int get translatedCount => _table.length;
}

/// 简写：`tr('检索')`。
/// 特意不叫 `t` —— 代码里局部变量叫 t 的地方不少，会撞名。
String tr(String zh, [List<Object?>? args]) => L10n.tr(zh, args);
