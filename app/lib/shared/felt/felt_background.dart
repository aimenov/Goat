/// The casino felt backdrop: a warm radial "table lamp" light pool over deep
/// green, finished with a vignette. Painted once and cached as a layer by the
/// [RepaintBoundary], so table animations never re-rasterize it.
library;

import 'package:flutter/material.dart';

import '../../core/render_mode.dart';
import '../theme/cosmetic_styles.dart';

class FeltPainter extends CustomPainter {
  const FeltPainter({
    this.lightCenter = const Alignment(0, -0.15),
    this.theme = FeltTheme.classic,
  });

  final Alignment lightCenter;
  final FeltTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // CPU mode: two full-screen radial gradients are far too expensive to
    // software-rasterize (even cached, every resize re-pays them) — a flat
    // felt tone keeps the palette without the shader fills.
    if (cpuRenderMode) {
      canvas.drawRect(rect, Paint()..color = theme.flat);
      return;
    }

    // 1. Base fill.
    canvas.drawRect(rect, Paint()..color = theme.base);

    // 2. Radial light pool ("table lamp").
    final center = lightCenter.alongSize(size);
    final radius = size.longestSide * 0.75;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [theme.light, theme.mid, theme.base],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // 3. Vignette toward the edges.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            theme.deep.withValues(alpha: 0),
            theme.deep.withValues(alpha: 0.85),
          ],
          stops: const [0.55, 1.0],
        ).createShader(
          Rect.fromCircle(
            center: size.center(Offset.zero),
            radius: size.longestSide * 0.72,
          ),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant FeltPainter oldDelegate) =>
      oldDelegate.lightCenter != lightCenter ||
      !identical(theme, oldDelegate.theme);
}

/// Full-bleed felt backdrop; wraps [child] (if any) above the painted felt.
class FeltBackground extends StatelessWidget {
  const FeltBackground({
    super.key,
    this.lightCenter = const Alignment(0, -0.15),
    this.theme = FeltTheme.classic,
    this.child,
  });

  final Alignment lightCenter;
  final FeltTheme theme;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: FeltPainter(lightCenter: lightCenter, theme: theme),
        // Isolate the child: an ink ripple or entrance animation inside it
        // must not force the felt gradients to repaint.
        child: RepaintBoundary(child: child ?? const SizedBox.expand()),
      ),
    );
  }
}
