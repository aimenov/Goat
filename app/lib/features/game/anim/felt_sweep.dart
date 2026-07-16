/// One-shot light sweep across the felt on deal start: a soft rotated gold
/// band travels the table once (700 ms) and the widget goes inert. Re-key
/// (ValueKey(generation)) to replay. RepaintBoundary + IgnorePointer keep the
/// per-frame repaint isolated; the band shader is created once per size.
library;

import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../../../shared/theme/tokens.dart';

class FeltSweep extends StatefulWidget {
  const FeltSweep({super.key});

  @override
  State<FeltSweep> createState() => _FeltSweepState();
}

class _FeltSweepState extends State<FeltSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenCompleteOrCancel(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _SweepPainter(animation: _controller),
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
    final bandW = size.width * 0.35;
    _bandPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Tokens.gold100.withValues(alpha: 0),
          Tokens.gold100.withValues(alpha: 0.10),
          Tokens.gold100.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromLTWH(-bandW / 2, 0, bandW, 1));
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
