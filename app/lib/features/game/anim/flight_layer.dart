/// Fire-and-forget animation overlay for the game table: card flights, the
/// шоха signature moment and the trump-reveal flourish. Every effect owns one
/// [AnimationController], disposes it on completion, and never touches game
/// state — if the layer is gone or an anchor is missing, effects are skipped.
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cards.dart';
import '../../../core/services/sound.dart';
import '../../../shared/cards/card_face.dart';
import '../../../shared/fx/radial_glow.dart';
import '../../../shared/theme/tokens.dart';
import 'confetti.dart';
import 'flight_math.dart';

export '../../../shared/fx/radial_glow.dart' show RadialGlowPainter;

/// Motion/landing profile of a card flight.
enum FlightStyle {
  /// Dealing/drawing: calm, no landing pop.
  deal,

  /// A led card: slight breathing scale, melts into the table at the end.
  play,

  /// A beating card: grows in flight, then a short slam pop on landing.
  slam,

  /// A face-down discard: flips face-down mid-flight (scaleX flip).
  discard,

  /// Trick vacuum: accelerates into the winner and shrinks.
  vacuum,
}

class FlightLayer extends StatefulWidget {
  const FlightLayer({super.key, this.sound});

  /// Optional SFX hookup — only the шоха slam needs frame-exact audio.
  final SoundService? sound;

  @override
  State<FlightLayer> createState() => FlightLayerState();
}

