/// Regression tests for the Chrome white-screen bug: the table must survive
/// the lobby→playing transition (no duplicate GlobalKeys from positional
/// reconciliation of the anchored Column) and must lay out on short/narrow
/// viewports without RenderFlex overflows.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:goat_app/core/game/game_controller.dart';
import 'package:goat_app/core/game/models.dart';
import 'package:goat_app/features/game/table_screen.dart';

/// A [GameController] that never touches the network: it starts from a
/// crafted state and lets the test assign new states directly.
class FakeGameController extends GameController {
  FakeGameController(this._initial);

  final GameUiState _initial;
  final _fakeEvents = StreamController<TableEvent>.broadcast();

  @override
  GameUiState build() => _initial;

  @override
  Stream<TableEvent> get tableEvents => _fakeEvents.stream;

  void setState(GameUiState next) => state = next;

  /// Injects a one-shot table event (e.g. a reaction) as the server would.
  void emitEvent(TableEvent event) => _fakeEvents.add(event);
}

GameUiState lobbyState() => const GameUiState(
      roomPhase: RoomPhase.lobby,
      mySeat: 0,
      lobbySeats: [
        LobbySeat(seat: 0, nickname: 'Ася', ready: true, connected: true, isHost: true),
        LobbySeat(seat: 1, nickname: 'Борис', ready: true, connected: true, isHost: false),
        LobbySeat(seat: 2, nickname: 'Вера', ready: false, connected: true, isHost: false),
      ],
    );

GameUiState playingState({
  int playerCount = 4,
  List<DealResult>? lastDealResults,
  int myScore = 0,
  List<int> myWonPile = const [],
  LegalActions? legal,
  int turn = 2,
}) =>
    GameUiState(
      roomPhase: RoomPhase.playing,
      phase: 'TRICK_LEAD',
      mySeat: 0,
      dealIndex: 0,
      playerCount: playerCount,
      scoreLimit: 24,
      multiplier: 1,
      trumpSuit: 3,
      trumpCard: 27, // 6♥
      stockCount: 8,
      seats: [
        for (var s = 0; s < playerCount; s++)
          SeatState(
            seat: s,
            nickname: 'Игрок ${s + 1}',
            connected: true,
            handCount: 6,
            wonCount: s.isEven ? 2 : 0,
            score: s == 0 ? myScore : s,
          ),
      ],
      myHand: const [0, 3, 7, 12, 20, 30], // 6 cards
      myWonPile: myWonPile,
      trick: TrickState(
        leader: 1,
        k: 1,
        turn: turn,
        sets: const [
          TableSet(owner: 1, kind: 'lead', cards: [14]),
        ],
        discards: const [],
      ),
      legal: legal, // null: waiting on someone else's move
      deadline: DateTime.now().millisecondsSinceEpoch + 30000,
      lastDealResults: lastDealResults,
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

/// Pumps a bounded series of frames: the table hosts perpetual animations
/// (PulseGlow on the active seat, the turn countdown), so pumpAndSettle would
/// never settle in the playing phase.
Future<void> pumpFrames(WidgetTester tester,
    {int frames = 10,
    Duration step = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

void main() {
  testWidgets('lobby→playing transition never duplicates GlobalKeys or overflows',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldOnError);

    final fake = await pumpTable(tester, lobbyState());
    await tester.pumpAndSettle();
    expect(find.text('Ждём игроков'), findsOneWidget);

    // The exact transition that used to white-screen Chrome: the lobby
    // overlay drops and the keyed anchor Column gains its playing children.
    fake.setState(playingState());
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(
      errors.map((e) => e.exceptionAsString()),
      isEmpty,
      reason: 'no Duplicate GlobalKeys / RenderFlex overflow during the '
          'lobby→playing transition',
    );
    expect(find.text('Раздача 1'), findsOneWidget);

    // Full circle back to the leader: the leaderDecision action bar
    // (caption + «Побить всё» + «Закрыть круг») must mount without
    // disturbing the keyed Column either.
    fake.setState(playingState(
      turn: 0,
      legal: const LegalActions(
        kind: 'leaderDecision',
        canBeat: true,
        beatMatrix: {
          14: [30],
        },
      ),
    ));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(
      errors.map((e) => e.exceptionAsString()),
      isEmpty,
      reason: 'the playing→leaderDecision transition must not disturb the '
          'anchored Column',
    );
    expect(find.text('Побить самому'), findsNothing);
    expect(find.text('Закрыть круг'), findsOneWidget);
  });

  testWidgets('table lays out on a short viewport without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(800, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldOnError);

    await pumpTable(tester, playingState());
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(errors.map((e) => e.exceptionAsString()), isEmpty,
        reason: 'a 500px-tall viewport must scroll, not overflow');
    expect(find.text('Раздача 1'), findsOneWidget);
  });

  testWidgets('deal-results overlay with many rows scrolls instead of overflowing',
      (tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldOnError);

    // The overlay shows when lastDealResults arrives on a state change, so
    // start without results and then deliver them (as dealEnded would).
    final fake = await pumpTable(tester, playingState(playerCount: 6));
    await pumpFrames(tester, frames: 3);

    fake.setState(playingState(
      playerCount: 6,
      lastDealResults: [
        for (var s = 0; s < 6; s++)
          DealResult(seat: s, cardPoints: 20 + s, penalty: s.isOdd ? 2 : 0, score: 4 + s),
      ],
    ));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(errors.map((e) => e.exceptionAsString()), isEmpty,
        reason: 'six result rows on a 400x500 viewport must scroll, '
            'not overflow');
    expect(find.text('Итоги раздачи'), findsOneWidget);
  });

  testWidgets(
      'my area with two-digit score/взятки and a reaction bubble fits a '
      '212px-wide viewport', (tester) async {
    tester.view.physicalSize = const Size(212, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldOnError);

    // Two-digit score and взятки — the widest the chips get in a real game.
    final fake = await pumpTable(
      tester,
      playingState(
        myScore: 24,
        myWonPile: [for (var i = 0; i < 12; i++) i],
      ),
    );
    await pumpFrames(tester, frames: 3);

    // A reaction bubble on my own seat adds the transient emoji to the row.
    fake.emitEvent(const TableEvent('reaction', {'seat': 0, 'emoji': 'goat'}));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(
      errors.map((e) => e.exceptionAsString()),
      isEmpty,
      reason: 'score 24 + 12 взяток + reaction bubble must shrink, '
          'not overflow, at 212px',
    );
    expect(find.text('Взятки: 12'), findsOneWidget);
    expect(find.text('🐐'), findsWidgets);
  });
}
