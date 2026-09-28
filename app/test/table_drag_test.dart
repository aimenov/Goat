/// Drag-to-play interactions: dragging hand cards onto the table plays them
/// through the same intent paths as the buttons — lead on the center zone,
/// beats on specific table cards (auto-sent on the k-th assignment),
/// face-down discards thrown on the center — while horizontal swipes keep
/// scrolling the hand and illegal drops bounce. Also covers the reworked
/// leaderDecision action bar (no «Побить самому»).
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
/// [beforeDrop] runs while the card still hovers over [to].
Future<void> dragCardTo(
  WidgetTester tester,
  Finder from,
  Offset to, {
  void Function()? beforeDrop,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveBy(const Offset(0, -60));
  await tester.pump(const Duration(milliseconds: 20));
  await gesture.moveTo(to);
  await tester.pump(const Duration(milliseconds: 20));
  beforeDrop?.call();
  await gesture.up();
  await tester.pump();
}

/// The table's center drop zone (the outermost `DragTarget<int>`). Its
/// middle sits on the first chain, so in beat mode a drop there can land on
/// that card's own per-target zone — use [openFelt] to hit the center one.
Offset centerZone(WidgetTester tester) =>
    tester.getCenter(find.byType(DragTarget<int>).first);

/// A point inside the center drop zone that is off every table card.
Offset openFelt(WidgetTester tester) {
  final zone = tester.getRect(find.byType(DragTarget<int>).first);
  final point = zone.topLeft + const Offset(40, 30);
  for (final element in find.byType(CardFace).evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    expect(rect.contains(point), isFalse, reason: 'openFelt hit a card');
  }
  return point;
}

/// Face-down hand-size cards: only a discard's drag feedback renders a
/// [CardBack] at the hand's 92 px height.
final Finder dragBacks =
    find.byWidgetPredicate((w) => w is CardBack && w.height == 92);

/// Responding with nothing to beat with: [k] cards must go face-down.
LegalActions forcedDiscard(int k) =>
    LegalActions(kind: 'respond', discardCount: k);

List<TableSet> leadSet(List<int> cards) => [
      TableSet(owner: 1, kind: 'lead', cards: cards),
    ];

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

  group('discard drags', () {
    testWidgets('k == 1: a card thrown on the table goes face-down',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(1),
        sets: leadSet(const [14]),
      );

      var backsWhileHovering = 0;
      var veilShown = false;
      await dragCardTo(
        tester,
        cardFace(30),
        centerZone(tester),
        beforeDrop: () {
          backsWhileHovering = dragBacks.evaluate().length;
          veilShown = find.text('Втёмную').evaluate().isNotEmpty;
        },
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(backsWhileHovering, 1, reason: 'the feedback rides face-down');
      expect(veilShown, isTrue);
      expect(fake.discards, [
        [30],
      ]);
      expect(fake.beats, isEmpty);
      expect(fake.leads, isEmpty);
    });

    testWidgets('k == 1: dragging a card other than the tapped one throws it',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(1),
        sets: leadSet(const [14]),
      );

      await tester.tap(cardFace(0));
      await pumpFrames(tester, frames: 2);
      await dragCardTo(tester, cardFace(20), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, [
        [20],
      ]);
    });

    testWidgets('dragging one of a complete tap selection throws them all',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(2),
        sets: leadSet(const [14, 15]),
      );

      await tester.tap(cardFace(0));
      await pumpFrames(tester, frames: 2);
      await tester.tap(cardFace(3));
      await pumpFrames(tester, frames: 2);
      expect(find.text('Скинуть (2/2)'), findsOneWidget);

      var backsWhileHovering = 0;
      await dragCardTo(
        tester,
        cardFace(3),
        centerZone(tester),
        beforeDrop: () => backsWhileHovering = dragBacks.evaluate().length,
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(backsWhileHovering, 2, reason: 'the whole throw is shown');
      expect(fake.discards, hasLength(1));
      expect(fake.discards.single.toSet(), {0, 3});
    });

    testWidgets('a free card completing the selection throws the union',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(2),
        sets: leadSet(const [14, 15]),
      );

      await tester.tap(cardFace(0));
      await pumpFrames(tester, frames: 2);
      await dragCardTo(tester, cardFace(20), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, hasLength(1));
      expect(fake.discards.single.toSet(), {0, 20});
    });

    testWidgets('short of k a drop collects, the next drop throws both',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(2),
        sets: leadSet(const [14, 15]),
      );

      var veilShown = false;
      await dragCardTo(
        tester,
        cardFace(20),
        centerZone(tester),
        beforeDrop: () =>
            veilShown = find.text('Втёмную 1/2').evaluate().isNotEmpty,
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(veilShown, isTrue);
      expect(fake.discards, isEmpty);
      expect(find.text('Скинуть (1/2)'), findsOneWidget);

      await dragCardTo(tester, cardFace(30), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, hasLength(1));
      expect(fake.discards.single.toSet(), {20, 30});
    });

    testWidgets('an incomplete selection dragged by a selected card bounces',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(3),
        sets: leadSet(const [14, 15, 16]),
      );

      await tester.tap(cardFace(0));
      await pumpFrames(tester, frames: 2);
      await dragCardTo(tester, cardFace(0), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, isEmpty);
      expect(find.text('Скинуть (1/3)'), findsOneWidget);
    });

    testWidgets('an over-full tap selection never throws more than k',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(2),
        sets: leadSet(const [14, 15]),
      );

      for (final c in const [0, 3, 7]) {
        await tester.tap(cardFace(c));
        await pumpFrames(tester, frames: 2);
      }
      expect(find.text('Скинуть (3/2)'), findsOneWidget);

      // A selected card (3 ≠ k) and a free card (union 4 > k) both bounce.
      await dragCardTo(tester, cardFace(3), centerZone(tester));
      await pumpFrames(tester);
      await dragCardTo(tester, cardFace(20), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, isEmpty);
      expect(find.text('Скинуть (3/2)'), findsOneWidget);
    });

    testWidgets('a free card on a complete selection bounces', (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: forcedDiscard(2),
        sets: leadSet(const [14, 15]),
      );

      await tester.tap(cardFace(0));
      await pumpFrames(tester, frames: 2);
      await tester.tap(cardFace(3));
      await pumpFrames(tester, frames: 2);
      await dragCardTo(tester, cardFace(20), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, isEmpty);
      expect(find.text('Скинуть (2/2)'), findsOneWidget);
    });

    testWidgets('«Скинуть» segment: drags throw instead of beating',
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
        sets: leadSet(const [14]),
      );

      await tester.tap(find.text('Скинуть'));
      await pumpFrames(tester, frames: 2);
      // 30 could beat 14, but the segment says discard.
      await dragCardTo(tester, cardFace(30), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, [
        [30],
      ]);
      expect(fake.beats, isEmpty);
    });

    testWidgets('beat mode: a card that beats nothing is thrown face-down',
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
        sets: leadSet(const [14]),
      );

      // Dropped right onto the table card: its per-target zone rejects 7,
      // the center zone underneath takes it as the discard.
      var backsWhileHovering = 0;
      await dragCardTo(
        tester,
        cardFace(7),
        tester.getCenter(cardFace(14)),
        beforeDrop: () => backsWhileHovering = dragBacks.evaluate().length,
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(backsWhileHovering, 1);
      expect(fake.discards, [
        [7],
      ]);
      expect(fake.beats, isEmpty);
    });

    testWidgets('beat mode: a beating card dropped on the center still beats',
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
        sets: leadSet(const [14]),
      );

      // Open felt, not card 14: the center zone itself must resolve the
      // beat (the discard branch now runs ahead of it).
      var backsWhileHovering = 0;
      await dragCardTo(
        tester,
        cardFace(30),
        openFelt(tester),
        beforeDrop: () => backsWhileHovering = dragBacks.evaluate().length,
      );
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(backsWhileHovering, 0, reason: 'beats ride face-up');
      expect(fake.beats, [
        {14: 30},
      ]);
      expect(fake.discards, isEmpty);
    });

    testWidgets('beat mode, k > 1: a non-beating drop flips to «Скинуть»',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: const LegalActions(
          kind: 'respond',
          canBeat: true,
          beatMatrix: {
            14: [30],
            15: [20],
          },
          discardCount: 2,
        ),
        sets: leadSet(const [14, 15]),
      );

      await dragCardTo(tester, cardFace(0), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, isEmpty);
      expect(fake.beats, isEmpty);
      expect(find.text('Скинуть (1/2)'), findsOneWidget);

      // Discard mode now: even a card that could beat joins the throw.
      await dragCardTo(tester, cardFace(30), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, hasLength(1));
      expect(fake.discards.single.toSet(), {0, 30});
      expect(fake.beats, isEmpty);
    });

    testWidgets('beat mode: a half-assigned beat never turns into a discard',
        (tester) async {
      final fake = await pumpDragTable(
        tester,
        legal: const LegalActions(
          kind: 'respond',
          canBeat: true,
          beatMatrix: {
            14: [30],
            15: [20],
          },
          discardCount: 2,
        ),
        sets: leadSet(const [14, 15]),
      );

      await dragCardTo(tester, cardFace(30), tester.getCenter(cardFace(14)));
      await pumpFrames(tester);
      expect(fake.beats, isEmpty, reason: '1/2 assigned, nothing sent yet');

      await dragCardTo(tester, cardFace(0), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, isEmpty);
      expect(fake.beats, isEmpty);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('leaderDecision: a non-beating card cannot be discarded',
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
        sets: leadSet(const [14]),
      );

      await dragCardTo(tester, cardFace(0), centerZone(tester));
      await pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(fake.discards, isEmpty);
      expect(fake.beats, isEmpty);
      expect(fake.endTricks, 0);
    });
  });
}
