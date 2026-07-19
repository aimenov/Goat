/// Asset-free playing card widgets: [CardFace], [CardBack], [FaceDownCard].
/// Casino-elegance skin: ivory gradient faces, serif indices (Playfair),
/// vector suit glyphs (no emoji font), deep-green gold-lattice back.
/// Everything scales from [height]; default size ~64x92.
library;

import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/cards.dart';
import '../../core/render_mode.dart';
import '../theme/tokens.dart';
import 'suit_paths.dart';

const double cardAspect = 0.695; // width / height

class CardFace extends StatefulWidget {
  final int card;
  final double height;
  final bool selected;
  final bool dimmed;
  final VoidCallback? onTap;

  /// Draws the double gold border inside the face (trump plaque/reveal).
  final bool trumpStyle;

  const CardFace({
    super.key,
    required this.card,
    this.height = 92,
    this.selected = false,
    this.dimmed = false,
    this.onTap,
    this.trumpStyle = false,
  });

  @override
  State<CardFace> createState() => _CardFaceState();
}

class _CardFaceState extends State<CardFace> {
  bool _hovered = false;

  bool get _hoverCapable {
    if (widget.onTap == null) return false;
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.height;
    final width = height * cardAspect;
    final radius = height * 0.09;
    final shohaCard = isShoha(widget.card);
    final selected = widget.selected;
    final lifted = selected || _hovered;

    // Static fast path: non-interactive, unselected faces (trick chains,
    // trump plaque, won-pile sheet, flight spawns) need none of the implicit
    // animation machinery — two AnimatedContainers per card is 2 controllers
    // + tickers each (~25-35 cards on a busy table) plus decoration diffing
    // per rebuild. A plain Container with the resting decoration paints
    // identically. (_hovered can't be true here: hover requires onTap.)
    if (widget.onTap == null && !selected) {
      Widget result = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Tokens.ivory,
          borderRadius: BorderRadius.circular(radius),
          border: shohaCard
              ? Border.all(color: Tokens.gold400, width: 2)
              : Border.all(
                  color: Tokens.suitBlack.withValues(alpha: 0.2),
                  width: 0.8,
                ),
          // CPU mode drops all card shadows — blurs are the priciest
          // software-raster op and cards are the most numerous widget.
          boxShadow: cpuRenderMode
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x59000000), // black @ 0.35 — the resting shadow
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: _faceContent(height, radius, shohaCard),
      );
      if (widget.dimmed) result = Opacity(opacity: 0.45, child: result);
      return result;
    }

    final face = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Tokens.ivory,
        borderRadius: BorderRadius.circular(radius),
        border: selected
            ? Border.all(color: Tokens.gold300, width: 2.5)
            : shohaCard
                ? Border.all(color: Tokens.gold400, width: 2)
                : Border.all(
                    color: Tokens.suitBlack.withValues(alpha: 0.2),
                    width: 0.8,
                  ),
        // Web: one constant shadow (the resting values). Animating the blur
        // sigma/offset per card multiplies first-use blur-pipeline variants
        // during the deal burst on WebGL — the select/hover lift still reads
        // via the border + translate. Native keeps the animated shadow.
        boxShadow: cpuRenderMode
            ? null
            : kIsWeb
            ? const [
                BoxShadow(
                  color: Color(0x59000000), // black @ 0.35
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.5 : (lifted ? 0.45 : 0.35)),
                  blurRadius: lifted ? 8 : 4,
                  offset: Offset(0, lifted ? 4 : 2),
                ),
              ],
      ),
      child: _faceContent(height, radius, shohaCard),
    );

    Widget result = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      transform: Matrix4.translationValues(0, selected ? -8 : 0, 0),
      child: face,
    );
    if (widget.dimmed) result = Opacity(opacity: 0.45, child: result);
    if (widget.onTap != null) {
      result = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: result,
      );
    }
    // Hover-lift for web/desktop mouse users; a strict no-op on touch (the
    // platform gate plus MouseRegion's mouse-only enter/exit guarantee it).
    if (_hoverCapable) {
      result = MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedSlide(
          offset: _hovered ? const Offset(0, -0.06) : Offset.zero,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: result,
        ),
      );
    }
    return result;
  }

  /// Clipped painter + shoha ribbon — shared by the static and animated paths.
  Widget _faceContent(double height, double radius, bool shohaCard) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: CardFacePainter(
                card: widget.card,
                trumpStyle: widget.trumpStyle,
              ),
            ),
            if (shohaCard)
              Positioned(
                left: 0,
                right: 0,
                bottom: height * 0.17,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: height * 0.012),
                  decoration: cpuRenderMode
                      // Solid gold ribbon: no gradient fill in CPU mode.
                      ? const BoxDecoration(color: Tokens.gold400)
                      : const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Tokens.gold200, Tokens.gold500],
                          ),
                        ),
                  child: Text(
                    'ШОХА',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: Tokens.sansFamily,
                      color: Tokens.suitBlack,
                      fontSize: height * 0.10,
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
}

