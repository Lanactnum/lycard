import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../data/clipboard_watch.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/card_repository.dart';
import '../data/bg_image.dart';
import '../data/storage_manager.dart';
import '../models/card_edit.dart';
import '../models/collect_info.dart';
import '../models/lycee_card.dart';
import '../models/wish_card.dart';
import '../data/deck_share.dart';
import '../l10n/l10n.dart';
import '../data/banlist.dart';

/// 一套主战构筑
class Deck {
  Deck({
    required this.id,
    required this.name,
    required this.mainCardCode,
    this.coverCode = '',
    this.intro = '',
    this.format = DeckFormat.libre,
    Map<String, int>? cards,
    Map<String, int>? sideboard,
    List<BattleRecord>? battles,
    List<DeckSnapshot>? snapshots,
    Set<String>? mvpCodes,
    Map<String, String>? cardNotes,
    List<String>? ignoredWarnings,
    bool? hideMissing,
  })  : cards = cards ?? <String, int>{},
        sideboard = sideboard ?? <String, int>{},
        battles = battles ?? <BattleRecord>[],
        snapshots = snapshots ?? <DeckSnapshot>[],
        mvpCodes = mvpCodes ?? <String>{},
        cardNotes = cardNotes ?? <String, String>{},
        ignoredWarnings = ignoredWarnings ?? <String>[],
        hideMissing = hideMissing ?? false;

  /// 备卡区：0~10 张（可选）
  static const int maxSideboard = 10;

  /// 规则模式（默认自由构筑）
  DeckFormat format;

  final String id;
  String name; // 构筑名
  String mainCardCode; // 主战卡号（可为空 = 未设置）
  String coverCode; // 封面卡号（为空则依次回退：主战卡 → 第一张卡）
  String intro; // 简介（细体、比标题小、可编辑）
  Map<String, int> cards; // code -> 张数

  /// 备卡区：0~10 张（可选）。构筑限制与主卡组联动计算，统计图只算主卡区。
  Map<String, int> sideboard;

  /// 胜负记录
  List<BattleRecord> battles;

  /// 版本快照（v1.0 比赛版…），回滚时连该版本的胜负记录一起带回来
  List<DeckSnapshot> snapshots;

  /// 打了 MVP 标记的卡号
  Set<String> mvpCodes;

  /// 单卡心得：code -> 文字
  Map<String, String> cardNotes;

  /// 被手动忽略的软性提示（存消息原文，匹配上就不再提示）
  List<String> ignoredWarnings;

  /// 缺卡提醒是否被忽略（用户可手动关掉）
  bool hideMissing;

  int get total => cards.values.fold(0, (a, b) => a + b);
  int get sideTotal => sideboard.values.fold(0, (a, b) => a + b);

  int get wins => battles.where((b) => b.win).length;
  int get losses => battles.length - wins;
  bool get hasBattles => battles.isNotEmpty;

  String get winRateText => battles.isEmpty
      ? '-'
      : '${(wins * 100 / battles.length).toStringAsFixed(1)}%';

  /// 盖掉这套构筑的内容（回滚用）
  void applySnapshot(DeckSnapshot s) {
    mainCardCode = s.mainCardCode;
    cards = Map<String, int>.from(s.cards);
    sideboard = Map<String, int>.from(s.sideboard);
    battles = s.battles.map((b) => b.copy()).toList();
  }

