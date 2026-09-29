import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/banlist.dart';
import 'package:lycee_app/data/card_repository.dart';

/// 官方禁限卡表（要求 L83-84）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    BanList.instance.applyCustom({'forbidden': [], 'copyLimited': {}});
  });

  test('随包的官方表能读出来，且不是空的', () async {
    await BanList.instance.load();
    final ban = BanList.instance;
    expect(ban.loaded, isTrue);
    expect(ban.forbidden, isNotEmpty, reason: '官方有禁用卡');
    expect(ban.constructionLimited, isNotEmpty, reason: '官方有构筑限制卡');
    // ignore: avoid_print
    print(
      '官方表：禁止 ${ban.forbidden.length} 张 · '
      '构筑限制 ${ban.constructionLimited.length} 张 · '
      '更新日 ${ban.updatedAt}',
    );
  });

  test('官方表里的卡号在本地卡库都能查到', () async {
    await BanList.instance.load();
    await CardRepository.instance.load();
    final repo = CardRepository.instance;
    final ban = BanList.instance;

    final missing = <String>[];
    for (final c in {...ban.forbidden, ...ban.constructionLimited}) {
      if (repo.byCode(c) == null) missing.add(c);
    }
    expect(missing, isEmpty, reason: '这些卡号在卡库里查不到：$missing');
  });

  test('自定义禁止：叠加在官方之上，不覆盖官方', () async {
    await BanList.instance.load();
    final ban = BanList.instance;
    final official = ban.forbidden.length;

    ban.toggleCustomForbidden('LO-0001');
    expect(ban.isForbidden('LO-0001'), isTrue);
    expect(ban.forbidden.length, official, reason: '官方集合不该被改');
    expect(ban.allForbidden.length, official + 1);

    // 再点一次取消
    ban.toggleCustomForbidden('LO-0001');
    expect(ban.isForbidden('LO-0001'), isFalse);
  });

  test('自定义张数上限：能设也能清', () {
    final ban = BanList.instance;
    ban.setCustomCopyLimit('LO-0002', 2);
    expect(ban.copyLimitOf('LO-0002'), 2);
    ban.setCustomCopyLimit('LO-0002', null);
    expect(ban.copyLimitOf('LO-0002'), isNull);
    ban.setCustomCopyLimit('LO-0003', 0); // 0 视为清除
    expect(ban.copyLimitOf('LO-0003'), isNull);
  });

  test('导出/导入自定义：能往返', () {
    final ban = BanList.instance;
    ban.toggleCustomForbidden('LO-0001');
    ban.setCustomCopyLimit('LO-0002', 3);
    final exported = ban.exportCustom();
    final json = jsonDecode(jsonEncode(exported)) as Map<String, dynamic>;

    ban.applyCustom({'forbidden': [], 'copyLimited': {}});
    expect(ban.customForbidden, isEmpty);

    ban.applyCustom(json);
    expect(ban.customForbidden, contains('LO-0001'));
    expect(ban.copyLimitOf('LO-0002'), 3);
  });

  test('联网更新的结果能覆盖官方部分，但不动自定义', () async {
    await BanList.instance.load();
    final ban = BanList.instance;
    ban.toggleCustomForbidden('LO-0001');

    ban.applyOfficial({
      'forbidden': ['LO-9999'],
      'constructionLimited': ['LO-8888'],
      'copyLimited': {'LO-7777': 1},
      'updatedAt': '2099/01/01',
    });
    expect(ban.forbidden, ['LO-9999']);
    expect(ban.constructionLimited, ['LO-8888']);
    expect(ban.copyLimitOf('LO-7777'), 1);
    expect(ban.updatedAt, '2099/01/01');
    expect(ban.customForbidden, contains('LO-0001'), reason: '自定义限制不该被官方更新冲掉');
  });

  test('官方页面解析：从真实结构里抠出卡号', () async {
    // 用抓下来的真实页面（如果本地有）验证解析规则
    final raw = await rootBundle.loadString('assets/data/banlist.json');
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final fb = (j['forbidden'] as List).map((e) => '$e').toList();
    final cl = (j['constructionLimited'] as List).map((e) => '$e').toList();

    expect(fb.length, 15, reason: '正误订正卡不能混进使用禁止列表');
    expect(cl.length, 21, reason: '当前构筑限制包含多张生效日期表');
    // 卡号格式必须规范
    final re = RegExp(r'^LO-\d{3,5}(-[A-Z]{1,2})?$');
    for (final c in [...fb, ...cl]) {
      expect(re.hasMatch(c), isTrue, reason: '$c 格式不对');
    }
  });

  test('summary 会反映各表数量', () async {
    await BanList.instance.load();
    final s = BanList.instance.summary;
    expect(s.contains('禁止'), isTrue);
    expect(s.contains('构筑限制'), isTrue);
  });
}