/// Paints the entire card face: ivory gradient, inner hairline, Playfair
/// corner indices over painted suit glyphs, the big center pip and (for the
/// trump display) a double gold border. Paints once per card; identical
/// params never repaint.
@visibleForTesting
class CardFacePainter extends CustomPainter {
  const CardFacePainter({required this.card, this.trumpStyle = false});

  final int card;
  final bool trumpStyle;

  /// Rank TextPainters are LRU-cached: flights re-instantiate faces often
  /// and TextPainter layout is the expensive part of a face paint.
  static final LinkedHashMap<(int, int, int), TextPainter> _rankCache =
      LinkedHashMap();
  // Above the live working set (9 ranks × 2 inks × ~7 sizes) so busy scenes
  // don't cycle evictions.
  static const _rankCacheLimit = 160;

  static TextPainter _rankPainter(int rankIndex, Color ink, double height) {
    final key = (rankIndex, ink.toARGB32(), height.round());
    final cached = _rankCache.remove(key);
    if (cached != null) {
      _rankCache[key] = cached; // refresh LRU position
      return cached;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: ranks[rankIndex],
        style: TextStyle(
          fontFamily: Tokens.serifFamily,
          fontWeight: FontWeight.w700,
          fontSize: height * 0.18,
          color: ink,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _rankCache[key] = tp;
    if (_rankCache.length > _rankCacheLimit) {
      _rankCache.remove(_rankCache.keys.first)?.dispose();
    }
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = h * 0.09;

    // 1. Ivory fill — gradient on GPU, flat in CPU mode (gradient fills are
    //    per-pixel shader evaluations in software).
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      cpuRenderMode
          ? (Paint()..color = Tokens.ivory)
          : (Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Tokens.ivory, Tokens.ivoryWarm],
              ).createShader(Offset.zero & size)),
    );

    // 2. Inner hairline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1.5, 1.5, w - 3, h - 3),
        Radius.circular(radius - 1),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.7, h * 0.01)
        ..color = Tokens.ivoryEdge,
    );

    // 3. Trump display: double gold border inside the face.
    if (trumpStyle) {
      final k = h / 92; // scale strokes with height
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(2 * k, 2 * k, w - 4 * k, h - 4 * k),
          Radius.circular(radius - k),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.9, 1.6 * k)
          ..color = Tokens.gold400,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(5 * k, 5 * k, w - 10 * k, h - 10 * k),
          Radius.circular(max(2, radius - 3 * k)),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          // clamp so the inner line stays visible on mini (36px) trump plaques
          ..strokeWidth = max(0.8, 0.8 * k)
          ..color = Tokens.gold600,
      );
    }

    final red = isRed(card);
    final ink = red ? Tokens.suitRed : Tokens.suitBlack;
    final suit = suitOf(card);
    final inkPaint = Paint()..color = ink;

    // 4. Corner indices: serif rank above a painted suit glyph; the
    //    bottom-right corner is the same drawing rotated 180°.
    final rank = _rankPainter(rankOf(card), ink, h);
    final glyphSize = h * 0.13;
    void corner() {
      final left = w * 0.07;
      final top = h * 0.045;
      rank.paint(canvas, Offset(left, top));
      paintSuitGlyph(
        canvas,
        suit: suit,
        center: Offset(
          left + rank.width / 2,
          top + rank.height + glyphSize * 0.62,
        ),
        size: glyphSize,
        paint: inkPaint,
      );
    }

    corner();
    canvas.save();
    canvas.translate(w, h);
    canvas.rotate(pi);
    corner();
    canvas.restore();

    // 5. Center pip, with a subtle letterpress shadow for red suits.
    final pipSize = h * 0.42;
    final center = Offset(w / 2, h / 2);
    if (red) {
      paintSuitGlyph(
        canvas,
        suit: suit,
        center: center + const Offset(0, 1.2),
        size: pipSize,
        paint: Paint()..color = Colors.black.withValues(alpha: 0.15),
      );
    }
    paintSuitGlyph(
      canvas,
      suit: suit,
      center: center,
      size: pipSize,
      paint: inkPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CardFacePainter oldDelegate) =>
      oldDelegate.card != card || oldDelegate.trumpStyle != trumpStyle;
}

