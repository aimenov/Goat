/// Cosmetic theming: styled card backs / felts build with the right painter
/// styles, shouldRepaint keys off instance identity (const canonicalization),
/// and the CPU-mode branches accept non-classic palettes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/render_mode.dart';
import 'package:goat_app/shared/cards/card_face.dart';
import 'package:goat_app/shared/felt/felt_background.dart';
import 'package:goat_app/shared/theme/cosmetic_styles.dart';

/// The first [LatticePainter] in the tree (CustomPaint is ubiquitous;
/// filter by painter type).
LatticePainter latticeOf(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (paint.painter is LatticePainter) return paint.painter as LatticePainter;
  }
  fail('no LatticePainter in the tree');
}

FeltPainter feltOf(WidgetTester tester) {
  for (final paint in tester.widgetList<CustomPaint>(find.byType(CustomPaint))) {
    if (paint.painter is FeltPainter) return paint.painter as FeltPainter;
  }
  fail('no FeltPainter in the tree');
}

void main() {
  tearDown(() => debugSetCpuRenderMode(null));

  testWidgets('CardBack defaults to the classic style', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Center(child: CardBack(height: 76))),
    );
    expect(identical(latticeOf(tester).style, CardBackStyle.classic), isTrue);
  });

  testWidgets('CardBack builds with the burgundy style threaded through',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: CardBack(height: 76, style: CardBackStyle.burgundy),
        ),
      ),
    );
    expect(latticeOf(tester).style.id, 'back_burgundy');
    expect(tester.takeException(), isNull);
  });

  testWidgets('FaceDownCard threads its style into the painter',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: FaceDownCard(height: 32, seed: 3, style: CardBackStyle.midnight),
        ),
      ),
    );
    expect(latticeOf(tester).style.id, 'back_midnight');
  });

  test('LatticePainter.shouldRepaint: identical const style false, cross-style true',
      () {
    const a = LatticePainter(style: CardBackStyle.burgundy);
    // Const canonicalization: the "second" instance IS the same style object.
    const b = LatticePainter(style: CardBackStyle.burgundy);
    const classic = LatticePainter();
    expect(a.shouldRepaint(b), isFalse);
    expect(b.shouldRepaint(a), isFalse);
    expect(a.shouldRepaint(classic), isTrue);
    expect(classic.shouldRepaint(a), isTrue);
  });

  test('FeltPainter.shouldRepaint: theme identity plus the light center', () {
    const a = FeltPainter(theme: FeltTheme.midnight);
    const b = FeltPainter(theme: FeltTheme.midnight);
    const classic = FeltPainter();
    const moved = FeltPainter(lightCenter: Alignment(0, -0.4));
    expect(a.shouldRepaint(b), isFalse);
    expect(a.shouldRepaint(classic), isTrue);
    expect(classic.shouldRepaint(moved), isTrue);
  });

  testWidgets('themed FeltBackground builds and paints its theme',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FeltBackground(
          theme: FeltTheme.burgundy,
          child: SizedBox.expand(),
        ),
      ),
    );
    expect(feltOf(tester).theme.id, 'felt_burgundy');
    expect(tester.takeException(), isNull);
  });

  testWidgets('CPU render mode: themed flat branches build cleanly',
      (tester) async {
    debugSetCpuRenderMode(true);
    await tester.pumpWidget(
      const MaterialApp(
        home: FeltBackground(
          theme: FeltTheme.cabbage,
          child: Center(
            child: CardBack(height: 76, style: CardBackStyle.goldenGoat),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(latticeOf(tester).style.id, 'back_golden_goat');
    expect(feltOf(tester).theme.id, 'felt_cabbage');
    expect(tester.takeException(), isNull);
  });

  test('byId round-trips every catalog id and rejects unknowns', () {
    for (final style in CardBackStyle.all) {
      expect(identical(CardBackStyle.byId(style.id), style), isTrue);
    }
    for (final theme in FeltTheme.all) {
      expect(identical(FeltTheme.byId(theme.id), theme), isTrue);
    }
    expect(CardBackStyle.byId('back_hologram'), isNull);
    expect(FeltTheme.byId('felt_lava'), isNull);
  });

  test('classic palettes mirror the pre-cosmetics constants', () {
    // Byte-identical classic rendering: same colors the painters hardcoded.
    expect(CardBackStyle.classic.top, const Color(0xFF255A3B)); // felt500
    expect(CardBackStyle.classic.bottom, const Color(0xFF0F2718)); // felt800
    expect(CardBackStyle.classic.flat, const Color(0xFF1C452D)); // felt600
    expect(CardBackStyle.classic.accent, const Color(0xFFD4AF37)); // gold400
    expect(CardBackStyle.classic.accentSoft, const Color(0xFFE6C36A)); // gold300
    expect(CardBackStyle.classic.accentDeep, const Color(0xFF8C6D1F)); // gold600
    expect(FeltTheme.classic.light, const Color(0xFF1C452D)); // felt600
    expect(FeltTheme.classic.mid, const Color(0xFF153522)); // felt700
    expect(FeltTheme.classic.base, const Color(0xFF0F2718)); // felt800
    expect(FeltTheme.classic.deep, const Color(0xFF0A1B10)); // felt900
    expect(FeltTheme.classic.flat, FeltTheme.classic.mid);
  });
}
