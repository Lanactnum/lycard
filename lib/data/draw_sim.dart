import 'dart:math';

/// 起手模拟（要求 L86 / L87）
///
/// · 试抽 8 / 9 张（先手 / 后手）
/// · 支持换牌（mulligan）与再摸一张
/// · 选中若干张卡 → 用超几何分布精确算"起手至少摸到其中一张的概率"
class DrawSim {
  DrawSim(this.cards, {int? seed})
      : _rnd = Random(seed),
        _library = _expand(cards);

  /// 卡组构成：卡号 → 张数
  final Map<String, int> cards;
  final Random _rnd;

  /// 牌库（已展开成一张张卡号）
  List<String> _library;

  /// 当前手牌
  final List<String> hand = [];

  /// 换过几次牌
  int mulligans = 0;

  static List<String> _expand(Map<String, int> src) {
    final out = <String>[];
    src.forEach((code, n) {
      for (var i = 0; i < n; i++) {
        out.add(code);
      }
    });
    return out;
  }

  int get deckSize => cards.values.fold(0, (a, b) => a + b);

  /// 洗牌后抽 [n] 张（先手 8 / 后手 9）
  void deal(int n) {
    _library = _expand(cards)..shuffle(_rnd);
    hand
      ..clear()
      ..addAll(_library.take(n));
    _library.removeRange(0, min(n, _library.length));
    mulligans = 0;
  }

  /// 换牌：把 [codes] 按出现次数放回牌库、洗牌、再补抽同样多张
  ///
  /// [codes] 允许重复（手上有 2 张同名就传两次）。
  /// 返回实际换掉的张数。
  int mulligan(List<String> codes) {
    if (codes.isEmpty) return 0;
    var changed = 0;
    for (final c in codes) {
      final i = hand.indexOf(c);
      if (i < 0) continue;
      hand.removeAt(i);
      _library.add(c);
      changed++;
    }
    if (changed == 0) return 0;
    _library.shuffle(_rnd);
    final draw = min(changed, _library.length);
    hand.addAll(_library.take(draw));
    _library.removeRange(0, draw);
    mulligans++;
    return changed;
  }

  /// 再摸一张（模拟回合开始抽牌）
  String? drawOne() {
    if (_library.isEmpty) return null;
    final c = _library.removeAt(0);
    hand.add(c);
    return c;
  }

  /// 起手（含首次摸牌）里至少摸到"目标牌里任意一张"的概率。
  ///
  /// 超几何分布：P(至少一张) = 1 - C(N-K, n) / C(N, n)
  ///   N = 卡组总张数、K = 目标牌总张数、n = 抽牌张数
  /// [mulliganAllowed] 为真时按"可以换一次牌"估算（等价于抽两轮取并集，略高估）。
  static double probAtLeastOne({
    required int deckSize,
    required int targets,
    required int drawCount,
    bool mulliganAllowed = false,
  }) {
    if (deckSize <= 0 || targets <= 0 || drawCount <= 0) return 0;
    final k = min(targets, deckSize);
    final n = min(drawCount, deckSize);
    double missOnce(int nn) {
      // C(N-K, nn) / C(N, nn)
      var p = 1.0;
      for (var i = 0; i < nn; i++) {
        p *= (deckSize - k - i) / (deckSize - i);
      }
      return p;
    }

    final miss = missOnce(n);
    if (!mulliganAllowed) return (1 - miss).clamp(0.0, 1.0);
    // 换牌后重抽 n 张，仍是"全没中"的概率 = miss^2（近似，不扣掉已换出的牌）
    return (1 - miss * missOnce(n)).clamp(0.0, 1.0);
  }

  /// 手牌按卡号归并成 卡号 → 张数
  Map<String, int> handCount() {
    final out = <String, int>{};
    for (final c in hand) {
      out[c] = (out[c] ?? 0) + 1;
    }
    return out;
  }

  /// 牌库里还剩多少张
  int get remaining => _library.length;
}
