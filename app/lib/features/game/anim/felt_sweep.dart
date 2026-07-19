/// One-shot light sweep across the felt on deal start: a soft rotated gold
/// band travels the table once (700 ms) and the widget goes inert. Re-key
/// (ValueKey(generation)) to replay. RepaintBoundary + IgnorePointer keep the
/// per-frame repaint isolated; the band shader is created once per size.
library;

import 'dart:math' show pi;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../core/render_mode.dart';
import '../../../shared/theme/tokens.dart';

class FeltSweep extends StatefulWidget {
  const FeltSweep({super.key});

  @override
  State<FeltSweep> createState() => _FeltSweepState();
}

class _FeltSweepState extends State<FeltSweep>
    with SingleTickerProviderStateMixin {
  // Nullable, not `late final`: in CPU mode no controller must ever exist —
  // a lazy field would be created on first touch in dispose(), where
  // createTicker's ancestor lookup throws during unmount.
  AnimationController? _controller;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // CPU mode: a full-screen band repainting every frame right at deal
    // start is the worst software-raster moment — skip the sweep entirely
    // (no controller is created; build stays SizedBox.shrink).
    if (cpuRenderMode) {
      _done = true;
      return;
    }
    final controller = _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    controller.forward().whenCompleteOrCancel(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          // Non-null here: _done is true from initState whenever no
          // controller was created.
          painter: _SweepPainter(animation: _controller!),
        ),
      ),
    );
  }
}

class _SweepPainter extends CustomPainter {
  _SweepPainter({required this.animation}) : super(repaint: animation);

  final Animation<double> animation;

  // Shader + paint cached per size; the per-frame work is one canvas
  // translate/rotate and a rect draw — zero allocations.
  Paint? _bandPaint;
  Size _shaderSize = Size.zero;

  static const _tilt = -18 * pi / 180;

  Paint _paintFor(Size size) {
    if (_bandPaint != null && _shaderSize == size) return _bandPaint!;
    if (kIsWeb) {
      // Web: same band, same motion, but a solid low-alpha gold fill — the
      // rotated-clip × linear-gradient combo would compile a fresh fragment
      // shader variant right at deal start (peak compile pressure).
      _bandPaint = Paint()..color = Tokens.gold100.withValues(alpha: 0.05);
    } else {
      final bandW = size.width * 0.35;
      _bandPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            Tokens.gold100.withValues(alpha: 0),
            Tokens.gold100.withValues(alpha: 0.10),
            Tokens.gold100.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(-bandW / 2, 0, bandW, 1));
    }
    _shaderSize = size;
    return _bandPaint!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = Curves.easeInOut.transform(animation.value.clamp(0.0, 1.0));
    final bandW = size.width * 0.35;
    final x = size.width * (-0.5 + 2.0 * t);
    canvas.save();
    canvas.translate(x, size.height / 2);
    canvas.rotate(_tilt);
    final reach = size.height; // long enough to cover the rotated screen
    canvas.drawRect(
      Rect.fromLTWH(-bandW / 2, -reach, bandW, reach * 2),
      _paintFor(size),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SweepPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
