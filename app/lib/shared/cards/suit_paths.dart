/// Vector suit glyphs — crisp at any size, no emoji font anywhere.
/// Each path lives in a 100×100 unit box; callers scale the canvas by
/// `size / 100` and fill. Paths are cached as `static final` (stateless).
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

Path heartPath() => Path()
  ..moveTo(50, 30)
  ..cubicTo(50, 19, 41, 11, 30, 11)
  ..cubicTo(15, 11, 7, 23, 7, 34)
  ..cubicTo(7, 52, 24, 65, 50, 90)
  ..cubicTo(76, 65, 93, 52, 93, 34)
  ..cubicTo(93, 23, 85, 11, 70, 11)
  ..cubicTo(59, 11, 50, 19, 50, 30)
  ..close();

/// Gently cushioned diamond.
Path diamondPath() => Path()
  ..moveTo(50, 5)
  ..quadraticBezierTo(62, 32, 89, 50)
  ..quadraticBezierTo(62, 68, 50, 95)
  ..quadraticBezierTo(38, 68, 11, 50)
  ..quadraticBezierTo(38, 32, 50, 5)
  ..close();

/// Inverted heart + flared stem.
Path spadePath() => Path()
  ..moveTo(50, 6)
  ..cubicTo(38, 24, 10, 38, 10, 56)
  ..cubicTo(10, 68, 19, 76, 29, 76)
  ..cubicTo(37, 76, 44, 72, 47, 65) // left lobe into notch
  ..cubicTo(46, 74, 43, 84, 36, 92) // stem left flare
  ..lineTo(64, 92)
  ..cubicTo(57, 84, 54, 74, 53, 65) // stem right flare
  ..cubicTo(56, 72, 63, 76, 71, 76)
  ..cubicTo(81, 76, 90, 68, 90, 56)
  ..cubicTo(90, 38, 62, 24, 50, 6)
  ..close();

/// Three discs + spade stem.
Path clubPath() => Path()
  ..addOval(Rect.fromCircle(center: const Offset(50, 27), radius: 19))
  ..addOval(Rect.fromCircle(center: const Offset(29, 56), radius: 19))
  ..addOval(Rect.fromCircle(center: const Offset(71, 56), radius: 19))
  ..moveTo(47, 62)
  ..cubicTo(46, 74, 43, 84, 36, 92)
  ..lineTo(64, 92)
  ..cubicTo(57, 84, 54, 74, 53, 62)
  ..close();

final List<Path> _suitPaths = [
  spadePath(), // 0 ♠
  clubPath(), // 1 ♣
  diamondPath(), // 2 ♦
  heartPath(), // 3 ♥
];

/// The cached unit-box (100×100) path for a suit index (♠♣♦♥ = 0..3).
Path suitGlyphPath(int suit) => _suitPaths[suit];

/// Fills the suit glyph centered at [center], sized [size] (glyph box edge).
void paintSuitGlyph(
  Canvas canvas, {
  required int suit,
  required Offset center,
  required double size,
  required Paint paint,
}) {
  canvas.save();
  canvas.translate(center.dx - size / 2, center.dy - size / 2);
  canvas.scale(size / 100);
  canvas.drawPath(suitGlyphPath(suit), paint);
  canvas.restore();
}

/// Tiny painted suit icon — used by the trump plaque, login monogram and
/// scorecard divider. Static; never repaints.
class SuitIcon extends StatelessWidget {
  const SuitIcon({super.key, required this.suit, this.size = 16, this.color});

  final int suit;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c =
        color ?? (suit >= 2 ? Tokens.suitRedOnDark : Tokens.suitLightOnDark);
    return CustomPaint(
      size: Size.square(size),
      painter: _SuitIconPainter(suit: suit, color: c),
    );
  }
}

class _SuitIconPainter extends CustomPainter {
  const _SuitIconPainter({required this.suit, required this.color});

  final int suit;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    paintSuitGlyph(
      canvas,
      suit: suit,
      center: size.center(Offset.zero),
      size: size.shortestSide,
      paint: Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _SuitIconPainter oldDelegate) =>
      oldDelegate.suit != suit || oldDelegate.color != color;
}
