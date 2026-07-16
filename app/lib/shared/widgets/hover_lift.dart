/// Mouse hover-lift for web/desktop: the child rises slightly under the
/// pointer. Strict no-op on touch platforms (platform gate + MouseRegion's
/// mouse-only enter/exit). Tickerless at rest.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HoverLift extends StatefulWidget {
  const HoverLift({
    super.key,
    required this.child,
    this.lift = const Offset(0, -0.04),
  });

  final Widget child;

  /// Fractional [AnimatedSlide] offset while hovered.
  final Offset lift;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  bool get _hoverCapable {
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
    if (!_hoverCapable) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        offset: _hovered ? widget.lift : Offset.zero,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
