import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../data/keyword_db.dart';
import '../pages/card_detail_page.dart';
import 'glass.dart';
import '../l10n/l10n.dart';

/// 把卡片效果文本渲染成「可以点」的文字：
///
///  · 词条（跳跃 / 充能 / 诱发 …）—— 点一下弹出含义浮层
///  · 别的卡名（效果里提到某张卡）—— 点一下跳到那张卡
class EffectText extends StatefulWidget {
  const EffectText({
    super.key,
    required this.text,
    required this.selfCode,
    this.selfSeries = '',
    this.style,
  });

  final String text;

  /// 当前卡自己，避免「跳到自己」
  final String selfCode;

  /// 当前卡所属系列：同名卡分散在不同弹里时，用它把同系列的排前面，
  /// 免得「言灵」跳到别弹去（除非那弹才是唯一同系列的）
  final String selfSeries;
  final TextStyle? style;

  @override
  State<EffectText> createState() => _EffectTextState();
}

class _EffectTextState extends State<EffectText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _clearRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _tap(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  void dispose() {
    _clearRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.style ?? const TextStyle(height: 1.6);
    final text = widget.text;

    // 每次重建先释放上一轮的识别器，避免泄漏
    _clearRecognizers();

    final marks = <_Mark>[];
    for (final (s, e, k) in KeywordDb.instance.scan(text)) {
      marks.add(_Mark(s, e, _MarkKind.keyword, keyword: k));
    }
    for (final hit in CardRepository.instance.scanCardNames(
      text,
      selfSeries: widget.selfSeries,
    )) {
      if (hit.code == widget.selfCode) continue;
      final overlap = marks
          .where((m) => hit.start < m.end && hit.end > m.start)
          .toList();
      if (overlap.isNotEmpty) {
        if (_isExplicitCardReference(text, hit.start, hit.end)) {
          marks.removeWhere(overlap.contains);
        } else {
          continue;
        }
      }
      marks.add(
        _Mark(
          hit.start,
          hit.end,
          _MarkKind.card,
          code: hit.code,
          codes: hit.codes,
        ),
      );
    }
    marks.sort((a, b) => a.start.compareTo(b.start));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in marks) {
      if (m.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, m.start)));
      }
      final label = text.substring(m.start, m.end);
      final isKw = m.kind == _MarkKind.keyword;
      // 关键词和卡名都是"能点的"，统一用主色（蓝）——
      // 以前卡名用 tertiary，颜色不蓝，看着像没做成可点。
      final color = scheme.primary;
      spans.add(
        TextSpan(
          text: label,
          style: base.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
            decorationColor: color,
          ),
          recognizer: _tap(() {
            if (isKw) {
              showKeywordSheet(context, m.keyword!);
              return;
            }
            if (m.codes.length <= 1) {
              _openCard(context, m.code!);
            } else {
              // 同名不同编号：不猜，直接让用户选
              _pickSameName(context, label, m.codes);
            }
          }),
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return SelectableText.rich(TextSpan(style: base, children: spans));
  }
}

enum _MarkKind { keyword, card }

bool _isExplicitCardReference(String text, int start, int end) {
  final left = start > 0 ? text[start - 1] : '';
  final right = end < text.length ? text[end] : '';
  return (left == '「' && right == '」') ||
      (left == '『' && right == '』') ||
      (left == '"' && right == '"');
}

class _Mark {
  _Mark(
    this.start,
    this.end,
    this.kind, {
    this.keyword,
    this.code,
    List<String>? codes,
  }) : codes = codes ?? (code == null ? const <String>[] : <String>[code]);

  final int start;
  final int end;
  final _MarkKind kind;
  final Keyword? keyword;
  final String? code;

  /// 同名不同编号时的全部候选
  final List<String> codes;
}

/// 进卡详情（效果文本里点卡名走这里）
void _openCard(BuildContext context, String code) {
  // 效果文本是长按/点击可滚动的文字，这里顺手把焦点放掉；
  // 否则从这一层卡详情再返回上一层时，键盘会莫名其妙弹出来。
  FocusManager.instance.primaryFocus?.unfocus();
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CardDetailPage(heroScope: 'effect', code: code),
    ),
  );
}

/// 同名不同编号：不猜，弹个选择框让用户挑
Future<void> _pickSameName(
  BuildContext context,
  String label,
  List<String> codes,
) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showFloatingLayer<void>(
    context: context,
    barrierLabel: tr('选择卡牌'),
    builder: (c) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('「{0}」有 {1} 张同名卡', [label, codes.length]),
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              tr('选一张查看'),
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(c).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final code in codes) _SameNameRow(code: code),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 同名卡列表里的一行：卡名 + **系列名** + 卡号。
///
/// 系列名必须显示 —— 同名卡往往分布在不同弹里（「言霊」在
/// パープルソフトウェア 1.0 和 2.0 各有一张），只看卡名根本分不清
/// 该点哪一张。
class _SameNameRow extends StatelessWidget {
  const _SameNameRow({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repo = CardRepository.instance;
    final card = repo.byCode(code);
    final series = card == null ? '' : card.seriesName;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.of(context).pop();
        _openCard(context, code);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card?.nameZh ?? card?.nameJp ?? code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  if (series.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        series,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              code,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 词条含义浮层 —— 下方弹出的悬浮玻璃胶囊
Future<void> showKeywordSheet(BuildContext context, Keyword k) {
  return showFloatingLayer<void>(
    context: context,
    barrierLabel: tr('关闭'),
    builder: (c) => _KeywordCapsule(k: k),
  );
}

class _KeywordCapsule extends StatelessWidget {
  const _KeywordCapsule({required this.k});

  final Keyword k;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium ?? const TextStyle();
    final title = theme.textTheme.titleSmall ?? const TextStyle();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.55,
        maxWidth: 400,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    k.type,
                    style: (body).copyWith(
                      fontSize: 10.5,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    k.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: title.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  color: scheme.onSurfaceVariant,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (k.cond.isNotEmpty && k.cond != '—') ...[
                      const SizedBox(height: 4),
                      Text(
                        k.cond,
                        style: body.copyWith(
                          color: scheme.onSurface,
                          height: 1.45,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      k.desc,
                      style: body.copyWith(
                        color: scheme.onSurface,
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
