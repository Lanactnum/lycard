import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lycee_app/data/card_repository.dart';
import 'package:lycee_app/models/collect_info.dart';
import 'package:lycee_app/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 要求 55：罕贵度 / 异画 + 角标颜色自定义
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> fresh() async {
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await AppState.create();
    SharedPreferences.setMockInitialValues({'deckSeeded': true});
    await CardRepository.instance.load();
    return AppState.create();
  }

  test('记录我手上的罕贵度 / 异画，没记录的回落官方', () async {
    final s = await fresh();
    final official = CardRepository.instance.byCode('LO-0575')!.rarity;

    expect(s.rarityOf('LO-0575', official), official);
    expect(s.isParallel('LO-0575'), isFalse);

    s.setCollectInfo('LO-0575', CollectInfo(rarity: 'SP', parallel: true));
    // ignore: avoid_print
    debugPrint('官方 $official → 我记的是 SP 异画');
    expect(s.rarityOf('LO-0575', official), 'SP');
    expect(s.isParallel('LO-0575'), isTrue);

    // 清除 → 回到官方
    s.setCollectInfo('LO-0575', CollectInfo());
    expect(s.rarityOf('LO-0575', official), official);
    expect(s.isParallel('LO-0575'), isFalse);
  });

  test('角标样式：默认色 + 自定义颜色/模糊/透明度', () async {
    final s = await fresh();
    final def = s.rarityStyle('SR');
    expect(def.color, defaultRarityColor('SR'));
    expect(s.hasCustomRarityStyle('SR'), isFalse);

    s.setRarityStyle('SR', RarityStyle(
      color: const Color(0xFFFF00AA),
      blur: 6,
      opacity: 0.5,
    ));
    final st = s.rarityStyle('SR');
    // ignore: avoid_print
    debugPrint('SR 角标：颜色 #${st.color.toARGB32().toRadixString(16)} '
        '模糊 ${st.blur} 透明度 ${st.opacity}');
    expect(s.hasCustomRarityStyle('SR'), isTrue);
    expect(st.blur, 6);
    expect(st.opacity, 0.5);
    // 透明度真的作用到显示色上
    expect(st.effective.a, lessThan(st.color.a));

    s.resetRarityStyle('SR');
    expect(s.rarityStyle('SR').color, defaultRarityColor('SR'));
    expect(s.hasCustomRarityStyle('SR'), isFalse);
  });

  test('每个罕贵度都有默认色，不会找不到', () async {
    await fresh();
    final all = CardRepository.instance.allRarities;
    expect(all, isNotEmpty);
    for (final r in all) {
      expect(defaultRarityColor(r), isA<Color>());
    }
    // ignore: avoid_print
    debugPrint('${all.length} 个罕贵度都有默认配色：${all.join(' ')}');
  });

  test('罕贵度记录与角标样式能跟着备份走', () async {
    final s = await fresh();
    s.setCollectInfo('LO-0575', CollectInfo(rarity: 'L', parallel: true));
    s.setRarityStyle('L', RarityStyle(color: const Color(0xFF00FF00), blur: 3, opacity: 0.7));
    final data = s.exportData();
    expect((data['collect'] as Map).length, 1);
    expect((data['rarityStyles'] as Map).length, 1);

    final s2 = await fresh();
    s2.importData(data);
    expect(s2.collectInfoOf('LO-0575')!.rarity, 'L');
    expect(s2.isParallel('LO-0575'), isTrue);
    expect(s2.rarityStyle('L').blur, 3);
    expect(s2.rarityStyle('L').color.toARGB32(), 0xFF00FF00);
  });
}
