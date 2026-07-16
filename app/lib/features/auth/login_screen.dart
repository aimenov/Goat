/// Guest login: pick a nickname and play.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/session.dart';
import '../../shared/cards/suit_paths.dart';
import '../../shared/felt/felt_background.dart';
import '../../shared/theme/tokens.dart';
import '../../shared/widgets/gold_button.dart';
import '../game/anim/motion_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _nicknameController = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Prefill the nickname once the stored identity loads.
    ref.listenManual(identityProvider, fireImmediately: true, (previous, next) {
      final nickname = next.value?.nickname;
      if (nickname != null && nickname.isNotEmpty && _nicknameController.text.isEmpty) {
        _nicknameController.text = nickname;
      }
    });
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите ник')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(identityProvider.notifier).login(nickname);
      if (mounted) context.go('/lobby');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Tokens.dangerDeep,
            content: Text('Не удалось войти. Проверьте интернет-соединение.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(identityProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: FeltBackground(
        lightCenter: const Alignment(0, -0.3),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Tokens.s6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const StompIn(
                      fromScale: 1.15,
                      fromTilt: -0.06,
                      child: Center(child: _MonogramCard()),
                    ),
                    const SizedBox(height: Tokens.s4),
                    const Text(
                      'Козёл',
                      textAlign: TextAlign.center,
                      style: Tokens.displaySerif,
                    ),
                    const SizedBox(height: Tokens.s2),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Tokens.gold600.withValues(alpha: 0.4),
                            thickness: 1,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: Tokens.s3),
                          child: Text(
                            'Карточная игра онлайн',
                            style: TextStyle(
                              color: Tokens.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Tokens.gold600.withValues(alpha: 0.4),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Tokens.s7),
                    TextField(
                      controller: _nicknameController,
                      enabled: !_busy && !identity.isLoading,
                      maxLength: 20,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _login(),
                      decoration: const InputDecoration(
                        labelText: 'Ваш ник',
                        counterText: '',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: Tokens.s4),
                    SizedBox(
                      height: 52,
                      child: GoldButton(
                        onPressed: _busy || identity.isLoading ? null : _login,
                        child: _busy
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Tokens.onGold,
                                ),
                              )
                            : const Text('Играть', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The gold monogram card: an ivory playing card with a double gold border,
/// a Playfair «К» and small painted suit pips in the four inner corners.
class _MonogramCard extends StatelessWidget {
  const _MonogramCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 172,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.r14),
        boxShadow: const [Tokens.shadowRaised],
      ),
      child: const CustomPaint(painter: _MonogramPainter()),
    );
  }
}

class _MonogramPainter extends CustomPainter {
  const _MonogramPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Ivory gradient face.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(Tokens.r14),
      ),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tokens.ivory, Tokens.ivoryWarm],
        ).createShader(Offset.zero & size),
    );

    // Double gold border (same recipe as trump cards).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(3, 3, w - 6, h - 6),
        const Radius.circular(Tokens.r14 - 2),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Tokens.gold400,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(8, 8, w - 16, h - 16),
        const Radius.circular(Tokens.r14 - 6),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Tokens.gold600,
    );

    // Playfair «К» monogram.
    final tp = TextPainter(
      text: const TextSpan(
        text: 'К',
        style: TextStyle(
          fontFamily: Tokens.serifFamily,
          fontWeight: FontWeight.w800,
          fontSize: 64,
          color: Tokens.gold500,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset((w - tp.width) / 2, (h - tp.height) / 2),
    );

    // Painted suit pips in the four inner corners: ♠ ♣ (top), ♦ ♥ (bottom).
    const pip = 10.0;
    const inset = 17.0;
    final black = Paint()..color = Tokens.suitBlack;
    final red = Paint()..color = Tokens.suitRed;
    paintSuitGlyph(canvas,
        suit: 0, center: const Offset(inset, inset), size: pip, paint: black);
    paintSuitGlyph(canvas,
        suit: 1, center: Offset(w - inset, inset), size: pip, paint: black);
    paintSuitGlyph(canvas,
        suit: 2, center: Offset(inset, h - inset), size: pip, paint: red);
    paintSuitGlyph(canvas,
        suit: 3, center: Offset(w - inset, h - inset), size: pip, paint: red);
  }

  @override
  bool shouldRepaint(covariant _MonogramPainter oldDelegate) => false;
}
