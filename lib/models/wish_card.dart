import 'dart:convert';
import '../l10n/l10n.dart';

/// 想要 / 出卡
enum WishKind {
  want, // 想要（想买）
  sell, // 出卡（想卖）
}

WishKind wishKindFrom(String? s) =>
    s == 'sell' ? WishKind.sell : WishKind.want;

String wishKindName(WishKind k) => k == WishKind.sell ? tr('出卡') : tr('想要');

/// 常见的品相预设（还可以自己加细化标签）
List<String> kConditionPresets = ['S', 'A', 'B', 'C', 'D'];

/// 细化标签的建议词（用户可以随便加）
List<String> kTagSuggestions = [
  tr('未拆封'),
  tr('未打比赛'),
  tr('轻微白边'),
  tr('压痕'),
  tr('折痕'),
  tr('签名板'),
  tr('角损'),
  tr('已使用'),
  tr('带卡套'),
];

class WishCard {
  WishCard({
    required this.id,
    required this.code,
    this.kind = WishKind.want,
    this.condition = '',
    List<String>? tags,
    this.price,
    this.currency = 'CNY',
    this.note = '',
    List<String>? photos,
    DateTime? addedAt,
  })  : tags = tags ?? <String>[],
        photos = photos ?? <String>[],
        addedAt = addedAt ?? DateTime.now();

  final String id;
  final String code; // 卡号
  WishKind kind;

  /// 品相：S / A / B / C / D（可以留空）
  String condition;

  /// 细化标签：未拆封 / 轻微白边 / 压痕 / 签名板…
  List<String> tags;

  /// 期望/标价（没填就是 null，界面上显示 - ）
  double? price;
  String currency;

  String note;

  /// 实拍图文件名（存在 App 专属目录 files/photos/ 下）
  List<String> photos;

  DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'kind': kind == WishKind.sell ? 'sell' : 'want',
        'condition': condition,
        'tags': tags,
        'price': price,
        'currency': currency,
        'note': note,
        'photos': photos,
        'addedAt': addedAt.toIso8601String(),
      };

  static WishCard fromJson(Map<String, dynamic> j) => WishCard(
        id: '${j['id']}',
        code: '${j['code']}',
        kind: wishKindFrom(j['kind'] as String?),
        condition: '${j['condition'] ?? ''}',
        tags: (j['tags'] as List? ?? const []).map((e) => '$e').toList(),
        price: (j['price'] as num?)?.toDouble(),
        currency: '${j['currency'] ?? 'CNY'}',
        note: '${j['note'] ?? ''}',
        photos: (j['photos'] as List? ?? const []).map((e) => '$e').toList(),
        addedAt: DateTime.tryParse('${j['addedAt']}') ?? DateTime.now(),
      );

  String encode() => jsonEncode(toJson());
}