class CardBack extends StatelessWidget {
  final double height;

  const CardBack({super.key, this.height = 92});

  @override
  Widget build(BuildContext context) {
    final width = height * cardAspect;
    final radius = height * 0.09;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.black38, width: 0.8),
        boxShadow: cpuRenderMode ? null : const [Tokens.shadowCard],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(size: Size(width, height), painter: const _LatticePainter()),
      ),
    );
  }
}

/// A [CardBack] with a slight, seed-deterministic random rotation.
class FaceDownCard extends StatelessWidget {
  final double height;
  final int seed;

  const FaceDownCard({super.key, this.height = 92, this.seed = 0});

  @override
  Widget build(BuildContext context) {
    final angle = (Random(seed * 31 + 7).nextDouble() - 0.5) * 0.18;
    return Transform.rotate(angle: angle, child: CardBack(height: height));
  }
}

/// Card back: deep-green gradient, gold diagonal lattice, an eight-petal gold
/// rosette and a double gold hairline frame. Static — never repaints.
class _LatticePainter extends CustomPainter {
  const _LatticePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Base: vertical deep-green gradient (flat fill in CPU mode).
    canvas.drawRect(
      Offset.zero & size,
      cpuRenderMode
          ? (Paint()..color = Tokens.felt600)
          : (Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Tokens.felt500, Tokens.felt800],
              ).createShader(Offset.zero & size)),
    );

    // 2. Gold diagonal lattice.
    final line = Paint()
      ..color = Tokens.gold600.withValues(alpha: 0.32)
      ..strokeWidth = max(0.6, h * 0.012);
    final step = w / 4;
    for (var x = -h; x < w + h; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + h, h), line);
      canvas.drawLine(Offset(x + h, 0), Offset(x, h), line);
    }

    // 3. Rosette: gold ring, 8 stroked petals, tiny filled center.
    final center = size.center(Offset.zero);
    final r = w * 0.30;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Tokens.gold400.withValues(alpha: 0.5),
    );
    final petal = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(-r * 0.18, -r * 0.45, 0, -r * 0.85)
      ..quadraticBezierTo(r * 0.18, -r * 0.45, 0, 0);
    final petalPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Tokens.gold300.withValues(alpha: 0.45);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    for (var i = 0; i < 8; i++) {
      canvas.drawPath(petal, petalPaint);
      canvas.rotate(pi / 4);
    }
    canvas.restore();
    canvas.drawCircle(center, r * 0.12, Paint()..color = Tokens.gold400);

    // 4. Double gold hairline frame.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(2.5, 2.5, w - 5, h - 5),
        Radius.circular(h * 0.06),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tokens.gold400.withValues(alpha: 0.6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5, 5, w - 10, h - 10),
        Radius.circular(h * 0.05),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tokens.gold600.withValues(alpha: 0.4),
    );
  }

  @override
  bool shouldRepaint(covariant _LatticePainter oldDelegate) => false;
}