  DeckSnapshot snapshotAs(String label) => DeckSnapshot(
        id: 's${DateTime.now().microsecondsSinceEpoch}',
        label: label,
        at: DateTime.now(),
        mainCardCode: mainCardCode,
        cards: Map<String, int>.from(cards),
        sideboard: Map<String, int>.from(sideboard),
        battles: battles.map((b) => b.copy()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mainCard': mainCardCode,
        'cover': coverCode,
        'intro': intro,
        'format': format.name,
        'cards': cards,
        'sideboard': sideboard,
        'battles': battles.map((b) => b.toJson()).toList(),
        'snapshots': snapshots.map((s) => s.toJson()).toList(),
        'mvp': mvpCodes.toList(),
        'cardNotes': cardNotes,
        if (ignoredWarnings.isNotEmpty) 'ignoredWarnings': ignoredWarnings,
        if (hideMissing) 'hideMissing': true,
      };

  factory Deck.fromJson(Map<String, dynamic> j) => Deck(
        id: '${j['id']}',
        name: '${j['name']}',
        mainCardCode: '${j['mainCard'] ?? ''}',
        coverCode: '${j['cover'] ?? ''}',
        intro: '${j['intro'] ?? ''}',
        format: deckFormatFrom(j['format'] as String?),
        cards: (j['cards'] as Map?)?.map((k, v) => MapEntry('$k', v as int)) ??
            <String, int>{},
        sideboard: (j['sideboard'] as Map?)
                ?.map((k, v) => MapEntry('$k', v as int)) ??
            <String, int>{},
        battles: (j['battles'] as List? ?? const [])
            .map((e) => BattleRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        snapshots: (j['snapshots'] as List? ?? const [])
            .map((e) => DeckSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
        mvpCodes:
            (j['mvp'] as List? ?? const []).map((e) => '$e').toSet(),
        cardNotes: (j['cardNotes'] as Map?)
                ?.map((k, v) => MapEntry('$k', '$v')) ??
            <String, String>{},
        hideMissing: j['hideMissing'] == true,
        ignoredWarnings: (j['ignoredWarnings'] as List? ?? const [])
            .map((e) => '$e')
            .toList(),
      );
}

/// 一场战绩
class BattleRecord {
  BattleRecord({
    required this.id,
    required this.win,
    this.memo = '',
    this.opponent = '',
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  bool win;
  String memo;
  String opponent;
  DateTime at;

  BattleRecord copy() => BattleRecord(
      id: id, win: win, memo: memo, opponent: opponent, at: at);

  Map<String, dynamic> toJson() => {
        'id': id,
        'win': win,
        'memo': memo,
        'opponent': opponent,
        'at': at.toIso8601String(),
      };

  static BattleRecord fromJson(Map<String, dynamic> j) => BattleRecord(
        id: '${j['id']}',
        win: j['win'] == true,
        memo: '${j['memo'] ?? ''}',
        opponent: '${j['opponent'] ?? ''}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
      );
}

/// 构筑版本快照
class DeckSnapshot {
  DeckSnapshot({
    required this.id,
    required this.label,
    required this.at,
    required this.mainCardCode,
    required this.cards,
    required this.sideboard,
    required this.battles,
  });

  final String id;
  final String label;
  final DateTime at;
  final String mainCardCode;
  final Map<String, int> cards;
  final Map<String, int> sideboard;
  final List<BattleRecord> battles;

  int get wins => battles.where((b) => b.win).length;
  int get losses => battles.length - wins;
  int get total => cards.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'at': at.toIso8601String(),
        'mainCard': mainCardCode,
        'cards': cards,
        'sideboard': sideboard,
        'battles': battles.map((b) => b.toJson()).toList(),
      };

  static DeckSnapshot fromJson(Map<String, dynamic> j) => DeckSnapshot(
        id: '${j['id']}',
        label: '${j['label']}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        mainCardCode: '${j['mainCard'] ?? ''}',
        cards: (j['cards'] as Map?)?.map((k, v) => MapEntry('$k', v as int)) ??
            <String, int>{},
        sideboard: (j['sideboard'] as Map?)
                ?.map((k, v) => MapEntry('$k', v as int)) ??
            <String, int>{},
        battles: (j['battles'] as List? ?? const [])
            .map((e) => BattleRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 常用币种 → 人民币 的默认汇率（联网拿不到汇率时兜底）
const Map<String, double> kDefaultRates = {
  'CNY': 1.0,
  'JPY': 0.048,
  'USD': 7.2,
  'EUR': 7.8,
  'HKD': 0.92,
  'TWD': 0.22,
  'KRW': 0.0052,
  'GBP': 9.1,
};

const List<String> kCurrencies = ['CNY', 'JPY', 'USD', 'EUR', 'HKD', 'TWD', 'KRW', 'GBP'];

/// 一张卡的「入库信息」（玩家自己填的购入价 / 入库时间 / 汇率）
class OwnedInfo {
  OwnedInfo({
    this.price,
    this.currency = 'JPY',
    this.acquiredAt,
    this.rate,
    this.note = '',
  });

  /// 入库金额（按 [currency] 计价）
  double? price;

  /// 币种
  String currency;

  /// 入库时间（为空 = 未填，用默认汇率）
  DateTime? acquiredAt;

  /// 1 个 [currency] 折算成多少人民币；null = 用 [kDefaultRates] 或联网结果
  double? rate;

  /// 备注
  String note;

  double get effectiveRate => rate ?? kDefaultRates[currency] ?? 1.0;

  /// 折算成人民币的这张卡的价值（没填价格 = 不算）
  double? get valueCny => price == null ? null : price! * effectiveRate;

  Map<String, dynamic> toJson() => {
        'price': price,
        'currency': currency,
        'acquiredAt': acquiredAt?.toIso8601String(),
        'rate': rate,
        'note': note,
      };

  factory OwnedInfo.fromJson(Map<String, dynamic> j) => OwnedInfo(
        price: (j['price'] as num?)?.toDouble(),
        currency: '${j['currency'] ?? 'JPY'}',
        acquiredAt: j['acquiredAt'] == null
            ? null
            : DateTime.tryParse('${j['acquiredAt']}'),
        rate: (j['rate'] as num?)?.toDouble(),
        note: '${j['note'] ?? ''}',
      );

  OwnedInfo copy() => OwnedInfo(
        price: price,
        currency: currency,
        acquiredAt: acquiredAt,
        rate: rate,
        note: note,
      );
}

/// 构筑规则（Lycee Overture 官方规则）
/// 构筑规则模式（不同比赛规则用不同校验算法）
enum DeckFormat {
  libre, // 自由构筑（Mix Format）
  neoClassic, // 单作品构筑（Neo-Classic）
  hybrid, // 混合属性构筑
  sealed, // 限定赛（Draft / Sealed）
}

Map<DeckFormat, String> kFormatName = {
  DeckFormat.libre: tr('自由构筑'),
  DeckFormat.neoClassic: tr('单作品'),
  DeckFormat.hybrid: tr('混合属性'),
  DeckFormat.sealed: tr('限定赛'),
};

Map<DeckFormat, String> kFormatDesc = {
  DeckFormat.libre: tr('Mix Format：只使用基本规则（张数/同编号上限/leader/备卡区）'),
  DeckFormat.neoClassic: tr('Neo-Classic：主卡组必须同一作品（含leader）'),
  DeckFormat.hybrid: tr('混合属性：主卡组属性最多 2 种'),
  DeckFormat.sealed: tr('Draft/Sealed：30 张/同编号最多 2 张/不可携带备卡'),
};

DeckFormat deckFormatFrom(String? s) => DeckFormat.values.firstWhere(
      (f) => f.name == s,
      orElse: () => DeckFormat.libre,
    );

class DeckRules {
  /// 1. 卡组构成 60 张（限定赛 30 张）
  static const int mainDeckSize = 60;
  static const int sealedDeckSize = 30;

  /// 2. 相同编号的卡最多 4 张（-A / -P 等变体算不同编号）；限定赛 2 张
  static const int maxCopiesPerCode = 4;
  static const int sealedMaxCopies = 2;

  /// 4. 基本能力含 leader 的卡最多 1 张
  static const int maxLeader = 1;

  /// 5. 混合属性构筑最多用几种属性
  static const int hybridMaxColors = 2;

  static int mainSizeFor(DeckFormat f) =>
      f == DeckFormat.sealed ? sealedDeckSize : mainDeckSize;

  static int maxCopiesFor(DeckFormat f) =>
      f == DeckFormat.sealed ? sealedMaxCopies : maxCopiesPerCode;

  static int maxSideFor(DeckFormat f) =>
      f == DeckFormat.sealed ? 0 : 10;
}

/// 构筑检查结果
class DeckIssue {
  const DeckIssue(this.level, this.message, {this.key});

  final IssueLevel level;
  final String message;

  /// 稳定的标识：软性提示可以按它「忽略」
  final String? key;
}

enum IssueLevel { error, warning, ok }

class AppState extends ChangeNotifier {
  AppState(this._prefs);

  final SharedPreferences _prefs;

  // ---------- 设置 ----------
  ThemeMode _themeMode = ThemeMode.system;
  bool _dynamicColor = true;
  Color _seed = const Color(0xFF3F7FBF);
  int _gridColumns = 0; // 0 = 自动（按屏宽）
  bool _useZh = true; // 默认显示中文
  AppLang _lang = AppLang.zhHans; // 界面语言（要求 L103）
  bool _showEffectInGrid = false;
  bool _expressiveCorners = false;
  int _cornerStyle = 1; // 0=精简(6) 1=常规(12) 2=夸张(20)
  /// 进 App 默认显示哪一栏。
  ///
  /// ⚠ 这里存的是**栏位身份**（0 检索 / 1 计算器 / 2 构筑 / 3 我的），
  /// 而不是「第几个」—— 计算器插进检索和构筑之间时，如果按位置存，
  /// 老用户存过的「构筑(1)」会变成计算器，语义就错了。
  int _startTab = 0;

  /// 剪贴板监听（要求 L73）：默认关闭，属于"可选开启"
  bool _clipboardWatch = false;
  String _valueUnit = 'CNY'; // 卡组价值显示单位
  bool _valueHidden = true; // 卡组价值默认隐藏
  bool _searchNumberPad = true; // 搜索框默认数字键盘（L81）
  double _dpiScale = 1.0; // 界面缩放 / DPI（L107）
  bool _haptics = true; // 震动适配（L119）
  bool _statsFloating = false; // 统计图以浮窗显示（L92）
  bool _statsVisible = true; // 统计图显示开关（L92）
  // ── 外观：悬浮 / 玻璃 / 背景（L99 L101 L117）──
  bool _floatingChrome = false; // 底栏、弹出页用悬浮样式（L99）
  bool _glassEffect = false;
  int _glassMode = 0; // 0=关 1=高斯模糊 2=柔光玻璃
  double _cornerRadiusValue = 12; // 自定义圆角度数
  double _motionScale = 1.0; // 动效程度 0~1.5
  // 顶栏 + 底栏 + 搜索/筛选胶囊：这三个共用一组（不填就跟随全局）
  double? _barBlur;
  double? _barOpacity; // 透明/毛玻璃效果总开关（L101）
  double _glassBlur = 18; // 模糊强度 0~30
  double _glassOpacity = 0.18; // 玻璃层不透明度 0.05~1（默认偏低才看得出透明）
  String _bgImage = ''; // 背景图文件名（files/backgrounds/）
  String _bgPath = ''; // 解析好的绝对路径（启动时算一次，避免每次切页都去读盘）
  ImageProvider? _bgProvider; // 复用的图片 provider
  ui.Image? _bgRaw; // 预解码好的位图：绘制是同步的，换页面不会"卡一下"
  double _bgBrightness = 1.0; // 背景亮度 0.5~1.5
  double _bgBlur = 0; // 背景模糊 0~20
  double _bgZoom = 1.0; // 背景缩放（裁剪）1~2
  int _bgRotation = 0; // 背景旋转 0/90/180/270
  int _bgMaskColor = 0xFF000000; // 背景遮罩色
  double _bgMaskOpacity = 0.25; // 背景遮罩不透明度 0~0.9
  // 悬浮统计窗的位置（要求 L121：位置持久化 + 不跑出屏外）
  double _floatX = 8;
  double _floatY = 90;
  // 字体（要求 L105）
  String _fontFile = ''; // 自定义字体文件名（files/fonts/）
  int _fontColor = 0; // 0 = 跟随主题；否则是 ARGB
  bool _dynWeight = true; // 动态字重（可变字体）

  ThemeMode get themeMode => _themeMode;
  bool get dynamicColor => _dynamicColor;
  Color get seed => _seed;
  int get gridColumns => _gridColumns;
  bool get useZh => _useZh;
  AppLang get lang => _lang;
  bool get showEffectInGrid => _showEffectInGrid;
  bool get expressiveCorners => _expressiveCorners;
  int get cornerStyle => _cornerStyle;
  double get cornerRadius => _cornerRadiusValue.clamp(0, 28);
  int get startTab => _startTab;

  bool get clipboardWatch => _clipboardWatch;

  void setClipboardWatch(bool v) {
    _clipboardWatch = v;
    if (!v) ClipboardWatch.reset();
    notifyListeners();
    _save();
  }
  bool get searchNumberPad => _searchNumberPad;
  double get dpiScale => _dpiScale;
  bool get haptics => _haptics;
  bool get statsFloating => _statsFloating;
  bool get statsVisible => _statsVisible;
  /// 强制悬浮（已去掉开关，永远是开的）
  bool get floatingChrome => true;
  bool get glassEffect => true;

  /// 强制透明/模糊（已去掉开关，永远是开的）；模糊与不透明度仍可调
  int get glassMode => 1;
  double get cornerRadiusValue => _cornerRadiusValue;
  double get motionScale => _motionScale;

  /// 顶栏 / 底栏 / 分段胶囊 共用（null = 跟随全局）
  double get barBlur => _barBlur ?? _glassBlur;
  double get barOpacity => _barOpacity ?? _glassOpacity;

  void setBarBlur(double v) {
    _barBlur = v.clamp(0.0, 40.0);
    notifyListeners();
    _save();
  }

  void setBarOpacity(double v) {
    _barOpacity = v.clamp(0.02, 1.0);
    notifyListeners();
    _save();
  }

  void resetBarLook() {
    _barBlur = null;
    _barOpacity = null;
    notifyListeners();
    _save();
  }
  double get glassBlur => _glassBlur;
  double get glassOpacity => _glassOpacity;
  String get bgImage => _bgImage;
  String get bgPath => _bgPath;

  /// 只建一次的图片 provider（切页面不会重新解码 → 不会卡）
  ImageProvider? get bgProvider => _bgProvider;

  /// 预解码的位图（优先用它画）
  ui.Image? get bgRaw => _bgRaw;

  /// 启动时把背景图路径解析好（要求：切页面不能卡）
  Future<void> resolveBgPath() async {
    _bgPath = '';
    _bgProvider = null;
    _bgRaw?.dispose();
    _bgRaw = null;
    if (_bgImage.isEmpty) return;
    final p = await StorageManager.instance.bgPath(_bgImage);
    if (p == null) return;
    _bgPath = p;
    _bgProvider = FileImage(File(p));
    // 先解码成位图：「进新一级界面时背景卡一下才出来」就是每次重新解码导致的
    try {
      final bytes = await File(p).readAsBytes();
      // 缩到 1080 宽就够用：位图小、光栅化快，换页面不会卡一下
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 1080);
      final frame = await codec.getNextFrame();
      _bgRaw = frame.image;
    } catch (_) {}
    notifyListeners();
  }
  bool get hasBg => _bgImage.isNotEmpty;
  double get bgBrightness => _bgBrightness;
  double get bgBlur => _bgBlur;
  double get bgZoom => _bgZoom;
  int get bgRotation => _bgRotation;
  Color get bgMaskColor => Color(_bgMaskColor);
  double get bgMaskOpacity => _bgMaskOpacity;
  double get floatX => _floatX;
  double get floatY => _floatY;
  String get fontFile => _fontFile;
  bool get hasFont => _fontFile.isNotEmpty;
  Color? get fontColor => _fontColor == 0 ? null : Color(_fontColor);
  bool get dynWeight => _dynWeight;

  void setFont(String file) {
    _fontFile = file;
    notifyListeners();
    _save();
  }

  void setFontColor(Color? c) {
    _fontColor = c?.toARGB32() ?? 0;
    notifyListeners();
    _save();
  }

  void setDynWeight(bool v) {
    _dynWeight = v;
    notifyListeners();
    _save();
  }

  void setFloatPos(double x, double y) {
    _floatX = x;
    _floatY = y;
    notifyListeners();
    _save();
  }

  void setFloatingChrome(bool v) {
    _floatingChrome = v;
    notifyListeners();
    _save();
  }

  void setGlassEffect(bool v) {
    _glassEffect = v;
    notifyListeners();
    _save();
  }

  void setGlassMode(int v) {
    _glassMode = v.clamp(0, 2);
    notifyListeners();
    _save();
  }

  void setCornerRadiusValue(double v) {
    _cornerRadiusValue = v.clamp(0, 28);
    notifyListeners();
    _save();
  }

  void setMotionScale(double v) {
    _motionScale = v.clamp(0.0, 1.6);
    notifyListeners();
    _save();
  }

  void setGlassBlur(double v) {
    _glassBlur = v.clamp(0, 30);
    notifyListeners();
    _save();
  }

  void setGlassOpacity(double v) {
    _glassOpacity = v.clamp(0.2, 1.0);
    notifyListeners();
    _save();
  }

  void setBg({String? image}) {
    if (image != null) _bgImage = image;
    notifyListeners();
    _save();
    resolveBgPath();
  }

  void clearBg() {
    _bgImage = '';
    _bgPath = '';
    _bgProvider = null;
    _bgRaw?.dispose();
    _bgRaw = null;
    notifyListeners();
    _save();
  }

  void setBgEdit({
    double? brightness,
    double? blur,
    double? zoom,
    int? rotation,
    int? maskColor,
    double? maskOpacity,
  }) {
    if (brightness != null) _bgBrightness = brightness.clamp(0.4, 1.6);
    if (blur != null) _bgBlur = blur.clamp(0, 20);
    if (zoom != null) _bgZoom = zoom.clamp(1.0, 2.0);
    if (rotation != null) _bgRotation = rotation % 360;
    if (maskColor != null) _bgMaskColor = maskColor;
    if (maskOpacity != null) _bgMaskOpacity = maskOpacity.clamp(0.0, 0.9);
    notifyListeners();
    _save();
  }

  /// 从背景图里取一个代表色（要求 L109「从应用内自定义背景取色」）
  Future<Color?> colorFromBackground() async {
    if (_bgImage.isEmpty) return null;
    return averageColorOfBg(_bgImage);
  }

  void setSearchNumberPad(bool v) {
    _searchNumberPad = v;
    notifyListeners();
    _save();
  }

  void setDpiScale(double v) {
    _dpiScale = v.clamp(0.8, 1.4);
    notifyListeners();
    _save();
  }

  void setHaptics(bool v) {
    _haptics = v;
    notifyListeners();
    _save();
  }

  void setCornerStyle(int v) {
    _cornerStyle = v.clamp(0, 2);
    notifyListeners();
    _save();
  }

  void setStatsFloating(bool v) {
    _statsFloating = v;
    notifyListeners();
    _save();
  }

  void setStatsVisible(bool v) {
    _statsVisible = v;
    notifyListeners();
    _save();
  }

  // ---------- 卡牌自定义（批次 5） ----------
  final Map<String, CardOverride> _cardEdits = {};

  Map<String, CardOverride> get cardEdits => _cardEdits;
  CardOverride? cardEditOf(String code) => _cardEdits[code];

  /// 用户新建的卡
  List<CardOverride> get newCards =>
      _cardEdits.values.where((e) => e.isNew).toList();

  /// 所有自定义分类（按名字排序）
  List<String> get categories {
    final s = <String>{};
    for (final e in _cardEdits.values) {
      s.addAll(e.categories);
    }
    return s.toList()..sort();
  }

  void setCardEdit(CardOverride e) {
    if (e.isEmpty) {
      _cardEdits.remove(e.code);
    } else {
      _cardEdits[e.code] = e;
    }
    CardRepository.instance.setEdits(_cardEdits);
    notifyListeners();
    _save();
  }

  void clearCardEdit(String code) {
    _cardEdits.remove(code);
    CardRepository.instance.setEdits(_cardEdits);
    notifyListeners();
    _save();
  }

  /// 新建一张卡（自定义卡号）
  CardOverride createCustomCard(String code, String name) {
    final e = CardOverride(code: code, isNew: true, nameZh: name);
    setCardEdit(e);
    return e;
  }

  /// 改分类名（所有引用旧名的卡一起改）
  void renameCategory(String from, String to) {
    for (final e in _cardEdits.values) {
      final i = e.categories.indexOf(from);
      if (i >= 0) e.categories[i] = to;
    }
    CardRepository.instance.setEdits(_cardEdits);
    notifyListeners();
    _save();
  }

  /// 删掉一个分类（卡上的引用也去掉）
  void deleteCategory(String name) {
    for (final e in _cardEdits.values) {
      e.categories.remove(name);
    }
    CardRepository.instance.setEdits(_cardEdits);
    notifyListeners();
    _save();
  }

  /// 把卡丢进 / 移出某个分类
  void setCardCategory(String code, String name, bool on) {
    final e = _cardEdits[code] ?? CardOverride(code: code);
    on ? e.categories.add(name) : e.categories.remove(name);
    setCardEdit(e);
  }

  // ---------- 罕贵度角标（要求 55） ----------
  final Map<String, CollectInfo> _collect = {};
  final Map<String, RarityStyle> _rarityStyles = {};

  CollectInfo? collectInfoOf(String code) => _collect[code];

  /// 显示用的罕贵度：优先用户选的，否则官方数据
  String rarityOf(String code, String? official) {
    final r = _collect[code]?.rarity ?? '';
    return r.isNotEmpty ? r : (official ?? '');
  }

  bool isParallel(String code) => _collect[code]?.parallel ?? false;

  void setCollectInfo(String code, CollectInfo info) {
    if (info.isEmpty) {
      _collect.remove(code);
    } else {
      _collect[code] = info;
    }
    notifyListeners();
    _save();
  }

  /// 某个罕贵度的角标样式（没自定义过就给默认色）
  RarityStyle rarityStyle(String rarity) =>
      _rarityStyles[rarity] ??
      RarityStyle(color: defaultRarityColor(rarity));

  bool hasCustomRarityStyle(String rarity) => _rarityStyles.containsKey(rarity);

  void setRarityStyle(String rarity, RarityStyle style) {
    _rarityStyles[rarity] = style;
    notifyListeners();
    _save();
  }

  void resetRarityStyle(String rarity) {
    _rarityStyles.remove(rarity);
    notifyListeners();
    _save();
  }

  // ---------- 收藏 / 收集 ----------
  final Set<String> _favorites = {}; // 特殊卡面收藏
  final Set<String> _owned = {}; // 已收集
  final Map<String, int> _ownedQty = {}; // 每种持有几张（没记就是 1）

  /// 持有数量（没收集 = 0）
  int ownedQty(String code) => _owned.contains(code) ? (_ownedQty[code] ?? 1) : 0;

  void setOwnedQty(String code, int n) {
    if (n <= 0) {
      _ownedQty.remove(code);
    } else {
      _owned.add(code);
      _ownedQty[code] = n;
    }
    notifyListeners();
    _save();
  }

  bool isFavorite(String code) => _favorites.contains(code);
  bool isOwned(String code) => _owned.contains(code);
  Set<String> get owned => _owned;
  Set<String> get favorites => _favorites;

  // ---------- 构筑 ----------
  final List<Deck> _decks = [];
  List<Deck> get decks => List.unmodifiable(_decks);

  // ── 构筑分享 / 导入（要求 L67 / L69）──

  /// 把一个构筑打成分享码（只带构筑本身，不含胜负记录/快照/心得）
  String shareDeck(Deck deck) => DeckShare.encode(DeckData(
        name: deck.name,
        mainCardCode: deck.mainCardCode,
        formatIndex: deck.format.index,
        intro: deck.intro,
        cards: deck.cards,
        sideboard: deck.sideboard,
      ));

  /// 从分享码导入成一个**新**构筑；返回 null 表示码不合法
  Deck? importDeck(String code) {
    final d = DeckShare.decode(code);
    if (d == null) return null;
    return importDeckData(d);
  }

  /// 把一份已解析好的构筑数据落库成一个**新**构筑。
  ///
  /// 两套识别系统（自家 LYD1 分享码 / 官方卡组链接）解析完都走这里，
  /// 保证导入后的卡组行为完全一致。
  Deck? importDeckData(DeckData d) {
    if (d.cards.isEmpty && d.sideboard.isEmpty) return null;
    final deck = Deck(
      id: _newId('d'),
      name: d.name.isEmpty ? tr('导入的构筑') : d.name,
      mainCardCode: d.mainCardCode,
    );
    final fi = d.formatIndex;
    if (fi >= 0 && fi < DeckFormat.values.length) {
      deck.format = DeckFormat.values[fi];
    }
    deck.intro = d.intro;
    deck.cards.addAll(d.cards);
    deck.sideboard.addAll(d.sideboard);
    _decks.add(deck);
    notifyListeners();
    _save();
    return deck;
  }

  // ---------- 生命周期 ----------
  static Future<AppState> create() async {
    await _writeChain; // 等上一次写入完成，保证「先写后读」
    final prefs = await SharedPreferences.getInstance();
    final s = AppState(prefs);
    s._restore();
    return s;
  }

  /// 载入禁限卡表：官方表随包打包，用户自定义表来自 prefs（要求 L83-84）
  Future<void> initBanList() async {
    await BanList.instance.load();
    notifyListeners();
  }

  void _restoreCustomBan() {
    final raw = _prefs.getString('customBan');
    if (raw == null || raw.isEmpty) return;
    try {
      BanList.instance.applyCustom(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // 存坏了就当没有自定义限制，不影响启动
    }
  }

  /// 改自定义禁限表后调一次（存盘 + 通知界面刷新）
  void saveCustomBan() {
    notifyListeners();
    _save();
  }

  void _restore() {
    _themeMode = ThemeMode.values[_prefs.getInt('themeMode') ?? 0];
    _dynamicColor = _prefs.getBool('dynamicColor') ?? true;
    _seed = Color(_prefs.getInt('seed') ?? 0xFF3F7FBF);
    _gridColumns = _prefs.getInt('gridColumns') ?? 0;
    _useZh = _prefs.getBool('useZh') ?? true;
    _restoreCustomBan();
    _lang = appLangFrom(_prefs.getString('lang'));
    L10n.set(_lang); // 启动就套用，首帧就是所选语言
    _showEffectInGrid = _prefs.getBool('showEffectInGrid') ?? false;
    _expressiveCorners = _prefs.getBool('expressiveCorners') ?? false;
    // 底栏顺序改过（计算器插到检索和构筑之间），老存档里的下标要迁移一次。
    // 用标记位保证**只迁一次**：否则用户在新顺序下再存一次「构筑(2)」，
    // 下次启动会被当成旧值再迁一遍，又跳到「我的」去了。
    final int rawTab = _prefs.getInt('startTab') ?? 0;
    final bool migrated = _prefs.getBool('startTabV2') ?? false;
    _startTab = migrated ? rawTab.clamp(0, 3) : AppState.migrateStartTab(rawTab);
    _clipboardWatch = _prefs.getBool('clipboardWatch') ?? false;
    _searchNumberPad = _prefs.getBool('searchNumberPad') ?? true;
    _cornerStyle = _prefs.getInt('cornerStyle') ?? 1;
    _dpiScale = _prefs.getDouble('dpiScale') ?? 1.0;
    _haptics = _prefs.getBool('haptics') ?? true;
    _statsFloating = _prefs.getBool('statsFloating') ?? false;
    _floatingChrome = _prefs.getBool('floatingChrome') ?? false;
    _glassEffect = _prefs.getBool('glassEffect') ?? false;
    _glassBlur = _prefs.getDouble('glassBlur') ?? 14;
    _glassOpacity = _prefs.getDouble('glassOpacity') ?? 0.18;
    _glassMode = _prefs.getInt('glassMode') ?? 0;
    if (_glassMode == 0 && (_prefs.getBool('glassEffect') ?? false)) {
      _glassMode = 1; // 老版本只存了 bool，按高斯模糊恢复
    }
    _cornerRadiusValue = _prefs.getDouble('cornerRadiusValue') ?? 12;
    _motionScale = _prefs.getDouble('motionScale') ?? 1.0;
    _barBlur = _prefs.getDouble('barBlur');
    _barOpacity = _prefs.getDouble('barOpacity');
    _bgImage = _prefs.getString('bgImage') ?? '';
    _bgBrightness = _prefs.getDouble('bgBrightness') ?? 1.0;
    _bgBlur = _prefs.getDouble('bgBlur') ?? 0;
    _bgZoom = _prefs.getDouble('bgZoom') ?? 1.0;
    _bgRotation = _prefs.getInt('bgRotation') ?? 0;
    _bgMaskColor = _prefs.getInt('bgMaskColor') ?? 0xFF000000;
    _bgMaskOpacity = _prefs.getDouble('bgMaskOpacity') ?? 0.25;
    _floatX = _prefs.getDouble('floatX') ?? 8;
    _floatY = _prefs.getDouble('floatY') ?? 90;
    _fontFile = _prefs.getString('fontFile') ?? '';
    _fontColor = _prefs.getInt('fontColor') ?? 0;
    _dynWeight = _prefs.getBool('dynWeight') ?? true;
    _statsVisible = _prefs.getBool('statsVisible') ?? true;

    try {
      _cardEdits
        ..clear()
        ..addAll((jsonDecode(_prefs.getString('cardEdits') ?? '{}') as Map)
            .map((k, v) => MapEntry(
                '$k', CardOverride.fromJson(v as Map<String, dynamic>))));
    } catch (_) {}

    try {
      _collect
        ..clear()
        ..addAll((jsonDecode(_prefs.getString('collect') ?? '{}') as Map)
            .map((k, v) => MapEntry(
                '$k', CollectInfo.fromJson(v as Map<String, dynamic>))));
      _rarityStyles
        ..clear()
        ..addAll((jsonDecode(_prefs.getString('rarityStyles') ?? '{}') as Map)
            .map((k, v) => MapEntry('$k',
                RarityStyle.fromJson(v as Map<String, dynamic>, defaultRarityColor('$k')))));
    } catch (_) {}

    try {
      _ownedQty
        ..clear()
        ..addAll((jsonDecode(_prefs.getString('ownedQty') ?? '{}') as Map)
            .map((k, v) => MapEntry('$k', (v as num).toInt())));
    } catch (_) {}

    try {
      _wish
        ..clear()
        ..addAll((jsonDecode(_prefs.getString('wish') ?? '[]') as List)
            .map((e) => WishCard.fromJson(e as Map<String, dynamic>)));
    } catch (_) {}
    _valueUnit = _prefs.getString('valueUnit') ?? 'CNY';
    _valueHidden = _prefs.getBool('valueHidden') ?? true;
    _ownedInfo
      ..clear()
      ..addAll(((jsonDecode(_prefs.getString('ownedInfo') ?? '{}'))
              as Map<String, dynamic>)
          .map((k, v) =>
              MapEntry(k, OwnedInfo.fromJson(v as Map<String, dynamic>))));

    _favorites
      ..clear()
      ..addAll(_prefs.getStringList('favorites') ?? const []);
    _owned
      ..clear()
      ..addAll(_prefs.getStringList('owned') ?? const []);

    final raw = _prefs.getString('decks');
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _decks
          ..clear()
          ..addAll(list.map((e) => Deck.fromJson(e as Map<String, dynamic>)));
      } catch (_) {}
    }
    if (_decks.isEmpty && !(_prefs.getBool('deckSeeded') ?? false)) {
      _decks.add(Deck(id: 'd1', name: tr('范例构筑'), mainCardCode: ''));
      _prefs.setBool('deckSeeded', true);
    }
  }

  /// 写入串行化：保证「先写、后读」的顺序（create() 会等上一次写完）
  static Future<void> _writeChain = Future.value();

  Future<void> _save() {
    final next = _writeChain.then((_) => _saveNow());
    _writeChain = next.catchError((_) {});
    return next;
  }

  Future<void> _saveNow() async {
    await _prefs.setInt('themeMode', _themeMode.index);
    await _prefs.setBool('dynamicColor', _dynamicColor);
    await _prefs.setInt('seed', _seed.toARGB32());
    await _prefs.setInt('gridColumns', _gridColumns);
    await _prefs.setBool('useZh', _useZh);
    await _prefs.setString('lang', _lang.code);
    await _prefs.setBool('showEffectInGrid', _showEffectInGrid);
    await _prefs.setBool('expressiveCorners', _expressiveCorners);
    await _prefs.setInt('startTab', _startTab);
    // 记下「已按新顺序存过」，下次启动不再迁移
    await _prefs.setBool('startTabV2', true);
    await _prefs.setBool('clipboardWatch', _clipboardWatch);
    await _prefs.setBool('searchNumberPad', _searchNumberPad);
    await _prefs.setInt('cornerStyle', _cornerStyle);
    await _prefs.setDouble('dpiScale', _dpiScale);
    await _prefs.setBool('haptics', _haptics);
    await _prefs.setBool('statsFloating', _statsFloating);
    await _prefs.setBool('floatingChrome', _floatingChrome);
    await _prefs.setBool('glassEffect', _glassEffect);
    await _prefs.setDouble('glassBlur', _glassBlur);
    await _prefs.setDouble('glassOpacity', _glassOpacity);
    await _prefs.setInt('glassMode', _glassMode);
    await _prefs.setDouble('cornerRadiusValue', _cornerRadiusValue);
    await _prefs.setDouble('motionScale', _motionScale);
    if (_barBlur != null) await _prefs.setDouble('barBlur', _barBlur!);
    if (_barOpacity != null) await _prefs.setDouble('barOpacity', _barOpacity!);
    await _prefs.setString('bgImage', _bgImage);
    await _prefs.setDouble('bgBrightness', _bgBrightness);
    await _prefs.setDouble('bgBlur', _bgBlur);
    await _prefs.setDouble('bgZoom', _bgZoom);
    await _prefs.setInt('bgRotation', _bgRotation);
    await _prefs.setInt('bgMaskColor', _bgMaskColor);
    await _prefs.setDouble('bgMaskOpacity', _bgMaskOpacity);
    await _prefs.setDouble('floatX', _floatX);
    await _prefs.setDouble('floatY', _floatY);
    await _prefs.setString('fontFile', _fontFile);
    await _prefs.setInt('fontColor', _fontColor);
    await _prefs.setBool('dynWeight', _dynWeight);
    await _prefs.setBool('statsVisible', _statsVisible);
    await _prefs.setString('valueUnit', _valueUnit);
    await _prefs.setString('wish', jsonEncode(_wish.map((w) => w.toJson()).toList()));
    await _prefs.setString('ownedQty', jsonEncode(_ownedQty));
    await _prefs.setString('cardEdits',
        jsonEncode(_cardEdits.map((k, v) => MapEntry(k, v.toJson()))));
    await _prefs.setString('collect',
        jsonEncode(_collect.map((k, v) => MapEntry(k, v.toJson()))));
    await _prefs.setString('rarityStyles',
        jsonEncode(_rarityStyles.map((k, v) => MapEntry(k, v.toJson()))));
    await _prefs.setBool('valueHidden', _valueHidden);
    await _prefs.setString('ownedInfo',
        jsonEncode(_ownedInfo.map((k, v) => MapEntry(k, v.toJson()))));
    await _prefs.setStringList('favorites', _favorites.toList());
    await _prefs.setStringList('owned', _owned.toList());
    await _prefs.setString(
        'decks', jsonEncode(_decks.map((d) => d.toJson()).toList()));
  }

  // ---------- 设置操作 ----------
  void setThemeMode(ThemeMode m) {
    _themeMode = m;
    notifyListeners();
    _save();
  }
  /// 切换界面语言（要求 L103）
  void setLang(AppLang l) {
    _lang = l;
    L10n.set(l);
    notifyListeners();
    _save();
  }


  void setDynamicColor(bool v) {
    _dynamicColor = v;
    notifyListeners();
    _save();
  }

  void setSeed(Color c) {
    _seed = c;
    notifyListeners();
    _save();
  }

  void setGridColumns(int n) {
    _gridColumns = n;
    notifyListeners();
    _save();
  }

  void setUseZh(bool v) {
    _useZh = v;
    notifyListeners();
    _save();
  }

  void setShowEffectInGrid(bool v) {
    _showEffectInGrid = v;
    notifyListeners();
    _save();
  }

  void setExpressiveCorners(bool v) {
    _expressiveCorners = v;
    notifyListeners();
    _save();
  }

  void setStartTab(int v) {
    _startTab = v;
    notifyListeners();
    _save();
  }

  /// 底栏栏位：0 检索 / 1 计算器 / 2 构筑 / 3 我的
  ///
  /// 历史数据里旧顺序是「检索(0) / 构筑(1) / 我的(2)」，读盘时做一次迁移，
  /// 否则老用户存的「构筑」会在新顺序下变成计算器。
  static int migrateStartTab(int old) {
    switch (old) {
      case 1:
        return 2; // 旧「构筑」→ 新「构筑」
      case 2:
        return 3; // 旧「我的」→ 新「我的」
      default:
        return old.clamp(0, 3); // 0 检索；其余（含新值 1/3）原样
    }
  }

  // ---------- 入库价值（批次 2） ----------
  final Map<String, OwnedInfo> _ownedInfo = {};

  OwnedInfo? infoOf(String code) => _ownedInfo[code];

  void setOwnedInfo(String code, OwnedInfo? info) {
    if (info == null) {
      _ownedInfo.remove(code);
    } else {
      _ownedInfo[code] = info;
    }
    notifyListeners();
    _save();
  }

  String get valueUnit => _valueUnit;
  bool get valueHidden => _valueHidden;

  void setValueUnit(String u) {
    _valueUnit = u;
    notifyListeners();
    _save();
  }

  void setValueHidden(bool v) {
    _valueHidden = v;
    notifyListeners();
    _save();
  }

  /// 已收集且填了价格的卡的总价值（人民币）
  double get totalValueCny {
    var sum = 0.0;
    for (final code in _owned) {
      final v = _ownedInfo[code]?.valueCny;
      if (v != null) sum += v;
    }
    return sum;
  }

  /// 填过价格的张数
  int get pricedCount =>
      _owned.where((c) => _ownedInfo[c]?.price != null).length;

  /// 按当前显示单位折算
  double get totalValueInUnit =>
      totalValueCny / (kDefaultRates[_valueUnit] ?? 1.0);

  static const Map<String, String> currencySymbols = {
    'CNY': '¥',
    'JPY': '¥',
    'USD': r'$',
    'EUR': '€',
    'HKD': 'HK\$',
    'TWD': 'NT\$',
    'KRW': '₩',
    'GBP': '£',
  };

  String get valueSymbol => currencySymbols[_valueUnit] ?? '';

  /// 大字里显示的价值文本（隐藏时返回 ••••）
  String get valueText => _valueHidden
      ? '••••••'
      : '$valueSymbol${totalValueInUnit.toStringAsFixed(2)}';

  // ---------- 收藏 / 收集 ----------
  void toggleFavorite(String code) {
    _favorites.contains(code) ? _favorites.remove(code) : _favorites.add(code);
    notifyListeners();
    _save();
  }

  /// 导出的备份（含所有用户自定义信息）
  Map<String, dynamic> exportData() => {
        'app': 'lycard',
        'format': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'decks': _decks.map((d) => d.toJson()).toList(),
        'favorites': _favorites.toList(),
        'owned': _owned.toList(),
        'ownedQty': _ownedQty,
        'wish': _wish.map((w) => w.toJson()).toList(),
        'cardEdits':
            _cardEdits.map((k, v) => MapEntry(k, v.toJson())),
        'collect': _collect.map((k, v) => MapEntry(k, v.toJson())),
        'appearance': {
          'floatingChrome': _floatingChrome,
          'glassEffect': _glassEffect,
          'glassBlur': _glassBlur,
          'glassOpacity': _glassOpacity,
          'bgImage': _bgImage,
          'bgBrightness': _bgBrightness,
          'bgBlur': _bgBlur,
          'bgZoom': _bgZoom,
          'bgRotation': _bgRotation,
          'bgMaskColor': _bgMaskColor,
          'bgMaskOpacity': _bgMaskOpacity,
        },
        'rarityStyles':
            _rarityStyles.map((k, v) => MapEntry(k, v.toJson())),
        'ownedInfo': _ownedInfo.map((k, v) => MapEntry(k, v.toJson())),
        'settings': {
          'themeMode': _themeMode.index,
          'dynamicColor': _dynamicColor,
          'seed': _seed.toARGB32(),
          'gridColumns': _gridColumns,
          'useZh': _useZh,
          'lang': _lang.code,
          'customBan': BanList.instance.exportCustom(),
          'showEffectInGrid': _showEffectInGrid,
          'expressiveCorners': _expressiveCorners,
          'startTab': _startTab,
          'valueUnit': _valueUnit,
          'valueHidden': _valueHidden,
        },
      };

  /// 从备份恢复。[merge] = true 时与现有数据合并，否则先清空再写入。
  String importData(Map<String, dynamic> j, {bool merge = false}) {
    if ('${j['app']}' != 'lycard') {
      throw FormatException(tr('这不是 lycard 的备份文件'));
    }
    if (!merge) {
      _decks.clear();
      _favorites.clear();
      _owned.clear();
      _ownedInfo.clear();
      _ownedQty.clear();
      _wish.clear();
    }

    var deckN = 0;
    for (final d in (j['decks'] as List? ?? const [])) {
      final deck = Deck.fromJson(d as Map<String, dynamic>);
      _decks.removeWhere((x) => x.id == deck.id);
      _decks.add(deck);
      deckN++;
    }
    _favorites.addAll((j['favorites'] as List? ?? const []).map((e) => '$e'));
    _owned.addAll((j['owned'] as List? ?? const []).map((e) => '$e'));
    (j['ownedQty'] as Map?)?.forEach((k, v) {
      if (v is num) _ownedQty['$k'] = v.toInt();
    });
    for (final w in (j['wish'] as List? ?? const [])) {
      final x = WishCard.fromJson(w as Map<String, dynamic>);
      _wish.removeWhere((e) => e.id == x.id);
      _wish.add(x);
    }
    (j['ownedInfo'] as Map?)?.forEach((k, v) {
      _ownedInfo['$k'] = OwnedInfo.fromJson(v as Map<String, dynamic>);
    });
    (j['cardEdits'] as Map?)?.forEach((k, v) {
      _cardEdits['$k'] = CardOverride.fromJson(v as Map<String, dynamic>);
    });
    (j['collect'] as Map?)?.forEach((k, v) {
      _collect['$k'] = CollectInfo.fromJson(v as Map<String, dynamic>);
    });
    final ap = j['appearance'] as Map<String, dynamic>?;
    if (ap != null) {
      _floatingChrome = ap['floatingChrome'] as bool? ?? _floatingChrome;
      _glassEffect = ap['glassEffect'] as bool? ?? _glassEffect;
      _glassBlur = (ap['glassBlur'] as num?)?.toDouble() ?? _glassBlur;
      _glassOpacity = (ap['glassOpacity'] as num?)?.toDouble() ?? _glassOpacity;
      _bgImage = '${ap['bgImage'] ?? _bgImage}';
      _bgBrightness = (ap['bgBrightness'] as num?)?.toDouble() ?? _bgBrightness;
      _bgBlur = (ap['bgBlur'] as num?)?.toDouble() ?? _bgBlur;
      _bgZoom = (ap['bgZoom'] as num?)?.toDouble() ?? _bgZoom;
      _bgRotation = (ap['bgRotation'] as num?)?.toInt() ?? _bgRotation;
      _bgMaskColor = (ap['bgMaskColor'] as num?)?.toInt() ?? _bgMaskColor;
      _bgMaskOpacity =
          (ap['bgMaskOpacity'] as num?)?.toDouble() ?? _bgMaskOpacity;
    }
    (j['rarityStyles'] as Map?)?.forEach((k, v) {
      _rarityStyles['$k'] =
          RarityStyle.fromJson(v as Map<String, dynamic>, defaultRarityColor('$k'));
    });
    CardRepository.instance.setEdits(_cardEdits);

    final s = j['settings'] as Map<String, dynamic>?;
    if (s != null) {
      _themeMode = ThemeMode.values[
          (s['themeMode'] as int? ?? 0).clamp(0, ThemeMode.values.length - 1)];
      _dynamicColor = s['dynamicColor'] as bool? ?? _dynamicColor;
      _seed = Color((s['seed'] as int?) ?? _seed.toARGB32());
      _gridColumns = s['gridColumns'] as int? ?? _gridColumns;
      _useZh = s['useZh'] as bool? ?? _useZh;
      setLang(appLangFrom('${s['lang']}'));
      final cb = s['customBan'];
      if (cb is Map) {
        BanList.instance.applyCustom(Map<String, dynamic>.from(cb));
      }
      _showEffectInGrid = s['showEffectInGrid'] as bool? ?? _showEffectInGrid;
      _expressiveCorners =
          s['expressiveCorners'] as bool? ?? _expressiveCorners;
      _startTab = s['startTab'] as int? ?? _startTab;
      _valueUnit = '${s['valueUnit'] ?? _valueUnit}';
      _valueHidden = s['valueHidden'] as bool? ?? _valueHidden;
    }

    notifyListeners();
    _save();
    return tr('构筑 {0} 套 · 收藏 {1} 张 · 已收集 {2} 张 · 入库信息 {3} 条', [deckN, _favorites.length, _owned.length, _ownedInfo.length]);
  }

  void toggleOwned(String code) {
    _owned.contains(code) ? _owned.remove(code) : _owned.add(code);
    if (!_owned.contains(code)) _ownedQty.remove(code);
    notifyListeners();
    _save();
  }

  // ---------- 想要 / 出卡 / 缺卡 ----------
  final List<WishCard> _wish = [];

  /// 自增序号：光用时间戳在同一个微秒内会撞号（测试里尤其明显）
  static int _idSeq = 0;
  static String _newId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  List<WishCard> get wantList =>
      _wish.where((w) => w.kind == WishKind.want).toList();
  List<WishCard> get sellList =>
      _wish.where((w) => w.kind == WishKind.sell).toList();

  WishCard addWish(String code,
      {WishKind kind = WishKind.want, double? price, String currency = 'CNY'}) {
    final w = WishCard(
      id: _newId('w'),
      code: code,
      kind: kind,
      price: price,
      currency: currency,
    );
    _wish.add(w);
    notifyListeners();
    _save();
    return w;
  }

  void updateWish(WishCard w) {
    final i = _wish.indexWhere((x) => x.id == w.id);
    if (i >= 0) _wish[i] = w;
    notifyListeners();
    _save();
  }

  void removeWish(String id) {
    _wish.removeWhere((x) => x.id == id);
    notifyListeners();
    _save();
  }

  bool isWanted(String code) =>
      _wish.any((w) => w.kind == WishKind.want && w.code == code);

  /// 某套构筑里缺的卡：[卡号, 需要, 持有]
  List<(String code, int need, int have)> missingOf(Deck d) {
    final out = <(String, int, int)>[];
    d.cards.forEach((code, need) {
      final have = ownedQty(code);
      if (have < need) out.add((code, need, have));
    });
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  /// 想要清单的预计补齐成本（折算成 CNY）；有卡没填价 → null（界面显示 -）
  double? get wantTotalCost {
    var sum = 0.0;
    for (final w in _wish.where((w) => w.kind == WishKind.want)) {
      final p = w.price;
      if (p == null) return null;
      sum += p * (kDefaultRates[w.currency] ?? 1.0);
    }
    return sum;
  }

  /// 多套构筑共用同一张卡、但实物不够 → 冲突的卡号
  List<String> get conflictCodes {
    final need = <String, int>{};
    for (final d in _decks) {
      d.cards.forEach((code, n) => need[code] = (need[code] ?? 0) + n);
    }
    return need.entries
        .where((e) => ownedQty(e.key) < e.value)
        .map((e) => e.key)
        .toList()
      ..sort();
  }

  /// 某张卡被哪些构筑需要（用于提示冲突）
  List<String> decksUsing(String code) =>
      _decks.where((d) => d.cards.containsKey(code)).map((d) => d.name).toList();

  /// 这套构筑缺的卡，按「想要」里填的价格估算补齐成本；有卡没填价 → null
  double? missingCostOf(Deck d) {
    var sum = 0.0;
    for (final m in missingOf(d)) {
      final w = _wish.firstWhere(
          (x) => x.kind == WishKind.want && x.code == m.$1,
          orElse: () => WishCard(id: '', code: ''));
      final p = w.price;
      if (p == null) return null;
      sum += p * (kDefaultRates[w.currency] ?? 1.0);
    }
    return sum;
  }

  /// 把（选中的）缺卡加进「想要」，返回真正加了几张
  int addMissingToWant(Deck d, List<String> codes) {
    final missing = missingOf(d);
    var n = 0;
    for (final code in codes) {
      final m = missing.where((e) => e.$1 == code).toList();
      if (m.isEmpty) continue;
      if (isWanted(code)) continue;
      final lack = m.first.$2 - m.first.$3;
      final w = addWish(code);
      w.note = tr('构筑「{0}」还缺 {1} 张', [d.name, lack]);
      updateWish(w);
      n++;
    }
    return n;
  }

  // ---------- 构筑编辑 ----------
  /// 简介（细体小字）
  void setIntro(Deck d, String text) {
    d.intro = text;
    notifyListeners();
    _save();
  }

  void addBattle(Deck d, {required bool win, String memo = '', String opponent = ''}) {
    d.battles.insert(
      0,
      BattleRecord(id: _newId('b'), win: win, memo: memo, opponent: opponent),
    );
    notifyListeners();
    _save();
  }

  void removeBattle(Deck d, String id) {
    d.battles.removeWhere((b) => b.id == id);
    notifyListeners();
    _save();
  }

  void toggleMvp(Deck d, String code) {
    d.mvpCodes.contains(code) ? d.mvpCodes.remove(code) : d.mvpCodes.add(code);
    notifyListeners();
    _save();
  }

  void setCardNote(Deck d, String code, String text) {
    if (text.trim().isEmpty) {
      d.cardNotes.remove(code);
    } else {
      d.cardNotes[code] = text.trim();
    }
    notifyListeners();
    _save();
  }

  /// 主卡组 → 备卡区（上限 10 张）
  void moveToSideboard(Deck d, String code, [int n = 1]) {
    final have = d.cards[code] ?? 0;
    final room = Deck.maxSideboard - d.sideTotal;
    final move = [have, n, room].reduce((a, b) => a < b ? a : b);
    if (move <= 0) return;
    d.cards[code] = have - move;
    if (d.cards[code] == 0) d.cards.remove(code);
    d.sideboard[code] = (d.sideboard[code] ?? 0) + move;
    notifyListeners();
    _save();
  }

  /// 备卡区 → 主卡组
  void moveToMain(Deck d, String code, [int n = 1]) {
    final have = d.sideboard[code] ?? 0;
    final move = [have, n].reduce((a, b) => a < b ? a : b);
    if (move <= 0) return;
    d.sideboard[code] = have - move;
    if (d.sideboard[code] == 0) d.sideboard.remove(code);
    d.cards[code] = (d.cards[code] ?? 0) + move;
    notifyListeners();
    _save();
  }

  /// 存一个版本快照
  DeckSnapshot saveSnapshot(Deck d, String label) {
    final s = d.snapshotAs(label);
    d.snapshots.insert(0, s);
    notifyListeners();
    _save();
    return s;
  }

  /// 回滚到某个快照（连该版本的胜负记录一起带回来）
  void rollbackSnapshot(Deck d, String id) {
    final s = d.snapshots.where((x) => x.id == id).toList();
    if (s.isEmpty) return;
    d.applySnapshot(s.first);
    notifyListeners();
    _save();
  }

  void deleteSnapshot(Deck d, String id) {
    d.snapshots.removeWhere((s) => s.id == id);
    notifyListeners();
    _save();
  }

  Deck createDeck(String name) {
    final d = Deck(
        id: _newId('d'), name: name, mainCardCode: '');
    _decks.add(d);
    notifyListeners();
    _save();
    return d;
  }

  void deleteDeck(String id) {
    _decks.removeWhere((d) => d.id == id);
    notifyListeners();
    _save();
  }

  /// 重命名构筑
  void renameDeck(Deck d, String name) {
    d.name = name;
    notifyListeners();
    _save();
  }

  /// 设置构筑封面（空字符串 = 交给「主战卡 → 第一张卡」兜底）
  void setDeckCover(Deck d, String code) {
    d.coverCode = code;
    notifyListeners();
    _save();
  }

  void setDeckMain(Deck d, String code) {
    d.mainCardCode = code;
    notifyListeners();
    _save();
  }

  void addCard(Deck d, LyceeCard c, [int n = 1]) {
    d.cards[c.code] = (d.cards[c.code] ?? 0) + n;
    notifyListeners();
    _save();
  }

  void removeCard(Deck d, String code, [int n = 1]) {
    final cur = d.cards[code] ?? 0;
    if (cur - n <= 0) {
      d.cards.remove(code);
    } else {
      d.cards[code] = cur - n;
    }
    notifyListeners();
    _save();
  }

  /// 自动检测构筑是否符合规则（按这套牌选的规则模式走）
  List<DeckIssue> checkDeck(Deck d) {
    final issues = <DeckIssue>[];
    final total = d.total;
    final fmt = d.format;
    final needSize = DeckRules.mainSizeFor(fmt);
    final maxCopies = DeckRules.maxCopiesFor(fmt);
    final maxSide = DeckRules.maxSideFor(fmt);

    if (total == 0) {
      issues.add(DeckIssue(IssueLevel.error, tr('卡组是空的')));
      return issues;
    }

    // 规则 1：张数（60 / 限定赛 30）
    if (total != needSize) {
      final diff = needSize - total;
      issues.add(DeckIssue(
        IssueLevel.error,
        '卡组共 $total 张，应为 $needSize 张'
        '（${diff > 0 ? '还差 $diff 张' : '超出 ${-diff} 张'}）',
      ));
    }

    // 规则 2：相同编号最多 4 张（主卡组 + 备卡区联动计算）
    final combined = <String, int>{};
    d.cards.forEach((k, v) => combined[k] = (combined[k] ?? 0) + v);
    d.sideboard.forEach((k, v) => combined[k] = (combined[k] ?? 0) + v);
    combined.forEach((code, n) {
      if (n > maxCopies) {
        final m = d.cards[code] ?? 0;
        final s = d.sideboard[code] ?? 0;
        issues.add(DeckIssue(
          IssueLevel.error,
          tr('{0} 主卡 {1} + 备卡 {2} = {3} 张，相同编号上限 {4} 张', [code, m, s, n, maxCopies]),
        ));
      }
    });

    // 备卡区：0~10 张（限定赛不能带）
    if (d.sideTotal > maxSide) {
      issues.add(DeckIssue(
        IssueLevel.error,
        maxSide == 0
            ? tr('{0}不能带备卡区（现在有 {1} 张）', [kFormatName[fmt], d.sideTotal])
            : tr('备卡区 {0} 张，上限 {1} 张', [d.sideTotal, maxSide]),
      ));
    }

    // ── 规则模式特有的校验 ──
    if (fmt == DeckFormat.neoClassic) {
      final series = <String>{};
      for (final code in d.cards.keys) {
        final s = CardRepository.instance.byCode(code)?.series;
        if (s != null && s.trim().isNotEmpty) series.add(s.trim());
      }
      if (d.mainCardCode.isNotEmpty) {
        final s = CardRepository.instance.byCode(d.mainCardCode)?.series;
        if (s != null && s.trim().isNotEmpty) series.add(s.trim());
      }
      if (series.length > 1) {
        issues.add(DeckIssue(
          IssueLevel.error,
          '单作品构筑：主卡组里出现了 ${series.length} 个作品（${series.join('、')}）',
        ));
      }
    }

    if (fmt == DeckFormat.hybrid) {
      final colors = <String>{};
      for (final code in d.cards.keys) {
        final c = CardRepository.instance.byCode(code)?.color;
        if (c == null || c.trim().isEmpty) continue;
        // 多色卡（雪月花…）按每个字拆开算
        for (final ch in c.split('')) {
          if (ch.trim().isNotEmpty) colors.add(ch);
        }
      }
      if (colors.length > DeckRules.hybridMaxColors) {
        issues.add(DeckIssue(
          IssueLevel.error,
          '混合属性构筑：主卡组用了 ${colors.length} 种属性'
          '（${(colors.toList()..sort()).join('、')}），最多 ${DeckRules.hybridMaxColors} 种',
        ));
      } else if (colors.isNotEmpty) {
        issues.add(DeckIssue(IssueLevel.ok,
            '属性：${(colors.toList()..sort()).join('、')}（上限 ${DeckRules.hybridMaxColors} 种）'));
      }
    }

    // 规则 4：leader 卡最多 1 张
    final leaders = <String>[];
    d.cards.forEach((code, n) {
      final c = CardRepository.instance.byCode(code);
      if (c != null && c.isLeader && n > 0) leaders.add(code);
    });
    if (d.mainCardCode.isNotEmpty && !leaders.contains(d.mainCardCode)) {
      final c = CardRepository.instance.byCode(d.mainCardCode);
      if (c != null && c.isLeader) leaders.add(d.mainCardCode);
    }
    if (leaders.length > DeckRules.maxLeader) {
      issues.add(DeckIssue(IssueLevel.error,
          'leader 卡有 ${leaders.length} 张（${leaders.join('、')}），上限 ${DeckRules.maxLeader} 张'));
    } else if (leaders.isEmpty) {
      issues.add(DeckIssue(IssueLevel.warning, tr('还没有 leader 卡'),
          key: 'no-leader'));
    }

    // 规则 3：卡片自带的构筑限制（主卡组 + 备卡区一起看）
    final allCodes = <String>{...d.cards.keys, ...d.sideboard.keys};
    for (final code in allCodes) {
      final c = CardRepository.instance.byCode(code);
      final r = c?.deckRestriction;
      if (r != null && r.trim().isNotEmpty) {
        issues.add(DeckIssue(IssueLevel.warning, tr('{0} 带有构筑限制：{1}', [code, r]),
            key: 'restriction:$code'));
      }
    }

    // 规则 6：官方禁限卡表（要求 L83-84）
    final ban = BanList.instance;
    if (ban.loaded && !ban.isEmpty) {
      // 6a 使用禁止 —— 硬性错误
      final banned = allCodes.where(ban.isForbidden).toList()..sort();
      for (final code in banned) {
        final nm = CardRepository.instance.byCode(code)?.displayName ?? code;
        issues.add(DeckIssue(
          IssueLevel.error,
          tr('「{0}」（{1}）在官方禁用卡表里，不能放入任何卡组', [nm, code]),
          key: 'ban:$code',
        ));
      }

      // 6b 张数限制 —— 硬性错误
      ban.allCopyLimited.forEach((code, limit) {
        final n = (d.cards[code] ?? 0) + (d.sideboard[code] ?? 0);
        if (n > limit) {
          final nm = CardRepository.instance.byCode(code)?.displayName ?? code;
          issues.add(DeckIssue(
            IssueLevel.error,
            tr('「{0}」（{1}）最多 {2} 张，现在有 {3} 张', [nm, code, limit, n]),
            key: 'copylimit:$code',
          ));
        }
      });

      // 6c 构筑限制卡：官方规定这类卡**只能放在单一会社构成的卡组**里。
      // 所以一旦卡组里有它，其余所有卡必须同会社。
      final limited = ban.limitedCardsIn(allCodes);
      if (limited.isNotEmpty) {
        final brands = <String, List<String>>{};
        for (final code in allCodes) {
          final c = CardRepository.instance.byCode(code);
          if (c == null) continue;
          (brands[c.brandTag] ??= []).add(code);
        }
        if (brands.length > 1) {
          final names = limited
              .map((c) => CardRepository.instance.byCode(c)?.displayName ?? c)
              .take(2)
              .join('、');
          final mix = (brands.keys.toList()..sort()).join('、');
          issues.add(DeckIssue(
            IssueLevel.error,
            tr('「{0}」等 {1} 张是构筑限制卡，只能用在单一会社的卡组里，当前混了 {2}', [names, limited.length, mix]),
            key: 'construction-limited',
          ));
        }
      }
    }

    if (!issues.any((i) => i.level == IssueLevel.error)) {
      issues.add(DeckIssue(
          IssueLevel.ok, tr('构筑合法 ✓（{0}）', [kFormatName[fmt]])));
    }

    // 软性提示（warning）可以被手动忽略
    final kept = <DeckIssue>[];
    var ignored = 0;
    for (final i in issues) {
      if (i.level == IssueLevel.warning &&
          d.ignoredWarnings.contains(i.message)) {
        ignored++;
        continue;
      }
      kept.add(i);
    }
    if (ignored > 0) {
      kept.add(DeckIssue(IssueLevel.ok, tr('已忽略 {0} 条软性提示', [ignored])));
    }
    return kept;
  }

  /// 缺卡提醒的显示开关
  void setHideMissing(Deck d, bool v) {
    d.hideMissing = v;
    notifyListeners();
    _save();
  }

  /// 忽略一条软性提示（可手动恢复）
  void ignoreWarning(Deck d, String message) {
    if (d.ignoredWarnings.contains(message)) return;
    d.ignoredWarnings.add(message);
    notifyListeners();
    _save();
  }

  /// 恢复全部被忽略的软性提示
  void clearIgnoredWarnings(Deck d) {
    d.ignoredWarnings.clear();
    notifyListeners();
    _save();
  }

  /// 按严重程度分组（界面用）
  ({List<DeckIssue> errors, List<DeckIssue> warnings, List<DeckIssue> oks})
      groupedIssues(Deck d) {
    final all = checkDeck(d);
    return (
      errors: all.where((i) => i.level == IssueLevel.error).toList(),
      warnings: all.where((i) => i.level == IssueLevel.warning).toList(),
      oks: all.where((i) => i.level == IssueLevel.ok).toList(),
    );
  }

  /// 切换规则模式
  void setDeckFormat(Deck d, DeckFormat f) {
    d.format = f;
    notifyListeners();
    _save();
  }
}
