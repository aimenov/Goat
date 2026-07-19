/// Presentation-queue pacing tests for [GameController]: server batches land
/// in one frame, but tricks / deal summaries / game over must each hold on
/// screen (see `pacing.dart`), while requested resyncs and socket closes
/// flush instantly. Driven with fakeAsync — no network, no widgets.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:goat_app/core/game/game_controller.dart';
import 'package:goat_app/core/game/models.dart';
import 'package:goat_app/core/game/pacing.dart';
import 'package:goat_app/core/net/transport.dart';

/// A [GameRoom] that never touches the network: outbound intents are
/// captured in [sent]; tests inject inbound messages and the close.
class FakeRoom implements GameRoom {
  final _messages = StreamController<(String, Object?)>.broadcast(sync: true);
  final _closed = Completer<int>();
  final sent = <(String, Object?)>[];

  @override
  Stream<(String, Object?)> get messages => _messages.stream;

  @override
  Future<int> get onClose => _closed.future;

  @override
  void send(String type, Object? payload) => sent.add((type, payload));

  void inject(String type, Object? payload) => _messages.add((type, payload));

  void close(int code) => _closed.complete(code);

  int get resyncCount =>
      sent.where((m) => m.$1 == 'intent' && asMap(m.$2)['type'] == 'resync').length;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeRoom does not implement $invocation');
}

Map<String, Object?> snapshotMsg({
  int seq = 0,
  String phase = 'TRICK_LEAD',
  int stockCount = 8,
  Map<String, Object?>? legal,
  Map<String, Object?>? trick,
}) =>
    {
      'seq': seq,
      'deadline': 0,
      'nicknames': ['Ася', 'Борис', 'Вера', 'Глеб'],
      'connected': [true, true, true, true],
      'view': {
        'phase': phase,
        'seat': 0,
        'dealIndex': 0,
        'playerCount': 4,
        'scoreLimit': 24,
        'multiplier': 1,
        'trumpSuit': 3,
        'trumpCard': 27,
        'stockCount': stockCount,
        'seats': [
          for (var s = 0; s < 4; s++) {'seat': s, 'handCount': 6, 'wonCount': 0, 'score': 0},
        ],
        'myHand': [0, 3, 7],
        'myWonPile': <int>[],
        'trick': trick,
        'legal': legal,
      },
    };

Map<String, Object?> trickEnded(int seq, {int winner = 1, int cardCount = 4}) =>
    {'type': 'trickEnded', 'seq': seq, 'winner': winner, 'cardCount': cardCount};

Map<String, Object?> turn(int seq, {int seat = 2, String phase = 'TRICK_LEAD'}) =>
    {'type': 'turn', 'seq': seq, 'seat': seat, 'phase': phase, 'deadline': 0};

Map<String, Object?> dealEnded(int seq) => {
      'type': 'dealEnded',
      'seq': seq,
      'results': [
        for (var s = 0; s < 4; s++) {'seat': s, 'cardPoints': 30, 'penalty': 0, 'score': s},
      ],
    };

Map<String, Object?> dealStarted(int seq, {int dealIndex = 1}) =>
    {'type': 'dealStarted', 'seq': seq, 'dealIndex': dealIndex, 'multiplier': 1};

Map<String, Object?> gameEnded(int seq) =>
    {'type': 'gameEnded', 'seq': seq, 'goats': [2], 'scores': [0, 3, 12, 5]};

/// Attaches a controller to a [FakeRoom] and applies the initial snapshot
/// (which the attach-time resync makes instant). Returns the wired trio plus
/// a live log of applied table-event types.
({ProviderContainer container, GameController controller, FakeRoom room, List<String> applied})
    setup(FakeAsync async, {Map<String, Object?>? snapshot}) {
  final container = ProviderContainer();
  final controller = container.read(gameControllerProvider.notifier);
  final room = FakeRoom();
  final applied = <String>[];
  controller.attach(room);
  controller.tableEvents.listen((e) => applied.add(e.type));
  room.inject('snapshot', snapshot ?? snapshotMsg());
  async.flushMicrotasks();
  return (container: container, controller: controller, room: room, applied: applied);
}

