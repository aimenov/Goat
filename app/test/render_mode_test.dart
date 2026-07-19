/// CPU-render-mode degradations: the reduced-effects branches gated on
/// [cpuRenderMode] never execute on the VM by default (the stub reports GPU),
/// so these tests force the mode via [debugSetCpuRenderMode] and assert the
/// expensive effects are actually dropped — and still present in GPU mode.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goat_app/core/render_mode.dart';
import 'package:goat_app/features/game/anim/confetti.dart';
import 'package:goat_app/features/game/anim/felt_sweep.dart';
import 'package:goat_app/shared/cards/card_face.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

/// True when any Container/DecoratedBox under [root] paints a box shadow.
bool _hasBoxShadow(WidgetTester tester, Finder root) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(of: root, matching: find.byType(DecoratedBox)),
  );
  return boxes.any((b) {
    final d = b.decoration;
    return d is BoxDecoration && (d.boxShadow?.isNotEmpty ?? false);
  });
}

void main() {
  tearDown(() => debugSetCpuRenderMode(null));

  testWidgets('CPU mode: static CardFace renders without box shadows', (tester) async {
    debugSetCpuRenderMode(true);
    await tester.pumpWidget(_host(const CardFace(card: 5)));
    expect(_hasBoxShadow(tester, find.byType(CardFace)), isFalse);
  });

  testWidgets('GPU mode: static CardFace keeps its resting shadow', (tester) async {
    debugSetCpuRenderMode(false);
    await tester.pumpWidget(_host(const CardFace(card: 5)));
    expect(_hasBoxShadow(tester, find.byType(CardFace)), isTrue);
  });

  testWidgets('CPU mode: FeltSweep skips the sweep entirely', (tester) async {
    debugSetCpuRenderMode(true);
    await tester.pumpWidget(_host(const FeltSweep()));
    expect(
      find.descendant(of: find.byType(FeltSweep), matching: find.byType(CustomPaint)),
      findsNothing,
    );
  });

  testWidgets('GPU mode: FeltSweep paints its band', (tester) async {
    debugSetCpuRenderMode(false);
    await tester.pumpWidget(_host(const FeltSweep()));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.descendant(of: find.byType(FeltSweep), matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
  });

  testWidgets('CPU mode: ConfettiBurst caps particles at 24', (tester) async {
    debugSetCpuRenderMode(true);
    await tester.pumpWidget(_host(const ConfettiBurst(particleCount: 80)));
    await tester.pump(const Duration(milliseconds: 50));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .expand((p) => [p.painter, p.foregroundPainter])
        .whereType<ConfettiPainter>()
        .single;
    expect(painter.particles.length, 24);
  });

  testWidgets('GPU mode: ConfettiBurst keeps the requested particle count', (tester) async {
    debugSetCpuRenderMode(false);
    await tester.pumpWidget(_host(const ConfettiBurst(particleCount: 80)));
    await tester.pump(const Duration(milliseconds: 50));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .expand((p) => [p.painter, p.foregroundPainter])
        .whereType<ConfettiPainter>()
        .single;
    expect(painter.particles.length, 80);
  });
}
