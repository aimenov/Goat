/// Interstitial wiring on the table screen, driven through a recording fake
/// [AdsService]: the capping counter ticks once per gameOver transition, the
/// ad request happens ONLY on the game-over «Выйти» exit, and a non-game-over
/// leave (connecting-overlay escape) never asks for one.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:goat_app/core/game/game_controller.dart';
import 'package:goat_app/core/game/models.dart';
import 'package:goat_app/core/services/ads/ads_service.dart';
import 'package:goat_app/features/game/table_screen.dart';

class FakeGameController extends GameController {
  FakeGameController(this._initial);

  final GameUiState _initial;
  final _fakeEvents = StreamController<TableEvent>.broadcast();

  @override
  GameUiState build() => _initial;

  @override
  Stream<TableEvent> get tableEvents => _fakeEvents.stream;

  void setState(GameUiState next) => state = next;
}

class RecordingAdsService extends NoopAdsService {
  int gamesFinished = 0;
  final List<InterstitialTrigger> interstitialRequests = [];

  @override
  void notifyGameFinished() => gamesFinished++;

  @override
  Future<bool> maybeShowInterstitial(InterstitialTrigger trigger) async {
    interstitialRequests.add(trigger);
    return false;
  }
}

GameUiState gameOverState() => const GameUiState(
      roomPhase: RoomPhase.gameOver,
      phase: 'GAME_OVER',
      mySeat: 0,
      playerCount: 2,
      scoreLimit: 24,
      seats: [
        SeatState(seat: 0, nickname: 'Ася', connected: true, handCount: 0, wonCount: 5, score: 3),
        SeatState(seat: 1, nickname: 'Борис', connected: true, handCount: 0, wonCount: 2, score: 13),
      ],
      goats: [1],
      finalScores: [3, 13],
    );

/// Pumps the table inside a two-route GoRouter so _leaveNow's
/// `context.go('/lobby')` has somewhere to land.
Future<(FakeGameController, RecordingAdsService)> pumpTable(
  WidgetTester tester,
  GameUiState initial,
) async {
  SharedPreferences.setMockInitialValues({});
  final fake = FakeGameController(initial);
  final ads = RecordingAdsService();
  final router = GoRouter(
    initialLocation: '/table',
    routes: [
      GoRoute(path: '/table', builder: (_, _) => const TableScreen()),
      GoRoute(
        path: '/lobby',
        builder: (_, _) => const Scaffold(body: Text('LOBBY_STUB')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gameControllerProvider.overrideWith(() => fake),
        adsServiceProvider.overrideWithValue(ads),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  return (fake, ads);
}

/// Bounded pump: overlays animate, so pumpAndSettle would never settle.
Future<void> pumpFrames(WidgetTester tester,
    {int frames = 10,
    Duration step = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  // Both tests start in the room-lobby phase: the connecting phase would arm
  // the startup-reconnect path, which (with no stored token) leaves for the
  // lobby on its own and would mask the behavior under test.
  const waitingState = GameUiState(roomPhase: RoomPhase.lobby);

  testWidgets('game-over exit: counter ticks once, interstitial requested',
      (tester) async {
    final (fake, ads) = await pumpTable(tester, waitingState);
    await pumpFrames(tester, frames: 3);

    fake.setState(gameOverState());
    await pumpFrames(tester);
    expect(ads.gamesFinished, 1, reason: 'one tick per gameOver transition');
    expect(ads.interstitialRequests, isEmpty,
        reason: 'reaching game over must not show an ad by itself');

    await tester.tap(find.text('Выйти'));
    await pumpFrames(tester);

    expect(ads.interstitialRequests, [InterstitialTrigger.leaveToLobby]);
    expect(find.text('LOBBY_STUB'), findsOneWidget,
        reason: 'navigation completes after the (skipped) ad');
  });

  testWidgets('leave outside game over never requests an interstitial',
      (tester) async {
    // The mid-game abandon path: back arrow → _confirmLeave dialog → «Выйти»
    // reaches _leaveNow with a non-gameOver phase.
    final (_, ads) = await pumpTable(tester, waitingState);
    await pumpFrames(tester, frames: 3);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await pumpFrames(tester, frames: 5);
    await tester.tap(find.text('Выйти')); // dialog confirm
    await pumpFrames(tester);

    expect(ads.interstitialRequests, isEmpty);
    expect(ads.gamesFinished, 0);
    expect(find.text('LOBBY_STUB'), findsOneWidget);
  });
}
