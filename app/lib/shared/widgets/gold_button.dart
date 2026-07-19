/// Gold-filled primary action button: metallic top-lit gradient, pressed
/// scale micro-interaction. Owns no ticker — [AnimatedScale] only animates
/// on press/release.
library;

import 'package:flutter/material.dart';

import '../../core/render_mode.dart';
import '../theme/tokens.dart';

class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _pressed = false;

  static final ButtonStyle _innerStyle = ButtonStyle(
    // The gradient DecoratedBox behind supplies the fill.
    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? Tokens.onGold.withValues(alpha: 0.55)
          : Tokens.onGold,
    ),
    overlayColor:
        WidgetStatePropertyAll(Tokens.gold100.withValues(alpha: 0.14)),
    shadowColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
  );

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final button = widget.icon == null
        ? FilledButton(
            style: _innerStyle,
            onPressed: widget.onPressed,
            child: widget.child,
          )
        : FilledButton.icon(
            style: _innerStyle,
            onPressed: widget.onPressed,
            icon: widget.icon,
            label: widget.child,
          );
    return Listener(
      onPointerDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.965 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // CPU mode: solid gold instead of the metallic gradient, and no
            // drop shadow (blur is the priciest software-raster op).
            gradient: enabled && !cpuRenderMode
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Tokens.gold200, Tokens.gold500],
                  )
                : null,
            color: enabled
                ? (cpuRenderMode ? Tokens.gold400 : null)
                : Tokens.gold600.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(Tokens.r10),
            border: Border.all(
              color: Tokens.gold600.withValues(alpha: enabled ? 1 : 0.4),
              width: 1,
            ),
            boxShadow:
                enabled && !cpuRenderMode ? const [Tokens.shadowCard] : null,
          ),
          child: button,
        ),
      ),
    );
  }
}
