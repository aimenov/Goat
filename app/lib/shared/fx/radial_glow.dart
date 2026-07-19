/// A soft radial gradient disc — used for the шоха burst, trump glow and the
/// achievements trophy halo.
library;

import 'package:flutter/material.dart';

import '../../core/render_mode.dart';

class RadialGlowPainter extends CustomPainter {
  const RadialGlowPainter({required this.color, required this.opacity});

  final Color color;
  final double opacity;

  /// Shaders are expensive to build, and these effects repaint every frame
  /// (with the radius animating too). One full-alpha unit-radius shader is
  /// cached per color; per frame we only scale the canvas to the current
  /// radius and modulate the paint alpha for the fade.
  static final Map<Color, Shader> _shaderCache = {};

  static Shader _shaderFor(Color color) => _shaderCache.putIfAbsent(
    color,
    () => RadialGradient(
      colors: [color, color.withValues(alpha: 0)],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
  );

  @override
  void paint(Canvas canvas, Size size) {
    // CPU mode: a big animated radial gradient is the single most expensive
    // software fill — the glow is an accent, not information, so drop it.
    if (cpuRenderMode) return;
    if (opacity <= 0.01) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    if (radius <= 0) return;
    final paint = Paint()
      ..shader = _shaderFor(color)
      // With a shader set, only the color's alpha applies — it multiplies
      // the shader output, giving us the per-frame fade for free.
      ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(radius);
    canvas.drawCircle(Offset.zero, 1, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RadialGlowPainter oldDelegate) =>
      oldDelegate.opacity != opacity || oldDelegate.color != color;
}
