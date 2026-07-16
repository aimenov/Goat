/// Pure math for card flights: quadratic Bezier paths with seeded jitter
/// and a wall-clock stagger scheduler for dealing bursts. No Flutter imports
/// beyond `dart:ui` — unit-testable without a widget tree.
library;

import 'dart:math';
import 'dart:ui';

/// A quadratic Bezier from [from] to [to] whose control point is pushed
/// sideways off the straight line, giving every flight a slight arc.
class FlightPath {
  final Offset from;
  final Offset to;
  final Offset control;

  const FlightPath({
    required this.from,
    required this.to,
    required this.control,
  });

  /// Control point at the midpoint, offset perpendicular to the segment by
  /// `bend * distance`. [bend] is signed; typical values are in [-0.2, 0.2].
  factory FlightPath.arc(Offset from, Offset to, {double bend = 0.12}) {
    final mid = Offset.lerp(from, to, 0.5)!;
    final delta = to - from;
    final dist = delta.distance;
    if (dist < 1e-3) return FlightPath(from: from, to: to, control: mid);
    final normal = Offset(-delta.dy, delta.dx) / dist;
    return FlightPath(
      from: from,
      to: to,
      control: mid + normal * (bend * dist),
    );
  }

  /// Seeded jitter: the bend varies deterministically with [rng], so no two
  /// throws look identical but replays with the same seed do.
  factory FlightPath.jittered(
    Offset from,
    Offset to,
    Random rng, {
    double maxBend = 0.16,
  }) => FlightPath.arc(from, to, bend: (rng.nextDouble() * 2 - 1) * maxBend);

  /// Point on the curve at parameter [t] in [0, 1].
  Offset at(double t) {
    final u = 1 - t;
    return from * (u * u) + control * (2 * u * t) + to * (t * t);
  }
}

/// A random angle in [-maxRadians, maxRadians].
double jitterAngle(Random rng, double maxRadians) =>
    (rng.nextDouble() * 2 - 1) * maxRadians;

/// Hands out increasing start delays so flights scheduled in the same burst
/// leave their source [gap] apart. Wall-clock based; inject [now] in tests.
class StaggerScheduler {
  StaggerScheduler({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _next;

  /// Reserves the next slot and returns how long the caller should wait.
  Duration reserve(Duration gap) {
    final t = _now();
    var next = _next;
    if (next == null || next.isBefore(t)) next = t;
    final delay = next.difference(t);
    _next = next.add(gap);
    return delay;
  }

  void reset() => _next = null;
}
