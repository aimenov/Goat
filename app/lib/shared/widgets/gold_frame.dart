/// Double gold hairline framing for overlay panels (game-over, scorecard)
/// plus the serif rule divider with a centered diamond pip.
library;

import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../cards/suit_paths.dart';
import '../theme/tokens.dart';

/// Two nested RRect strokes plus optional quarter-arc corner flourishes.
/// Fully static — never repaints.
class GoldFramePainter extends CustomPainter {
  const GoldFramePainter({
    this.radius = Tokens.r20,
    this.strokeOuter = 1.5,
    this.strokeInner = 1.0,
    this.insetInner = 6,
    this.flourishes = false,
  });

  final double radius;
  final double strokeOuter;
  final double strokeInner;
  final double insetInner;
  final bool flourishes;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeOuter
      ..color = Tokens.gold400;
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeInner
      ..color = Tokens.gold600.withValues(alpha: 0.7);

    final o = strokeOuter / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(o, o, size.width - 2 * o, size.height - 2 * o),
        Radius.circular(radius),
      ),
      outer,
    );
    final i = insetInner;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(i, i, size.width - 2 * i, size.height - 2 * i),
        Radius.circular((radius - i * 0.6).clamp(2.0, radius)),
      ),
      inner,
    );

    if (flourishes) {
      // Tiny quarter-arcs hugging each inner corner.
      const arc = 10.0;
      final f = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tokens.gold400.withValues(alpha: 0.8);
      final inset = i + 4;
      // Each quarter-arc is centered on an inner corner and sweeps the
      // quadrant that faces into the panel.
      final corners = [
        (Offset(inset, inset), 0.0), // top-left
        (Offset(size.width - inset, inset), pi / 2), // top-right
        (Offset(size.width - inset, size.height - inset), pi), // bottom-right
        (Offset(inset, size.height - inset), -pi / 2), // bottom-left
      ];
      for (final (corner, start) in corners) {
        canvas.drawArc(
          Rect.fromCircle(center: corner, radius: arc),
          start,
          pi / 2,
          false,
          f,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant GoldFramePainter oldDelegate) => false;
}

/// A 1px gold rule with a small painted ♦ at its center — the serif divider
/// under overlay headlines.
class GoldRule extends StatelessWidget {
  const GoldRule({super.key, this.width = 160});

  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size(width, 8), painter: const _GoldRulePainter());
  }
}

class _GoldRulePainter extends CustomPainter {
  const _GoldRulePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..strokeWidth = 1
      ..color = Tokens.gold600;
    const gap = 8.0;
    final cx = size.width / 2;
    canvas.drawLine(Offset(0, y), Offset(cx - gap, y), line);
    canvas.drawLine(Offset(cx + gap, y), Offset(size.width, y), line);
    paintSuitGlyph(
      canvas,
      suit: 2, // ♦
      center: Offset(cx, y),
      size: 6,
      paint: Paint()..color = Tokens.gold400,
    );
  }

  @override
  bool shouldRepaint(covariant _GoldRulePainter oldDelegate) => false;
}
