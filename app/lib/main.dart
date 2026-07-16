import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/services/sound.dart';
import 'features/achievements/achievements_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/lobby/lobby_screen.dart';
import 'features/game/table_screen.dart';
import 'shared/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: GoatApp()));
}

/// M3 fade-through without the `animations` package: the outgoing screen
/// fades out over the first 35%, the incoming one fades in and settles from
/// a 0.98 scale.
CustomTransitionPage<void> buildFadeThrough(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fadeIn = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
      );
      final scaleIn = Tween<double>(begin: 0.98, end: 1).animate(
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      );
      final fadeOut = ReverseAnimation(
        CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0, 0.35, curve: Curves.easeIn),
        ),
      );
      return FadeTransition(
        opacity: fadeIn,
        child: FadeTransition(
          opacity: fadeOut,
          child: ScaleTransition(scale: scaleIn, child: child),
        ),
      );
    },
    child: child,
  );
}

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          buildFadeThrough(state, const LoginScreen()),
    ),
    GoRoute(
      path: '/lobby',
      pageBuilder: (context, state) =>
          buildFadeThrough(state, const LobbyScreen()),
    ),
    GoRoute(
      path: '/table',
      pageBuilder: (context, state) =>
          buildFadeThrough(state, const TableScreen()),
    ),
    GoRoute(
      path: '/achievements',
      pageBuilder: (context, state) =>
          buildFadeThrough(state, const AchievementsScreen()),
    ),
  ],
);

class GoatApp extends ConsumerStatefulWidget {
  const GoatApp({super.key});

  @override
  ConsumerState<GoatApp> createState() => _GoatAppState();
}

class _GoatAppState extends ConsumerState<GoatApp> {
  // Web autoplay gate: dropped from the tree after the first pointer event.
  bool _soundUnlocked = false;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: preloads pools & prefs, never blocks the first frame.
    ref.read(soundServiceProvider).init();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Козёл',
      debugShowCheckedModeBanner: false,
      theme: buildCasinoTheme(),
      routerConfig: _router,
      builder: (context, child) {
        final content = child ?? const SizedBox.shrink();
        if (_soundUnlocked) return content;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            ref.read(soundServiceProvider).markUnlocked();
            setState(() => _soundUnlocked = true);
          },
          child: content,
        );
      },
    );
  }
}