class FlightLayerState extends State<FlightLayer>
    with TickerProviderStateMixin {
  final List<_Fx> _fx = [];
  final Set<Timer> _timers = {};
  bool _disposing = false;

  static const _maxConcurrent = 40;

  @override
  void dispose() {
    _disposing = true;
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final fx in _fx) {
      fx.controller.dispose();
    }
    _fx.clear();
    super.dispose();
  }

  /// Converts a global (screen) offset into this layer's coordinate space.
  Offset globalToLocal(Offset global) {
    final ro = context.findRenderObject();
    return ro is RenderBox && ro.attached ? ro.globalToLocal(global) : global;
  }

  /// The layer's current size (zero before first layout).
  Size get layerSize {
    final ro = context.findRenderObject();
    return ro is RenderBox && ro.hasSize ? ro.size : Size.zero;
  }

  // --------------------------------------------------------------- public

  /// Flies [card] (an already-built face or back widget) from [from] to [to].
  void flyCard({
    required Offset from,
    required Offset to,
    required Widget card,
    required double width,
    required double height,
    FlightStyle style = FlightStyle.play,
    Duration duration = const Duration(milliseconds: 320),
    Duration delay = Duration.zero,
    double bend = 0,
    double startRotation = 0,
    double endRotation = 0,
    bool flip = false,
  }) {
    _after(delay, () {
      _push(
        _CardFlightFx(
          controller: AnimationController(vsync: this, duration: duration),
          path: FlightPath.arc(from, to, bend: bend),
          card: RepaintBoundary(child: card),
          width: width,
          height: height,
          style: style,
          startRotation: startRotation,
          endRotation: endRotation,
          flip: flip,
        ),
      );
    });
  }

  /// The legendary шоха moment: dark barrier fade in/out, golden radial glow
  /// burst, oversized card scaling up then slamming onto its target, heavy
  /// haptic at the slam. ~900 ms total, never blocks the game.
  void playShoha({
    required Offset from,
    required Offset to,
    required int card,
  }) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    var slammed = false;
    controller.addListener(() {
      if (!slammed && controller.value >= 0.58) {
        slammed = true;
        HapticFeedback.heavyImpact();
        widget.sound?.play(Sfx.shohaImpact);
      }
    });
    _push(_ShohaFx(controller: controller, from: from, to: to, card: card));
  }

  /// Trump reveal flourish: 3D-ish rotateY flip at center, suit-colored glow,
  /// a sliding "Козырь — ♥" banner, then the card shrinks and docks into the
  /// trump indicator at [dock]. A gold particle shimmer bursts from the
  /// reveal center just after the flip shows the face.
  void playTrumpReveal({required int card, required Offset dock}) {
    _push(
      _TrumpFx(
        controller: AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 1500),
        ),
        card: card,
        dock: dock,
      ),
    );
    // ~t=0.30 of the 1500 ms flip: the face is up — shimmer.
    _after(const Duration(milliseconds: 450), () {
      _push(
        _ShimmerFx(
          controller: AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1100),
          ),
        ),
      );
    });
  }

  // -------------------------------------------------------------- plumbing

  void _after(Duration delay, VoidCallback run) {
    if (_disposing) return;
    if (delay <= Duration.zero) {
      run();
      return;
    }
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (mounted && !_disposing) run();
    });
    _timers.add(timer);
  }

  void _push(_Fx fx) {
    if (!mounted || _disposing || _fx.length >= _maxConcurrent) {
      fx.controller.dispose();
      return;
    }
    setState(() => _fx.add(fx));
    fx.controller.forward().whenCompleteOrCancel(() {
      if (_disposing) return;
      if (_fx.remove(fx)) {
        fx.controller.dispose();
        if (mounted) setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: _fx.isEmpty
          ? const SizedBox.expand()
          : RepaintBoundary(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      for (final fx in _fx)
                        AnimatedBuilder(
                          animation: fx.controller,
                          builder: (context, _) => fx.build(context, size),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

// ------------------------------------------------------------------ effects

abstract class _Fx {
  _Fx(this.controller);
  final AnimationController controller;

  Widget build(BuildContext context, Size layerSize);
}

class _CardFlightFx extends _Fx {
  _CardFlightFx({
    required AnimationController controller,
    required this.path,
    required this.card,
    required this.width,
    required this.height,
    required this.style,
    required this.startRotation,
    required this.endRotation,
    required this.flip,
  }) : super(controller);

  final FlightPath path;
  final Widget card;
  final double width;
  final double height;
  final FlightStyle style;
  final double startRotation;
  final double endRotation;
  final bool flip;

  @override
  Widget build(BuildContext context, Size layerSize) {
    final raw = controller.value;
    final moveCurve = switch (style) {
      FlightStyle.vacuum => Curves.easeInCubic,
      FlightStyle.slam => Curves.easeInOutCubic,
      FlightStyle.discard => Curves.easeInOut,
      _ => Curves.easeOutCubic,
    };
    final t = moveCurve.transform(raw);
    final pos = path.at(t);
    final angle = startRotation + (endRotation - startRotation) * t;
    final scale = _scale(raw);
    var sx = 1.0;
    if (flip) {
      final f = (raw / 0.38).clamp(0.0, 1.0);
      sx = (1 - 2 * f).abs().clamp(0.08, 1.0);
    }
    Widget child = Transform.rotate(
      angle: angle,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(scale * sx, scale, 1),
        child: card,
      ),
    );
    var opacity = _opacity(raw);
    // Web: every Opacity is a saveLayer, and 24-36 concurrent deal flights
    // land within a few frames — quantize to fully-opaque past 0.9 and only
    // pay for the layer while a fade is actually visible (flights just pop
    // ~10 px sooner). Native keeps the full fade.
    if (kIsWeb && opacity > 0.9) opacity = 1.0;
    if (!kIsWeb || opacity < 1.0) {
      child = Opacity(opacity: opacity, child: child);
    }
    return Positioned(
      left: pos.dx - width / 2,
      top: pos.dy - height / 2,
      child: child,
    );
  }

  double _scale(double t) => switch (style) {
    FlightStyle.slam =>
      t < 0.72
          ? 1.0 + 0.22 * Curves.easeOut.transform(t / 0.72)
          : 1.0 + 0.22 * (1 - Curves.easeIn.transform((t - 0.72) / 0.28)),
    FlightStyle.vacuum => 1.0 - 0.45 * t,
    FlightStyle.deal => 1.0,
    FlightStyle.discard => 0.95,
    FlightStyle.play => 1.0 + 0.10 * sin(pi * t),
  };

  double _opacity(double t) {
    final fadeIn = (t / 0.10).clamp(0.0, 1.0);
    final tailStart = style == FlightStyle.vacuum ? 0.82 : 0.90;
    final fadeOut = 1.0 - ((t - tailStart) / (1 - tailStart)).clamp(0.0, 1.0);
    return min(fadeIn, fadeOut).clamp(0.0, 1.0);
  }
}

class _ShohaFx extends _Fx {
  _ShohaFx({
    required AnimationController controller,
    required this.from,
    required this.to,
    required this.card,
  }) : super(controller);

  final Offset from;
  final Offset to;
  final int card;

  static const _gold = Tokens.goldGlow;
  static const _cardH = 84.0;

  @override
  Widget build(BuildContext context, Size layerSize) {
    final t = controller.value;

    // Dark barrier: fade in, hold while the card looms, fade out (~600 ms).
    final barrierPhase = t < 0.18
        ? t / 0.18
        : t > 0.66
        ? 1 - (t - 0.66) / 0.34
        : 1.0;
    final barrierAlpha = 0.5 * barrierPhase.clamp(0.0, 1.0);

    // Card: fly to the target while growing, loom, slam down to 1.0 scale.
    final mt = Curves.easeOutCubic.transform((t / 0.30).clamp(0.0, 1.0));
    final pos = Offset.lerp(from, to, mt)!;
    final double cardScale;
    if (t < 0.30) {
      cardScale = lerpDouble(1.3, 2.4, Curves.easeOut.transform(t / 0.30))!;
    } else if (t < 0.55) {
      cardScale = 2.4 + 0.05 * sin((t - 0.30) / 0.25 * pi * 2);
    } else if (t < 0.68) {
      cardScale = lerpDouble(
        2.4,
        1.0,
        Curves.easeInCubic.transform((t - 0.55) / 0.13),
      )!;
    } else {
      cardScale = 1.0;
    }
    final rotation = lerpDouble(-0.14, 0, (t / 0.68).clamp(0.0, 1.0))!;
    final cardOpacity = min(
      (t / 0.06).clamp(0.0, 1.0),
      1.0 - ((t - 0.92) / 0.08).clamp(0.0, 1.0),
    );

    // Golden glow burst behind the card.
    final gt = ((t - 0.18) / 0.72).clamp(0.0, 1.0);
    final glowRadius = lerpDouble(60.0, 200.0, Curves.easeOut.transform(gt))!;
    final glowOpacity = 0.85 * (1 - gt);

    const w = _cardH * cardAspect;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (barrierAlpha > 0.01)
            Container(color: Colors.black.withValues(alpha: barrierAlpha)),
          if (glowOpacity > 0.02)
            Positioned(
              left: pos.dx - glowRadius,
              top: pos.dy - glowRadius,
              width: glowRadius * 2,
              height: glowRadius * 2,
              child: CustomPaint(
                painter: RadialGlowPainter(color: _gold, opacity: glowOpacity),
              ),
            ),
          Positioned(
            left: pos.dx - w / 2,
            top: pos.dy - _cardH / 2,
            child: Opacity(
              opacity: cardOpacity.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scale: cardScale,
                  child: RepaintBoundary(
                    child: CardFace(card: card, height: _cardH),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrumpFx extends _Fx {
  _TrumpFx({
    required AnimationController controller,
    required this.card,
    required this.dock,
  }) : super(controller);

  final int card;
  final Offset dock;

  static const _cardH = 100.0;

  @override
  Widget build(BuildContext context, Size layerSize) {
    final t = controller.value;
    final center = Offset(layerSize.width / 2, layerSize.height * 0.38);
    final suit = suitOf(card);
    final suitColor =
        suit >= 2 ? Tokens.suitRedOnDark : Tokens.suitLightOnDark;

    // 3D-ish flip at center: back -> face.
    final f = Curves.easeInOutCubic.transform((t / 0.34).clamp(0.0, 1.0));
    final angle = pi * f;
    final showBack = angle < pi / 2;

    // Grow, hold, then shrink & dock into the trump indicator.
    final grow =
        1.0 + 0.5 * Curves.easeOut.transform((t / 0.20).clamp(0.0, 1.0));
    final mv = Curves.easeInOutCubic.transform(
      ((t - 0.62) / 0.34).clamp(0.0, 1.0),
    );
    final pos = Offset.lerp(center, dock, mv)!;
    final scale = lerpDouble(grow, 0.38, mv)!;
    final opacity = 1.0 - ((t - 0.94) / 0.06).clamp(0.0, 1.0);

    // Suit-colored glow while the face is shown at center.
    final glowOpacity = t < 0.30
        ? 0.0
        : t < 0.62
        ? 0.55 * sin(pi * (t - 0.30) / 0.32)
        : 0.0;

    // Suit banner slides by underneath.
    final bt = ((t - 0.30) / 0.45).clamp(0.0, 1.0);
    final bannerOpacity = sin(pi * bt);
    final bannerDx = lerpDouble(-50.0, 50.0, bt)!;

    // Web: a plain scaleX flip (exactly like the discard flip) — the
    // perspective entry would compile a distinct texture-sampling pipeline
    // variant right in the deal-start burst. Native keeps the 3D-ish flip.
    final transform = kIsWeb
        ? Matrix4.diagonal3Values(max(0.08, cos(angle).abs()), 1.0, 1.0)
        : (Matrix4.identity()
          ..setEntry(3, 2, 0.0014)
          ..rotateY(showBack ? angle : angle - pi));

    const w = _cardH * cardAspect;
    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (glowOpacity > 0.02)
            Positioned(
              left: pos.dx - 140,
              top: pos.dy - 140,
              width: 280,
              height: 280,
              child: CustomPaint(
                painter: RadialGlowPainter(
                  color: suitColor,
                  opacity: glowOpacity,
                ),
              ),
            ),
          if (bannerOpacity > 0.02 && bt > 0 && bt < 1)
            Positioned(
              left: 0,
              right: 0,
              top: center.dy + _cardH * 0.95,
              child: Opacity(
                opacity: bannerOpacity.clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(bannerDx, 0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Козырь — ${suitSymbol(suit)}',
                        style: TextStyle(
                          fontFamily: Tokens.serifFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: suitColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: pos.dx - w / 2,
            top: pos.dy - _cardH / 2,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Transform(
                  alignment: Alignment.center,
                  transform: transform,
                  child: RepaintBoundary(
                    child: showBack
                        ? const CardBack(height: _cardH)
                        : CardFace(card: card, height: _cardH, trumpStyle: true),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gold particle shimmer bursting from the trump-reveal center. Particles
/// are precomputed; the painter's radial mode does zero per-frame allocation
/// beyond the shared faded-palette map.
class _ShimmerFx extends _Fx {
  _ShimmerFx({required AnimationController controller})
    : particles = ConfettiParticle.generate(
        36,
        Random(1129),
        palette: ConfettiParticle.goldPalette,
      ),
      super(controller);

  final List<ConfettiParticle> particles;

  /// The trump reveal happens at (0.5, 0.38) of the layer — see [_TrumpFx].
  static const _origin = Offset(0.5, 0.38);

  @override
  Widget build(BuildContext context, Size layerSize) {
    return Positioned.fill(
      child: CustomPaint(
        painter: ConfettiPainter(
          particles: particles,
          progress: controller.value,
          palette: ConfettiParticle.goldPalette,
          origin: _origin,
          radial: true,
        ),
      ),
    );
  }
}