void main() {
  test('trickEnded holds beatHoldMs; the next event waits postTrickMs more', () {
    fakeAsync((async) {
      final s = setup(async);
      GameUiState read() => s.container.read(gameControllerProvider);

      s.room.inject('event', trickEnded(1));
      s.room.inject('event', turn(2, phase: 'TRICK_RESPOND'));
      async.flushMicrotasks();
      expect(s.applied, isEmpty);
      expect(read().seats[1].wonCount, 0);

      async.elapse(const Duration(milliseconds: beatHoldMs - 1));
      expect(s.applied, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(s.applied, ['trickEnded']);
      expect(read().seats[1].wonCount, 4);

      async.elapse(const Duration(milliseconds: postTrickMs - 1));
      expect(s.applied, ['trickEnded']);
      async.elapse(const Duration(milliseconds: 1));
      expect(s.applied, ['trickEnded', 'turn']);
      expect(read().phase, 'TRICK_RESPOND');
      s.container.dispose();
    });
  });

  test('dealStarted waits dealTransitionMs only right after dealEnded', () {
    fakeAsync((async) {
      final s = setup(async);
      GameUiState read() => s.container.read(gameControllerProvider);

      s.room.inject('event', dealEnded(1));
      async.flushMicrotasks();
      expect(read().lastDealResults, isNotNull, reason: 'dealEnded itself is not delayed');

      s.room.inject('event', dealStarted(2));
      async.flushMicrotasks();
      expect(read().dealIndex, 0);
      async.elapse(const Duration(milliseconds: dealTransitionMs - 1));
      expect(read().dealIndex, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(read().dealIndex, 1);
      expect(read().lastDealResults, isNull);
      s.container.dispose();
    });

    // Without a preceding dealEnded (e.g. the very first deal) there is no gap.
    fakeAsync((async) {
      final s = setup(async);
      s.room.inject('event', dealStarted(1));
      async.flushMicrotasks();
      expect(s.container.read(gameControllerProvider).dealIndex, 1);
      s.container.dispose();
    });
  });

  test('requested resync: next snapshot applies instantly and drops the queue', () {
    fakeAsync((async) {
      final s = setup(async);
      GameUiState read() => s.container.read(gameControllerProvider);
      expect(s.room.resyncCount, 1); // from attach()

      s.room.inject('event', trickEnded(1));
      // seq gap (2..4 missing) → the controller requests a resync at receipt.
      s.room.inject('event', {'type': 'led', 'seq': 5, 'seat': 1, 'cards': [14]});
      async.flushMicrotasks();
      expect(s.room.resyncCount, 2);

      s.room.inject('snapshot', snapshotMsg(seq: 5, stockCount: 3));
      async.flushMicrotasks();
      expect(read().stockCount, 3, reason: 'requested snapshot applies with no hold');

      async.elapse(const Duration(seconds: 10));
      expect(s.applied, isEmpty, reason: 'stale queued events were dropped');
      expect(read().seats[1].wonCount, 0);
      s.container.dispose();
    });
  });

  test('unrequested snapshot trails its batch: legal never precedes the turn', () {
    fakeAsync((async) {
      final s = setup(async);
      GameUiState read() => s.container.read(gameControllerProvider);

      // Trick ends, it becomes my turn; the mover snapshot carries my legal.
      s.room.inject('event', trickEnded(1));
      s.room.inject('event', turn(2, seat: 0));
      s.room.inject('snapshot', snapshotMsg(seq: 2, phase: 'TRICK_LEAD', legal: {'kind': 'lead', 'maxCount': 1}));
      async.flushMicrotasks();
      expect(read().legal, isNull);

      async.elapse(const Duration(milliseconds: beatHoldMs));
      expect(s.applied, ['trickEnded']);
      expect(read().legal, isNull, reason: 'snapshot must not overtake the paused turn');

      async.elapse(const Duration(milliseconds: postTrickMs - 1));
      expect(read().legal, isNull);
      async.elapse(const Duration(milliseconds: 1));
      expect(s.applied, ['trickEnded', 'turn']);
      expect(read().legal, isNotNull);
      expect(read().legal!.kind, 'lead');
      s.container.dispose();
    });
  });

  test('a rapid event chain never lags more than maxQueueLagMs', () {
    fakeAsync((async) {
      final s = setup(async);
      // Uncapped, this chain would stretch to 700+900+3000+700+900 = 6200 ms.
      s.room.inject('event', trickEnded(1));
      s.room.inject('event', turn(2));
      s.room.inject('event', dealEnded(3));
      s.room.inject('event', dealStarted(4));
      s.room.inject('event', trickEnded(5, winner: 2));
      s.room.inject('event', turn(6, seat: 3, phase: 'TRICK_RESPOND'));
      async.flushMicrotasks();

      async.elapse(const Duration(milliseconds: maxQueueLagMs - 1));
      expect(s.applied, hasLength(lessThan(6)));
      async.elapse(const Duration(milliseconds: 1));
      expect(s.applied, ['trickEnded', 'turn', 'dealEnded', 'dealStarted', 'trickEnded', 'turn']);
      expect(s.container.read(gameControllerProvider).phase, 'TRICK_RESPOND');
      s.container.dispose();
    });
  });

  test('gameEnded is held gameOverMs so the final summary stays visible', () {
    fakeAsync((async) {
      final s = setup(async);
      GameUiState read() => s.container.read(gameControllerProvider);

      s.room.inject('event', dealEnded(1));
      s.room.inject('event', gameEnded(2));
      async.flushMicrotasks();
      expect(read().lastDealResults, isNotNull);
      expect(read().roomPhase, RoomPhase.playing);

      async.elapse(const Duration(milliseconds: gameOverMs - 1));
      expect(read().roomPhase, RoomPhase.playing);
      async.elapse(const Duration(milliseconds: 1));
      expect(read().roomPhase, RoomPhase.gameOver);
      expect(read().goats, [2]);
      s.container.dispose();
    });
  });

  test('socket close mid-hold flush-applies the queue: no reconnecting after gameEnded', () {
    fakeAsync((async) {
      final s = setup(async);
      GameUiState read() => s.container.read(gameControllerProvider);

      s.room.inject('event', dealEnded(1));
      s.room.inject('event', gameEnded(2));
      async.flushMicrotasks();
      expect(read().roomPhase, RoomPhase.playing);

      s.room.close(1006); // unclean close during the gameEnded hold
      async.flushMicrotasks();
      expect(read().roomPhase, RoomPhase.gameOver,
          reason: 'the held gameEnded must apply before the reconnecting check');
      s.container.dispose();
    });
  });

  test('detach cancels the drain timer and clears the queue', () {
    fakeAsync((async) {
      final s = setup(async);
      s.room.inject('event', trickEnded(1));
      async.flushMicrotasks();
      expect(async.pendingTimers, isNotEmpty);

      s.controller.detach();
      expect(async.pendingTimers, isEmpty);
      async.elapse(const Duration(seconds: 10));
      expect(s.applied, isEmpty);
      s.container.dispose();
    });
  });
}
