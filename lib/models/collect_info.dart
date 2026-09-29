import 'dart:ui';

/// 我收集到的这张卡是哪个罕贵度 / 是不是异画
class CollectInfo {
  CollectInfo({this.rarity = '', this.parallel = false});

  /// 选定的罕贵度（空 = 用官方数据里的）
  String rarity;

  /// 异画（平行闪）
  bool parallel;

  bool get isEmpty => rarity.isEmpty && !parallel;

  Map<String, dynamic> toJson() => {
        if (rarity.isNotEmpty) 'rarity': rarity,
        if (parallel) 'parallel': true,
      };

  static CollectInfo fromJson(Map<String, dynamic> j) => CollectInfo(
        rarity: '${j['rarity'] ?? ''}',
        parallel: j['parallel'] == true,
      );
}

/// 某个罕贵度的角标样式（颜色 / 模糊 / 透明度），都能在设置里改
class RarityStyle {
  RarityStyle({required this.color, this.blur = 0, this.opacity = 0.85});

  Color color;
  double blur; // 0~12，越大越糊（做发光/虚化效果）
  double opacity; // 0.1~1

  Color get effective =>
      color.withValues(alpha: color.a * opacity);

  Map<String, dynamic> toJson() => {
        'color': color.toARGB32(),
        'blur': blur,
        'opacity': opacity,
      };

  static RarityStyle fromJson(Map<String, dynamic> j, Color fallback) =>
      RarityStyle(
        color: Color((j['color'] as int?) ?? fallback.toARGB32()),
        blur: (j['blur'] as num?)?.toDouble() ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 0.85,
      );
}

/// 默认的罕贵度配色（都能在设置里改）
const Map<String, Color> kDefaultRarityColors = {
  'C': Color(0xFF9E9E9E),
  'P': Color(0xFF7CB342),
  'U': Color(0xFF29B6F6),
  'R': Color(0xFF5C6BC0),
  'KR': Color(0xFFFFA726),
  'SR': Color(0xFFFFCA28),
  'SP': Color(0xFFAB47BC),
  'SSP': Color(0xFFEC407A),
  'ST': Color(0xFF26A69A),
  'L': Color(0xFFEF5350),
  'KC': Color(0xFF8D6E63),
  'CP': Color(0xFF66BB6A),
  'KSR': Color(0xFFFF7043),
  'ER': Color(0xFF42A5F5),
};

Color defaultRarityColor(String rarity) =>
    kDefaultRarityColors[rarity] ?? const Color(0xFF607D8B);
