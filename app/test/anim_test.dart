import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/features/game/anim/confetti.dart';
import 'package:goat_app/features/game/anim/flight_math.dart';
import 'package:goat_app/features/game/anim/motion_widgets.dart';

void main() {
  group('FlightPath', () {
    test('starts at from and ends at to', () {
      final path = FlightPath.arc(const Offset(10, 20), const Offset(200, 400), bend: 0.15);
      expect(path.at(0), const Offset(10, 20));
      expect(path.at(1), const Offset(200, 400));
    });

    test('control point sits perpendicular to the segment at bend*distance', () {
      // Horizontal segment of length 100 with bend 0.1 -> control (50, 10).
      final path = FlightPath.arc(Offset.zero, const Offset(100, 0), bend: 0.1);
      expect(path.control.dx, closeTo(50, 1e-9));
      expect(path.control.dy, closeTo(10, 1e-9));
      // Midpoint of the Bezier is pulled halfway toward the control point.
      final mid = path.at(0.5);
      expect(mid.dx, closeTo(50, 1e-9));
      expect(mid.dy, closeTo(5, 1e-9));
    });

    test('jittered paths are seed-deterministic and bounded', () {
      final a = FlightPath.jittered(Offset.zero, const Offset(0, 100), Random(42));
      final b = FlightPath.jittered(Offset.zero, const Offset(0, 100), Random(42));
      expect(a.control, b.control);
      // Perpendicular offset never exceeds maxBend * distance.
      for (var seed = 0; seed < 50; seed++) {
        final p = FlightPath.jittered(Offset.zero, const Offset(0, 100), Random(seed),
            maxBend: 0.16);
        expect(p.control.dx.abs(), lessThanOrEqualTo(16.0 + 1e-9));
        expect(p.control.dy, closeTo(50, 1e-9));
      }
    });

    test('degenerate zero-length flight stays put', () {
      final p = FlightPath.arc(const Offset(5, 5), const Offset(5, 5), bend: 0.2);
      expect(p.at(0.5), const Offset(5, 5));
    });
  });

  group('StaggerScheduler', () {
    test('hands out increasing delays within a burst and resets after idle', () {
      var now = DateTime(2026, 1, 1);
      final scheduler = StaggerScheduler(now: () => now);
      const gap = Duration(milliseconds: 40);
      expect(scheduler.reserve(gap), Duration.zero);
      expect(scheduler.reserve(gap), const Duration(milliseconds: 40));
      expect(scheduler.reserve(gap), const Duration(milliseconds: 80));
      // After real time passes the schedule catches up to "now".
      now = now.add(const Duration(seconds: 2));
      expect(scheduler.reserve(gap), Duration.zero);
      scheduler.reset();
      expect(scheduler.reserve(gap), Duration.zero);
    });
  });

  group('Confetti', () {
    test('generates a deterministic, bounded particle set', () {
      final a = ConfettiParticle.generate(80, Random(7));
      final b = ConfettiParticle.generate(80, Random(7));
      expect(a.length, 80);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].x, b[i].x);
        expect(a[i].color, b[i].color);
        expect(a[i].x, inInclusiveRange(0.0, 1.0));
        expect(a[i].speed, inInclusiveRange(0.9, 1.5));
        expect(ConfettiParticle.palette, contains(a[i].color));
      }
    });

    test('painter paints without errors and repaints only on progress change', () {
      final particles = ConfettiParticle.generate(80, Random(3));
      for (final progress in [0.0, 0.4, 0.8, 1.0]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        ConfettiPainter(particles: particles, progress: progress)
            .paint(canvas, const Size(400, 800));
        recorder.endRecording().dispose();
      }
      final p1 = ConfettiPainter(particles: particles, progress: 0.4);
      final p2 = ConfettiPainter(particles: particles, progress: 0.5);
      final p3 = ConfettiPainter(particles: particles, progress: 0.5);
      expect(p2.shouldRepaint(p1), isTrue);
      expect(p3.shouldRepaint(p2), isFalse);
    });
  });

  group('CountUpText', () {
    testWidgets('counts from zero up to the final value', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CountUpText(
              value: 42,
              prefix: '+',
              duration: Duration(milliseconds: 300),
            ),
          ),
        ),
      );
      expect(find.text('+0'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('+42'), findsOneWidget);
    });

    testWidgets('rolls from a starting value into the total', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CountUpText(
              from: 10,
              value: 14,
              prefix: '= ',
              duration: Duration(milliseconds: 300),
            ),
          ),
        ),
      );
      expect(find.text('= 10'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('= 14'), findsOneWidget);
    });
  });
}
