/// Small reusable motion widgets for the table: pulsing turn glow, idle card
/// lift, count-up numbers, punch-in badges, shakes and goat stomps. One-shot
/// effects use [TweenAnimationBuilder] (nothing to dispose); looping effects
/// own a controller and dispose it.
library;

import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../shared/theme/tokens.dart';

/// Slow, subtle pulsing glow behind the active player's tile (1.2 s loop).
class PulseGlow extends StatefulWidget {
  const PulseGlow({
    super.key,
    required this.active,
    required this.child,
    this.color = Tokens.gold300,
    this.borderRadius,
  });

  final bool active;
  final Widget child;
  final Color color;
  final BorderRadius? borderRadius;

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulseGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    // The RepaintBoundary sits INSIDE the per-frame DecoratedBox: the child
    // subtree (a whole opponent tile) is cached as its own layer and only
    // re-composited each frame — never re-painted — while the glow decoration
    // repaints alone. The tile call site adds an outer boundary that keeps
    // the glow repaint off the rest of the screen.
    return AnimatedBuilder(
      animation: _controller,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final v = Curves.easeInOut.transform(_controller.value);
        if (kIsWeb) {
          // Web: a solid stroke pulse instead of a per-frame-changing blur
          // sigma — the animated MaskFilter shadow is a continuous shader-
          // variant load the whole game (someone always has the turn).
          // Reads nearly identically at ~2 px.
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              border: Border.all(
                color: widget.color.withValues(alpha: 0.30 + 0.45 * v),
                width: 1.5 + 1.0 * v,
              ),
            ),
            child: child,
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.18 + 0.30 * v),
                blurRadius: 8 + 8 * v,
                spreadRadius: 0.5 + 2 * v,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// Gentle idle lift affordance for playable hand cards on my turn.
class IdleLift extends StatefulWidget {
  const IdleLift({
    super.key,
    required this.enabled,
    required this.child,
    this.phase = 0,
    this.amount = 3.5,
  });

  final bool enabled;
  final Widget child;

  /// Per-card phase in [0, 1) so cards breathe out of sync.
  final double phase;
  final double amount;

  @override
  State<IdleLift> createState() => _IdleLiftState();
}

/// One shared, ref-counted clock drives every enabled [IdleLift]: a full hand
/// of breathing cards costs a single ticker instead of one per card.
class _IdleLiftClock {
  _IdleLiftClock._();
  static final _IdleLiftClock instance = _IdleLiftClock._();

  static const _period = Duration(milliseconds: 2400);

  /// Cycle position in [0, 1); advances one notification per frame while
  /// at least one client is attached.
  final ValueNotifier<double> phase = ValueNotifier<double>(0);

  Ticker? _ticker;
  int _clients = 0;

  void retain() {
    _clients++;
    _ticker ??= Ticker(_onTick)..start();
  }

  void release() {
    _clients--;
    if (_clients <= 0) {
      _clients = 0;
      _ticker?.dispose();
      _ticker = null;
      phase.value = 0;
    }
  }

  void _onTick(Duration elapsed) {
    phase.value =
        (elapsed.inMicroseconds / _period.inMicroseconds) % 1.0;
  }
}

class _IdleLiftState extends State<IdleLift> {
  bool _attached = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(IdleLift oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  void _sync() {
    if (widget.enabled == _attached) return;
    if (widget.enabled) {
      _IdleLiftClock.instance.retain();
    } else {
      _IdleLiftClock.instance.release();
    }
    _attached = widget.enabled;
  }

  @override
  void dispose() {
    if (_attached) {
      _IdleLiftClock.instance.release();
      _attached = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    // The RepaintBoundary sits INSIDE the per-frame Transform: the card face
    // is cached as its own layer and only re-composited at a new offset each
    // frame — the full CardFacePainter never re-runs. The hand call site adds
    // an outer boundary that keeps the translate repaint off the hand strip.
    return AnimatedBuilder(
      animation: _IdleLiftClock.instance.phase,
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final wave =
            0.5 -
            0.5 *
                cos(
                  2 *
                      pi *
                      (_IdleLiftClock.instance.phase.value + widget.phase),
                );
        return Transform.translate(
          offset: Offset(0, -widget.amount * wave),
          child: child,
        );
      },
    );
  }
}

/// Text that counts from [from] up to [value] after [delay].
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    this.from = 0,
    this.prefix = '',
    this.suffix = '',
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.style,
  });

  final int value;
  final int from;
  final String prefix;
  final String suffix;
  final Duration delay;
  final Duration duration;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final total = delay + duration;
    final start = total.inMilliseconds == 0
        ? 0.0
        : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Text(
        '$prefix${(from + (value - from) * v).round()}$suffix',
        style: style,
      ),
    );
  }
}

/// Slides up and fades in once, after [delay] — for staggered rows.
class SlideFadeIn extends StatelessWidget {
  const SlideFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    final total = delay + duration;
    final start = total.inMilliseconds == 0
        ? 0.0
        : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, offset * (1 - v)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Punches in with an elastic scale-bounce — for ×2/×3 badges and count pops.
/// Re-keys (e.g. `ValueKey(popCount)`) to replay.
class PunchIn extends StatelessWidget {
  const PunchIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 550),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final total = delay + duration;
    final start = total.inMilliseconds == 0
        ? 0.0
        : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.elasticOut),
      builder: (context, v, child) => Transform.scale(
        scale: 0.4 + 0.6 * v,
        child: Opacity(opacity: (v * 3).clamp(0.0, 1.0), child: child),
      ),
      child: child,
    );
  }
}

/// One-shot horizontal shake (the goat's row of shame).
class ShakeWidget extends StatelessWidget {
  const ShakeWidget({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 700),
    this.amplitude = 6,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double amplitude;

  @override
  Widget build(BuildContext context) {
    final total = delay + duration;
    final start = total.inMilliseconds == 0
        ? 0.0
        : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1),
      builder: (context, v, child) => Transform.translate(
        offset: Offset(sin(v * pi * 6) * amplitude * (1 - v), 0),
        child: child,
      ),
      child: child,
    );
  }
}

/// Stomps in: oversized and tilted, then slams down to rest (the 🐐 entrance).
/// A gentler entrance (e.g. the login monogram) can lower [fromScale] and
/// [fromTilt].
class StompIn extends StatelessWidget {
  const StompIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 650),
    this.fromScale = 2.6,
    this.fromTilt = -0.35,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double fromScale;
  final double fromTilt;

  @override
  Widget build(BuildContext context) {
    final total = delay + duration;
    final start = total.inMilliseconds == 0
        ? 0.0
        : delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutBack),
      builder: (context, v, child) => Opacity(
        opacity: (v * 3).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: (1 - v) * fromTilt,
          child: Transform.scale(
            scale: fromScale + (1 - fromScale) * v,
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}
