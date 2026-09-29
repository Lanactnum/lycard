/// 用户对某张卡的修改 / 用户新建的卡
///
/// 只存「被改过的字段」，没改的留 null（用官方数据）。
class CardOverride {
  CardOverride({
    required this.code,
    this.isNew = false,
    this.nameZh,
    this.nameJp,
    this.effectZh,
    this.color,
    this.cost,
    this.ex,
    this.ap,
    this.dp,
    this.sp,
    this.dmg,
    this.kind,
    this.cardType,
    this.series,
    this.illust,
    this.rarity,
    this.imageFile,
    List<String>? categories,
  }) : categories = categories ?? <String>[];

  final String code;
  final bool isNew; // true = 用户新建的卡（不是覆盖官方卡）

  String? nameZh;
  String? nameJp;
  String? effectZh;
  String? color;
  String? cost;
  int? ex;
  int? ap;
  int? dp;
  int? sp;
  int? dmg;
  String? kind; // キャラクター / イベント / アイテム / エリア
  String? cardType; // 类型（タイプ）
  String? series; // 作品
  String? illust; // 画师
  String? rarity; // 罕贵度

  /// 替换的卡面图片文件名（存在 App 专属目录 files/cards/ 下）
  String? imageFile;

  /// 自定义分类（用户可以新建分类并把卡丢进去）
  List<String> categories;

  bool get isEmpty =>
      nameZh == null &&
      nameJp == null &&
      effectZh == null &&
      color == null &&
      cost == null &&
      ex == null &&
      ap == null &&
      dp == null &&
      sp == null &&
      dmg == null &&
      kind == null &&
      cardType == null &&
      series == null &&
      illust == null &&
      rarity == null &&
      imageFile == null &&
      categories.isEmpty &&
      !isNew;

  Map<String, dynamic> toJson() => {
        'code': code,
        if (isNew) 'isNew': true,
        if (nameZh != null) 'nameZh': nameZh,
        if (nameJp != null) 'nameJp': nameJp,
        if (effectZh != null) 'effectZh': effectZh,
        if (color != null) 'color': color,
        if (cost != null) 'cost': cost,
        if (ex != null) 'ex': ex,
        if (ap != null) 'ap': ap,
        if (dp != null) 'dp': dp,
        if (sp != null) 'sp': sp,
        if (dmg != null) 'dmg': dmg,
        if (kind != null) 'kind': kind,
        if (cardType != null) 'cardType': cardType,
        if (series != null) 'series': series,
        if (illust != null) 'illust': illust,
        if (rarity != null) 'rarity': rarity,
        if (imageFile != null) 'imageFile': imageFile,
        if (categories.isNotEmpty) 'categories': categories,
      };

  static CardOverride fromJson(Map<String, dynamic> j) => CardOverride(
        code: '${j['code']}',
        isNew: j['isNew'] == true,
        nameZh: j['nameZh'] as String?,
        nameJp: j['nameJp'] as String?,
        effectZh: j['effectZh'] as String?,
        color: j['color'] as String?,
        cost: j['cost'] as String?,
        ex: (j['ex'] as num?)?.toInt(),
        ap: (j['ap'] as num?)?.toInt(),
        dp: (j['dp'] as num?)?.toInt(),
        sp: (j['sp'] as num?)?.toInt(),
        dmg: (j['dmg'] as num?)?.toInt(),
        kind: j['kind'] as String?,
        cardType: j['cardType'] as String?,
        series: j['series'] as String?,
        illust: j['illust'] as String?,
        rarity: j['rarity'] as String?,
        imageFile: j['imageFile'] as String?,
        categories:
            (j['categories'] as List? ?? const []).map((e) => '$e').toList(),
      );
}
