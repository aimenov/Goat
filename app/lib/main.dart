import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/monetization.dart';
import 'core/services/sound.dart';
import 'features/achievements/achievements_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/leaderboard/leaderboard_screen.dart';
import 'features/lobby/lobby_screen.dart';
import 'features/game/table_screen.dart';
import 'features/shop/shop_screen.dart';
import 'shared/theme/app_theme.dart';

void main() {
  runApp(ProviderScope(
    // Installs the real ad/IAP implementations behind the C1 hook seams;
    // on web/desktop the hooks stay null and every surface self-hides.
    overrides: monetizationOverrides,
    child: const GoatApp(),
  ));
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
    GoRoute(
      path: '/shop',
      pageBuilder: (context, state) =>
          buildFadeThrough(state, const ShopScreen()),
    ),
    GoRoute(
      path: '/leaderboard',
      pageBuilder: (context, state) =>
          buildFadeThrough(state, const LeaderboardScreen()),
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
    // IAP: attach the purchase-stream listener right after the first frame —
    // cheap, but it must be early so purchases the store redelivers (paid but
    // never redeemed) are picked up. Ads init is deferred to the lobby.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(monetizationProvider); // wake the event/redeem bridge first
      ref.read(iapServiceProvider).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Козёл',
      debugShowCheckedModeBanner: false,
      theme: buildCasinoTheme(),
      routerConfig: _router,
      builder: (context, child) {
        // Permanently mounted: swapping this wrapper out after the first tap
        // changed the widget type above the Navigator and forced a full
        // reparent (duplicate-GlobalKey risk mid-transition). Only the
        // callback is gated.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            if (_soundUnlocked) return;
            _soundUnlocked = true; // no rebuild needed — nothing visual changes
            ref.read(soundServiceProvider).markUnlocked();
          },
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
