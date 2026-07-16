/// Small brass stadium chips for scores and counters: dark felt fill, gold
/// hairline, numeric (tabular) content. [AnimatedScoreChip] adds a count-up
/// roll, a punch-in pop and a brief gold border flash on value change.
library;

import 'package:flutter/material.dart';

import '../../features/game/anim/motion_widgets.dart';
import '../theme/tokens.dart';

class BrassChip extends StatelessWidget {
  const BrassChip({
    super.key,
    this.icon,
    this.text,
    this.child,
    this.danger = false,
    this.fontSize = 12,
  }) : assert(text != null || child != null, 'text or child required');

  final IconData? icon;
  final String? text;
  final Widget? child;

  /// ×3+ multiplier variant: border/text switch to danger.
  final bool danger;
  final double fontSize;

  static BoxDecoration decoration({bool danger = false, Color? borderColor}) =>
      BoxDecoration(
        color: Tokens.felt900.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderColor ??
              (danger ? Tokens.danger : Tokens.gold600.withValues(alpha: 0.6)),
          width: 0.8,
        ),
      );

  static TextStyle textStyle({bool danger = false, double fontSize = 12}) =>
      Tokens.numeric.copyWith(
        fontSize: fontSize,
        color: danger ? Tokens.danger : Tokens.gold100,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: decoration(danger: danger),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1, color: Tokens.gold300),
            const SizedBox(width: 3),
          ],
          child ??
              Text(text!, style: textStyle(danger: danger, fontSize: fontSize)),
        ],
      ),
    );
  }
}

/// Brass chip whose number rolls up (CountUpText), pops (PunchIn) and briefly
/// flashes its gold border whenever [value] changes. Tickerless at rest.
class AnimatedScoreChip extends StatefulWidget {
  const AnimatedScoreChip({
    super.key,
    required this.value,
    this.prefix = '',
    this.icon,
    this.fontSize = 12,
  });

  final int value;
  final String prefix;
  final IconData? icon;
  final double fontSize;

  @override
  State<AnimatedScoreChip> createState() => _AnimatedScoreChipState();
}

class _AnimatedScoreChipState extends State<AnimatedScoreChip> {
  int _from = 0;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.value;
  }

  @override
  void didUpdateWidget(AnimatedScoreChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _from = oldWidget.value;
      _gen++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.fontSize + 1, color: Tokens.gold300),
          const SizedBox(width: 3),
        ],
        CountUpText(
          key: ValueKey('score-$_gen'),
          from: _from,
          value: widget.value,
          prefix: widget.prefix,
          duration: const Duration(milliseconds: 450),
          style: BrassChip.textStyle(fontSize: widget.fontSize),
        ),
      ],
    );

    // Border flash: gold300 -> gold600 over 400 ms, re-keyed per change.
    final chip = _gen == 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BrassChip.decoration(),
            child: content,
          )
        : TweenAnimationBuilder<double>(
            key: ValueKey('flash-$_gen'),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 400),
            builder: (context, t, child) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BrassChip.decoration(
                borderColor: Color.lerp(
                  Tokens.gold300,
                  Tokens.gold600.withValues(alpha: 0.6),
                  t,
                ),
              ),
              child: child,
            ),
            child: content,
          );

    if (_gen == 0) return chip;
    return PunchIn(key: ValueKey('pop-$_gen'), child: chip);
  }
}
