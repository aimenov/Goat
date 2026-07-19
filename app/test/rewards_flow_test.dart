/// Game-over rewards flow on the table screen, driven through a
/// [FakeGameController] (no network): no rewards → no 🥬 anywhere; rewards →
/// капуста count-up + breakdown + rating delta; a rating-band crossing shows
/// the «Новое звание» chip.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:goat_app/core/game/game_controller.dart';
import 'package:goat_app/core/game/models.dart';
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

GameUiState gameOverState({GameRewards? rewards}) => GameUiState(
      roomPhase: RoomPhase.gameOver,
      phase: 'GAME_OVER',
      mySeat: 0,
      playerCount: 2,
      scoreLimit: 24,
      seats: const [
        SeatState(seat: 0, nickname: 'Ася', connected: true, handCount: 0, wonCount: 5, score: 3),
        SeatState(seat: 1, nickname: 'Борис', connected: true, handCount: 0, wonCount: 2, score: 13),
      ],
      goats: const [1],
      finalScores: const [3, 13],
      rewards: rewards,
    );

Future<FakeGameController> pumpTable(
  WidgetTester tester,
  GameUiState initial,
) async {
  SharedPreferences.setMockInitialValues({});
  final fake = FakeGameController(initial);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gameControllerProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: TableScreen()),
    ),
  );
  return fake;
}

/// Bounded pump: the game-over overlay animates (confetti, count-ups), so
/// pumpAndSettle would never settle.
Future<void> pumpFrames(WidgetTester tester,
    {int frames = 14,
    Duration step = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('game over without rewards shows no капуста', (tester) async {
    await pumpTable(tester, gameOverState());
    await pumpFrames(tester);

    expect(find.text('Игра окончена'), findsOneWidget);
    expect(find.textContaining('🥬'), findsNothing);
    expect(find.textContaining('Рейтинг'), findsNothing);
  });

  testWidgets('rewards render count-up, verbatim breakdown and rating delta',
      (tester) async {
    final fake = await pumpTable(tester, gameOverState());
    await pumpFrames(tester, frames: 3);

    fake.setState(gameOverState(
      rewards: const GameRewards(
        coins: 45,
        breakdown: [
          RewardLine(ru: 'Победа', amount: 20),
          RewardLine(ru: 'Задание дня', amount: 15),
        ],
        ratingDelta: 18,
        rating: 1068,
        questProgress: [
          QuestTick(id: 'win_1', ru: 'Выиграйте партию', progress: 1, target: 1, completed: true),
        ],
      ),
    ));
    await pumpFrames(tester);

    expect(find.text('+45 🥬'), findsOneWidget, reason: 'count-up lands on the total');
    expect(find.text('Победа'), findsOneWidget);
    expect(find.text('Задание дня'), findsOneWidget);
    expect(find.text('Рейтинг: 1068'), findsOneWidget);
    expect(find.text('+18'), findsOneWidget);
    // 1050 → 1068 stays inside the «Козёл обыкновенный» band: no rank-up.
    expect(find.textContaining('Новое звание'), findsNothing);
    // No rewarded-ad hook installed → no double button.
    expect(find.textContaining('Удвоить'), findsNothing);
  });

  testWidgets('a rating-band crossing shows the «Новое звание» chip',
      (tester) async {
    final fake = await pumpTable(tester, gameOverState());
    await pumpFrames(tester, frames: 3);

    // 1085 → 1105 crosses the 1100 «Козёл отпущения» threshold.
    fake.setState(gameOverState(
      rewards: const GameRewards(
        coins: 30,
        breakdown: [RewardLine(ru: 'Победа', amount: 20)],
        ratingDelta: 20,
        rating: 1105,
      ),
    ));
    await pumpFrames(tester);

    expect(
      find.text('Новое звание: 🙃 Козёл отпущения!'),
      findsOneWidget,
    );
  });

  testWidgets('anonymous rewards show only the login hint', (tester) async {
    final fake = await pumpTable(tester, gameOverState());
    await pumpFrames(tester, frames: 3);

    fake.setState(gameOverState(rewards: const GameRewards(anonymous: true)));
    await pumpFrames(tester);

    expect(find.text('Войдите, чтобы копить капусту'), findsOneWidget);
    expect(find.textContaining('🥬'), findsNothing);
  });
}
