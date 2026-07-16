/// Lightweight confetti: ~80 precomputed particles, one controller, a single
/// [CustomPainter] and an auto-stop — no assets, no per-frame allocation.
/// Supports a falling full-area mode (game over) and a radial shimmer mode
/// ([ConfettiPainter.radial]) used for the trump-reveal gold burst.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shared/theme/tokens.dart';

class ConfettiParticle {
  const ConfettiParticle({
    required this.x,
    required this.speed,
    required this.size,
    required this.sway,
    required this.phase,
    required this.spin,
    required this.color,
  });

  /// Horizontal start position as a fraction of width [0, 1].
  final double x;

  /// Fall distance over the full animation, as a fraction of height.
  final double speed;

  /// Flake size in logical pixels.
  final double size;

  /// Horizontal sway amplitude in logical pixels.
  final double sway;

  /// Sway phase offset in radians (doubles as the launch direction when the
  /// painter runs in radial mode).
  final double phase;

  /// Total rotation over the lifetime, radians.
  final double spin;

  final Color color;

  static const palette = [
    Color(0xFFFFC107),
    Color(0xFF66BB6A),
    Color(0xFFEF5350),
    Color(0xFF42A5F5),
    Color(0xFFF5F5F5),
    Color(0xFFAB47BC),
  ];

  /// Casino game-over retint: gold, ivory, carmine, felt.
  static const casinoPalette = [
    Tokens.gold100,
    Tokens.gold300,
    Tokens.gold400,
    Tokens.ivory,
    Tokens.suitRedOnDark,
    Tokens.feltLine,
  ];

  /// Trump-reveal shimmer: pure golds and ivory.
  static const goldPalette = [
    Tokens.gold100,
    Tokens.gold200,
    Tokens.gold400,
    Tokens.goldGlow,
    Tokens.ivory,
  ];

  /// Deterministic particle set for a given [rng] seed.
  static List<ConfettiParticle> generate(
    int count,
    Random rng, {
    List<Color>? palette,
  }) {
    final colors = palette ?? ConfettiParticle.palette;
    return [
      for (var i = 0; i < count; i++)
        ConfettiParticle(
          x: rng.nextDouble(),
          speed: 0.9 + rng.nextDouble() * 0.6,
          size: 5 + rng.nextDouble() * 5,
          sway: 8 + rng.nextDouble() * 22,
          phase: rng.nextDouble() * 2 * pi,
          spin: (rng.nextDouble() * 2 - 1) * 6 * pi,
          color: colors[rng.nextInt(colors.length)],
        ),
    ];
  }
}

class ConfettiPainter extends CustomPainter {
  const ConfettiPainter({
    required this.particles,
    required this.progress,
    this.palette = ConfettiParticle.palette,
    this.origin,
    this.radial = false,
  });

  final List<ConfettiParticle> particles;

  /// Animation progress in [0, 1].
  final double progress;

  /// The palette [particles] were generated from — used for the shared
  /// fade-map (≤ palette-size Color allocations per frame, not per particle).
  final List<Color> palette;

  /// Burst origin in fraction coordinates (radial mode).
  final Offset? origin;

  /// Radial shimmer: particles fly outward from [origin] and settle with a
  /// slight t² gravity fall instead of raining top-to-bottom.
  final bool radial;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = progress.clamp(0.0, 1.0);
    final fade = t < 0.75 ? 1.0 : 1.0 - (t - 0.75) / 0.25;
    if (fade <= 0) return;
    // Fade the fixed palette once per frame (a handful of Color allocations)
    // instead of allocating a faded Color per particle (~80/frame).
    final faded = fade >= 1.0
        ? null
        : {for (final c in palette) c: c.withValues(alpha: fade)};
    final paint = Paint();
    final o = radial
        ? Offset(
            size.width * (origin?.dx ?? 0.5),
            size.height * (origin?.dy ?? 0.5),
          )
        : Offset.zero;
    final reach = size.shortestSide * 0.35;
    final radialT = Curves.easeOut.transform(t);
    for (final p in particles) {
      final double x;
      final double y;
      if (radial) {
        final r = p.speed * radialT * reach;
        x = o.dx + cos(p.phase) * r;
        y = o.dy + sin(p.phase) * r + size.height * 0.10 * t * t; // gravity
      } else {
        y = size.height * (p.speed * t - 0.06);
        if (y < -20 || y > size.height + 20) continue;
        x = size.width * p.x + sin(t * 8 + p.phase) * p.sway;
      }
      paint.color = faded == null ? p.color : (faded[p.color] ?? p.color);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      // Fold on a second axis for a tumbling-paper look.
      final squeeze = 0.25 + 0.75 * sin(t * 10 + p.phase).abs();
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * squeeze,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.particles != particles;
}

/// Full-area confetti burst that runs once and removes itself.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({
    super.key,
    this.particleCount = 80,
    this.duration = const Duration(milliseconds: 2600),
    this.seed = 7,
    this.palette,
  });

  final int particleCount;
  final Duration duration;
  final int seed;

  /// Optional palette override (e.g. [ConfettiParticle.casinoPalette]).
  final List<Color>? palette;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final List<ConfettiParticle> _particles = ConfettiParticle.generate(
    widget.particleCount,
    Random(widget.seed),
    palette: widget.palette,
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            size: Size.infinite,
            painter: ConfettiPainter(
              particles: _particles,
              progress: _controller.value,
              palette: widget.palette ?? ConfettiParticle.palette,
            ),
          ),
        ),
      ),
    );
  }
}
