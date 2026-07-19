/// Drag-to-play interactions: dragging hand cards onto the table plays them
/// through the same intent paths as the buttons — lead on the center zone,
/// beats on specific table cards (auto-sent on the k-th assignment) — while
/// horizontal swipes keep scrolling the hand and illegal drops bounce. Also
/// covers the reworked leaderDecision action bar (no «Побить самому»).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:goat_app/core/game/game_controller.dart';
import 'package:goat_app/core/game/models.dart';
import 'package:goat_app/features/game/table_screen.dart';
import 'package:goat_app/shared/cards/card_face.dart';

import 'table_stability_test.dart';

/// A [FakeGameController] that records play intents instead of sending them.
class RecordingGameController extends FakeGameController {
  RecordingGameController(super.initial);

  final leads = <List<int>>[];
  final beats = <Map<int, int>>[];
  final discards = <List<int>>[];
  int endTricks = 0;

  @override
  void lead(List<int> cards) => leads.add(cards);

  @override
  void beat(Map<int, int> pairing) => beats.add(pairing);

  @override
  void discard(List<int> cards) => discards.add(cards);

  @override
  void endTrick() => endTricks++;
}

/// My turn with a crafted [legal]; hand is [0, 3, 7, 12, 20, 30].
GameUiState myTurnState({
  LegalActions? legal,
  List<TableSet> sets = const [],
}) =>
    GameUiState(
      roomPhase: RoomPhase.playing,
      phase: 'TRICK_LEAD',
      mySeat: 0,
      dealIndex: 0,
      playerCount: 4,
      scoreLimit: 24,
      multiplier: 1,
      trumpSuit: 3,
      trumpCard: 27, // 6♥
      stockCount: 8,
      seats: [
        for (var s = 0; s < 4; s++)
          SeatState(
            seat: s,
            nickname: 'Игрок ${s + 1}',
            connected: true,
            handCount: 6,
            wonCount: 0,
            score: s,
          ),
      ],
      myHand: const [0, 3, 7, 12, 20, 30],
      trick: TrickState(
        leader: sets.isEmpty ? 0 : 1,
        k: 1,
        turn: 0,
        sets: sets,
        discards: const [],
      ),
      legal: legal,
      deadline: DateTime.now().millisecondsSinceEpoch + 30000,
    );

/// Pumps the table waiting on someone else, then delivers [legal] through a
/// state transition — beat mode primes in the screen's state listener, which
/// only fires on changes (exactly like a real server `legal` event).
Future<RecordingGameController> pumpDragTable(
  WidgetTester tester, {
  required LegalActions legal,
  List<TableSet> sets = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final fake = RecordingGameController(myTurnState(sets: sets));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [gameControllerProvider.overrideWith(() => fake)],
      child: const MaterialApp(home: TableScreen()),
    ),
  );
  await pumpFrames(tester, frames: 2);
  fake.setState(myTurnState(legal: legal, sets: sets));
  await pumpFrames(tester, frames: 2);
  return fake;
}

Finder cardFace(int card) =>
    find.byWidgetPredicate((w) => w is CardFace && w.card == card);

/// Drags [from] to [to]: a clear vertical motion first so the Draggable's
/// vertical-affinity recognizer wins the arena, then steers to the target.
Future<void> dragCardTo(WidgetTester tester, Finder from, Offset to) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveBy(const Offset(0, -60));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveTo(to);
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.up();
  await tester.pump();
}

void main() {
  testWidgets('vertical drag of a hand card onto the center leads it',
      (tester) async {
    final fake = await pumpDragTable(
      tester,
      legal: const LegalActions(kind: 'lead', maxCount: 3),
    );

    final center = tester.getCenter(find.byType(DragTarget<int>).first);
    await dragCardTo(tester, cardFace(30), center);
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(fake.leads, [
      [30],
    ]);
    expect(fake.beats, isEmpty);
    expect(fake.discards, isEmpty);
  });

  testWidgets('drop on a table card with k==1 assigns and auto-sends the beat',
      (tester) async {
    final fake = await pumpDragTable(
      tester,
      legal: const LegalActions(
        kind: 'respond',
        canBeat: true,
        beatMatrix: {
          14: [30],
        },
        discardCount: 1,
      ),
      sets: const [
        TableSet(owner: 1, kind: 'lead', cards: [14]),
      ],
    );

    await dragCardTo(tester, cardFace(30), tester.getCenter(cardFace(14)));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(fake.beats, [
      {14: 30},
    ]);
    // Auto-send: the old confirm button never appears.
    expect(find.textContaining('Побить ('), findsNothing);
  });

  testWidgets(
      'leaderDecision: no «Побить самому», «Закрыть круг» ends the trick',
      (tester) async {
    final fake = await pumpDragTable(
      tester,
      legal: const LegalActions(
        kind: 'leaderDecision',
        canBeat: true,
        beatMatrix: {
          14: [30],
        },
      ),
      sets: const [
        TableSet(owner: 1, kind: 'lead', cards: [14]),
      ],
    );

    expect(find.text('Побить самому'), findsNothing);
    expect(find.text('Побить всё'), findsOneWidget);
    expect(find.text('Закрыть круг'), findsOneWidget);

    await tester.tap(find.text('Закрыть круг'));
    await pumpFrames(tester, frames: 3);

    expect(tester.takeException(), isNull);
    expect(fake.endTricks, 1);
    expect(fake.beats, isEmpty);
  });

  testWidgets('horizontal drag across the hand never plays a card',
      (tester) async {
    final fake = await pumpDragTable(
      tester,
      legal: const LegalActions(kind: 'lead', maxCount: 3),
    );

    // Sideways swipe over a hand card: the scrollable must win the arena
    // (vertical-affinity Draggable stays out), so no intent is recorded.
    final gesture = await tester.startGesture(tester.getCenter(cardFace(30)));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(-80, 0));
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.up();
    await pumpFrames(tester, frames: 3);

    expect(tester.takeException(), isNull);
    expect(fake.leads, isEmpty);
    expect(fake.beats, isEmpty);
    expect(fake.discards, isEmpty);
  });

  testWidgets('invalid lead union bounces without recording an intent',
      (tester) async {
    final fake = await pumpDragTable(
      tester,
      legal: const LegalActions(kind: 'lead', maxCount: 3),
    );

    // Select 6♠ (0), then drag 8♦ (20): the union shares neither rank nor
    // suit, so the center zone must reject the drop.
    await tester.tap(cardFace(0));
    await pumpFrames(tester, frames: 2);

    final center = tester.getCenter(find.byType(DragTarget<int>).first);
    await dragCardTo(tester, cardFace(20), center);
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);
    expect(fake.leads, isEmpty);
    expect(fake.beats, isEmpty);
    expect(fake.discards, isEmpty);
  });
}
