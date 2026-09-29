import 'package:flutter/material.dart';

import '../data/keyword_db.dart';
import '../l10n/l10n.dart';
import '../widgets/bg_scaffold.dart';
import '../widgets/effect_text.dart';
import '../widgets/glass.dart';
import '../widgets/layout.dart';
import 'tutorial_page.dart';

/// 对战规则说明。
///
/// 内容是 Lycee Overture 的基本规则 + 本 App 的构筑校验口径，
/// 给刚上手的玩家一个"一页看完"的参考。词条部分直接读
/// assets/data/keywords.json（和卡详情里点词条弹出的是同一份数据），
/// 所以不会出现两处说法不一致。
class RulesPage extends StatelessWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BgScaffold(
      backgroundColor: Colors.transparent,
      appBar: GlassAppBar(title: Text(tr('对战规则'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kBottomBarSpace),
        children: [
          _Head(tr('胜利条件')),
          _rule(context, tr('把对方的牌库削到 0 张即获胜')),
          _rule(context, tr('这个游戏不看血量，看牌库——攻击没被角色挡下时，伤害直接进对方牌库')),

          _Head(tr('场地与区域')),
          _rule(context, tr('场地：前面 3 格是 AF（攻击区），后面 3 格是 DF（防御区），共 6 格')),
          _rule(context, tr('护盾置场：牌库要受伤时，可以破弃护盾置场的卡来代替承受')),
          _rule(context, tr('垃圾箱：被破弃的卡放这里，双方随时都能查看')),

          _Head(tr('卡组构成')),
          _rule(context, tr('主卡组正好 60 张（限定赛 30 张）')),
          _rule(context, tr('相同编号的卡最多 4 张（限定赛 2 张）')),
          _rule(context, tr('基本能力含「领导者」的卡最多 1 张，放在主战卡位')),
          _rule(context, tr('备卡区可选，0~10 张，构筑限制与主卡组联动计算')),
          _rule(context, tr('备卡区不计入 60 张，但算在「同编号最多 4 张」里')),

          _Head(tr('卡片种类')),
          _rule(context, tr('角色：配置到场上参与战斗，有 AP/DP/SP')),
          _rule(context, tr('事件：一次性效果，用完进垃圾箱')),
          _rule(context, tr('道具：配置后持续生效')),
          _rule(context, tr('区域：配置在场上，多为场地类效果')),

          _Head(tr('属性与数值')),
          _rule(context, tr('属性共 5 种：宙、月、花、日、雪')),
          _rule(context, tr('费用：使用这张卡需要支付的属性代偿')),
          _rule(context, tr('EX：这张卡被当作费用支付时产生的费用点数（不是稀有度）')),
          _rule(context, tr('AP：攻击力。攻击判定时和防御角色的 DP 比较，更高就把对方打掉')),
          _rule(context, tr('DP：防御力。攻击判定时和攻击角色的 AP 比较')),
          _rule(context, tr('SP：支援时提供的加成值，加到被支援角色的 AP 或 DP 上')),
          _rule(context, tr('DMG：攻击没被防御角色挡下时，破弃对方牌库的卡数')),

          _Head(tr('对局准备')),
          _rule(context, tr('双方各抽起手 7 张')),
          _rule(context, tr('先攻第一回合再抽 1 张、后攻第一回合抽 2 张，所以第一回合手上是 8 / 9 张')),
          _rule(context, tr('可以换牌：把手牌全部放回牌库、洗匀，再抽 7 张')),
          _rule(context, tr('主战卡（leader）单独放在主战卡位，不进手牌')),
          _rule(context, tr('手牌没有上限，但回合结束时超过 8 张要弃到 7 张')),

          _Head(tr('回合流程')),
          _rule(context, tr('开始阶段：唤醒（把自己已行动的角色全部转正）＋热身（抽 2 张，先攻第 1 回合只抽 1 张）')),
          _rule(context, tr('主要阶段：配置角色、使用事件／道具、宣言能力、进行攻击')),
          _rule(context, tr('战斗：攻击对方角色或对方玩家')),
          _rule(context, tr('回合结束：结算持续到回合结束的效果')),

          _Head(tr('行动时机')),
          _rule(context, tr('[宣言]：自己回合主动使用')),
          _rule(context, tr('[手牌宣言]：从手牌直接宣言的能力')),
          _rule(context, tr('[誘発]：条件满足时自动触发，不用主动使用')),
          _rule(context, tr('[常時]：一直有效，不需要宣言')),
          _rule(context, tr('[対応]：响应对方的行动而使用')),

          _Head(tr('能力与词条')),
          _rule(context, tr('卡面上的 [xxx] 是能力标记，点效果文本里的词条可以看含义')),
          const SizedBox(height: 4),
          _KeywordList(),

          _Head(tr('构筑校验说明')),
          _rule(context, tr('本 App 按上面的规则自动检查，分「错误」和「提示」两级')),
          _rule(context, tr('错误：张数不对、同编号超限、禁限卡表违规等硬性问题')),
          _rule(context, tr('提示：缺主战卡、卡面自带构筑限制等，可以手动忽略')),
          _rule(context, tr('禁限卡表见「我的 → 设置 → 禁限卡表」，可自定义')),

          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(tr('对战教程')),
            subtitle: Text(tr('这一页是速查清单，想从零上手看这个')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const TutorialPage()),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              tr('以上为基本规则整理，细节以官方规则书为准。'),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rule(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 3, 16, 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Expanded(
              child: Text(s,
                  style: const TextStyle(fontSize: 12.5, height: 1.55)),
            ),
          ],
        ),
      );
}

/// 词条列表：直接读 keywords.json（与卡详情里点词条弹的是同一份）
class _KeywordList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final all = KeywordDb.instance.all;
    if (all.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(tr('词条数据未加载'),
            style: const TextStyle(fontSize: 12)),
      );
    }
    // 按类型分组
    final byType = <String, List<Keyword>>{};
    for (final k in all) {
      (byType[k.type] ??= []).add(k);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in byType.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              tr(e.key),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final k in e.value)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(k.label,
                  style: const TextStyle(fontSize: 12.5)),
              subtitle: Text(
                [k.cond, k.desc]
                    .where((s) => s.isNotEmpty && s != '—')
                    .join('\n'),
                style: const TextStyle(fontSize: 11, height: 1.4),
              ),
              onTap: () => showKeywordSheet(context, k),
            ),
        ],
      ],
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            )),
      );
}
