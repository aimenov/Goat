/// Wires a [GameRoom] message stream into [GameUiState] and exposes intents.
/// Events drive incremental updates (and animations); snapshots are
/// authoritative full replacements (join, reconnect, own turn, seq gap).
///
/// A FIFO presentation queue paces how server batches (which land in one
/// frame) become visible: seq bookkeeping happens at receipt, but most
/// messages apply after a scheduled hold (see `pacing.dart`) so tricks, deal
/// summaries and game over each get a moment on screen.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/transport.dart';
import 'models.dart';
import 'pacing.dart';

/// Transient one-shot events the UI reacts to (animations, toasts, reactions).
class TableEvent {
  final String type;
  final Map<String, Object?> data;
  const TableEvent(this.type, this.data);
}

/// One deferred message in the presentation queue.
class _PendingEntry {
  final bool isSnapshot;
  final Map<String, Object?> payload;
  final DateTime dueAt;
  const _PendingEntry(this.isSnapshot, this.payload, this.dueAt);
}

class GameController extends Notifier<GameUiState> {
  GameRoom? _room;
  StreamSubscription<(String, Object?)>? _sub;
  int _lastSeq = -1;
  int _actionCounter = 0;
  final _tableEvents = StreamController<TableEvent>.broadcast();
  final _rejections = StreamController<String>.broadcast();

  // Presentation queue: entries apply in FIFO order at their dueAt.
  final _queue = Queue<_PendingEntry>();
  Timer? _drainTimer;
  DateTime? _queueReadyAt; // dueAt of the last enqueued entry
  String? _lastQueuedType; // event type of the last enqueued (non-bypass) event
  bool _flushOnSnapshot = false; // a resync was requested; next snapshot flushes

  /// These reflect out-of-band reality (chat-like or connection-state), not
  /// game progression — they must never wait behind a paced trick.
  static const _bypassTypes = {'lobby', 'reaction', 'playerConnection', 'rematch'};

  Stream<TableEvent> get tableEvents => _tableEvents.stream;
  Stream<String> get rejections => _rejections.stream;

  @override
  GameUiState build() => const GameUiState();

  void attach(GameRoom room) {
    _sub?.cancel();
    _resetQueue();
    _room = room;
    _lastSeq = -1;
    state = const GameUiState(roomPhase: RoomPhase.lobby);
    _sub = room.messages.listen(_onMessage);
    room.onClose.then((code) {
      // A stale room's close (after a re-attach) must not flip the healthy
      // session that replaced it into "reconnecting".
      if (!identical(_room, room)) return;
      // Apply anything still held for pacing before deciding the phase: a
      // close during the gameEnded hold must not flip a finished game into
      // "reconnecting".
      _flushQueue();
      if (code == 4000 || state.roomPhase == RoomPhase.gameOver) return;
      state = state.copyWith(roomPhase: RoomPhase.reconnecting);
    });
    send('resync', {});
  }

  void detach() {
    _sub?.cancel();
    _resetQueue();
    _room = null;
    state = const GameUiState();
  }

  // ------------------------------------------------------------- intents

  void send(String type, Map<String, Object?> payload) {
    // Every resync request (attach, seq gap, rejected ack) makes the next
    // snapshot authoritative: it must flush the queue and apply instantly.
    if (type == 'resync') _flushOnSnapshot = true;
    _room?.send('intent', {'type': type, ...payload});
  }

  String _nextActionId() => 'a${_actionCounter++}';

  void setReady(bool ready) => send('ready', {'ready': ready});

  void react(String emoji) => send('react', {'emoji': emoji});

  void voteRematch(bool accept) => send('rematchVote', {'accept': accept});

  /// Optimistic: cards leave the hand immediately; a rejection resyncs.
  void lead(List<int> cards) {
    send('lead', {'actionId': _nextActionId(), 'cards': cards});
    _removeFromHand(cards);
  }

  void beat(Map<int, int> pairing) {
    final pairs = pairing.entries.map((e) => {'target': e.key, 'card': e.value}).toList();
    send('beat', {'actionId': _nextActionId(), 'pairs': pairs});
    _removeFromHand(pairing.values.toList());
  }

  void discard(List<int> cards) {
    send('discard', {'actionId': _nextActionId(), 'cards': cards});
    _removeFromHand(cards);
  }

  void endTrick() => send('endTrick', {'actionId': _nextActionId()});

  void _removeFromHand(List<int> cards) {
    final hand = [...state.myHand]..removeWhere(cards.contains);
    state = state.copyWith(myHand: hand, legal: null);
  }

  // ------------------------------------------------------------- messages

  void _onMessage((String, Object?) message) {
    final (type, payload) = message;
    switch (type) {
      case 'snapshot':
        _receiveSnapshot(asMap(payload));
      case 'event':
        _receiveEvent(asMap(payload));
      case 'ack':
        final m = asMap(payload);
        if (m['ok'] != true) {
          _rejections.add('${m['error'] ?? 'rejected'}');
          send('resync', {});
        }
      case 'pong':
        break;
    }
  }

  // -------------------------------------------------- presentation queue

  /// Seq bookkeeping happens here, at receipt; presentation may lag behind.
  void _receiveEvent(Map<String, Object?> m) {
    final type = '${m['type']}';
    final seq = (m['seq'] as num?)?.toInt() ?? _lastSeq;
    if (seq > _lastSeq + 1 && type != 'lobby' && type != 'reaction') {
      send('resync', {});
    }
    _lastSeq = max(_lastSeq, seq);
    if (_bypassTypes.contains(type)) {
      _applyEventBody(m);
    } else {
      _enqueue(isSnapshot: false, type: type, payload: m);
    }
  }

  void _receiveSnapshot(Map<String, Object?> m) {
    _lastSeq = max(_lastSeq, (m['seq'] as num).toInt());
    if (_flushOnSnapshot) {
      // Requested resync: the snapshot supersedes anything still queued.
      _resetQueue();
      _applySnapshotBody(m);
    } else {
      // Unrequested (own-turn) snapshot: trail the batch it arrived with so
      // `legal` never appears before the paused turn event.
      _enqueue(isSnapshot: true, type: null, payload: m);
    }
  }

  void _enqueue({required bool isSnapshot, required String? type, required Map<String, Object?> payload}) {
    final now = clock.now();
    var base = _queueReadyAt ?? now;
    if (base.isBefore(now)) base = now;
    final gap = isSnapshot ? 0 : _gapMs(type!, _lastQueuedType);
    var dueAt = base.add(Duration(milliseconds: gap));
    // Cap total presentation lag so the client never trails the server by
    // more than maxQueueLagMs under a rapid event chain.
    final cap = now.add(const Duration(milliseconds: maxQueueLagMs));
    if (dueAt.isAfter(cap)) dueAt = cap;
    _queue.add(_PendingEntry(isSnapshot, payload, dueAt));
    _queueReadyAt = dueAt;
    if (!isSnapshot) _lastQueuedType = type;
    _scheduleDrain();
  }

  /// Pause inserted before [type] given the previously enqueued [prev].
  int _gapMs(String type, String? prev) {
    if (type == 'trickEnded') return beatHoldMs; // let the full trick be seen
    if (prev == 'trickEnded') return postTrickMs; // breath after the vacuum
    if (type == 'dealStarted' && prev == 'dealEnded') return dealTransitionMs;
    if (type == 'gameEnded') return gameOverMs; // final summary stays visible
    return 0;
  }

  void _scheduleDrain() {
    if (_drainTimer != null || _queue.isEmpty) return;
    final wait = _queue.first.dueAt.difference(clock.now());
    if (wait <= Duration.zero) {
      _drain();
    } else {
      _drainTimer = Timer(wait, () {
        _drainTimer = null;
        _drain();
      });
    }
  }

  void _drain() {
    while (_queue.isNotEmpty && !_queue.first.dueAt.isAfter(clock.now())) {
      _applyEntry(_queue.removeFirst());
    }
    _scheduleDrain();
  }

  /// Applies everything still pending, ignoring dueAt (socket close).
  void _flushQueue() {
    _drainTimer?.cancel();
    _drainTimer = null;
    while (_queue.isNotEmpty) {
      _applyEntry(_queue.removeFirst());
    }
    _queueReadyAt = null;
    _lastQueuedType = null;
  }

  void _resetQueue() {
    _drainTimer?.cancel();
    _drainTimer = null;
    _queue.clear();
    _queueReadyAt = null;
    _lastQueuedType = null;
    _flushOnSnapshot = false;
  }

  void _applyEntry(_PendingEntry e) =>
      e.isSnapshot ? _applySnapshotBody(e.payload) : _applyEventBody(e.payload);

  // ------------------------------------------------------- state updates

  void _applySnapshotBody(Map<String, Object?> m) {
    final view = asMap(m['view']);
    final nicknames = (m['nicknames'] as List? ?? const []).map((e) => '$e').toList();
    final connected = (m['connected'] as List? ?? const []).map((e) => e == true).toList();
    final seatViews = (view['seats'] as List? ?? const []).map((raw) {
      final s = asMap(raw);
      final seat = (s['seat'] as num).toInt();
      return SeatState(
        seat: seat,
        nickname: seat < nicknames.length ? nicknames[seat] : 'Игрок ${seat + 1}',
        connected: seat < connected.length ? connected[seat] : true,
        handCount: (s['handCount'] as num).toInt(),
        wonCount: (s['wonCount'] as num).toInt(),
        score: (s['score'] as num).toInt(),
      );
    }).toList();

    final phase = '${view['phase']}';
    state = state.copyWith(
      roomPhase: phase == 'GAME_OVER' ? RoomPhase.gameOver : RoomPhase.playing,
      phase: phase,
      mySeat: (view['seat'] as num).toInt(),
      dealIndex: (view['dealIndex'] as num).toInt(),
      playerCount: (view['playerCount'] as num).toInt(),
      scoreLimit: (view['scoreLimit'] as num).toInt(),
      multiplier: (view['multiplier'] as num).toInt(),
      trumpSuit: (view['trumpSuit'] as num).toInt(),
      trumpCard: (view['trumpCard'] as num?)?.toInt(),
      stockCount: (view['stockCount'] as num).toInt(),
      seats: seatViews,
      myHand: asIntList(view['myHand']),
      myWonPile: asIntList(view['myWonPile']),
      trick: view['trick'] == null ? null : TrickState.fromWire(asMap(view['trick'])),
      legal: view['legal'] == null ? null : LegalActions.fromWire(asMap(view['legal'])),
      deadline: (m['deadline'] as num?)?.toInt() ?? 0,
      goats: view['goats'] == null ? null : asIntList(view['goats']),
    );
  }

  void _applyEventBody(Map<String, Object?> m) {
    final type = '${m['type']}';
    _tableEvents.add(TableEvent(type, m));

    switch (type) {
      case 'lobby':
        final seats = (m['seats'] as List? ?? const []).map((raw) {
          final s = asMap(raw);
          return LobbySeat(
            seat: (s['seat'] as num).toInt(),
            nickname: '${s['nickname']}',
            ready: s['ready'] == true,
            connected: s['connected'] == true,
            isHost: s['isHost'] == true,
          );
        }).toList();
        // The server tags every lobby event with the recipient's seat
        // ('you'); nicknames are not unique, so this is the only reliable
        // way to know which seat is mine before the game starts.
        final you = m['you'];
        state = state.copyWith(
          roomPhase: state.roomPhase == RoomPhase.connecting ? RoomPhase.lobby : state.roomPhase,
          lobbySeats: seats,
          lobbyCanStart: m['canStart'] == true,
          mySeat: you is num && you >= 0 ? you.toInt() : null,
        );

      case 'dealStarted':
        state = state.copyWith(
          roomPhase: RoomPhase.playing,
          dealIndex: (m['dealIndex'] as num).toInt(),
          multiplier: (m['multiplier'] as num).toInt(),
          myHand: const [],
          myWonPile: const [],
          seats: [for (final s in state.seats) s.copyWith(handCount: 0, wonCount: 0)],
          trick: null,
          legal: null,
          lastDealResults: null,
        );

      case 'yourDraw':
        state = state.copyWith(myHand: [...state.myHand, ...asIntList(m['cards'])]);

      case 'cardDrawn':
        final seat = (m['seat'] as num).toInt();
        state = state.copyWith(
          stockCount: (m['stockCount'] as num).toInt(),
          seats: _mutateSeat(seat, (s) => s.copyWith(handCount: s.handCount + 1)),
        );

      case 'trumpRevealed':
        state = state.copyWith(
          trumpSuit: (m['suit'] as num).toInt(),
          trumpCard: (m['card'] as num).toInt(),
        );

      case 'led':
        final seat = (m['seat'] as num).toInt();
        final cards = asIntList(m['cards']);
        final trick = state.trick ??
            TrickState(leader: seat, k: cards.length, turn: seat, sets: const [], discards: const []);
        state = state.copyWith(
          trick: TrickState(
            leader: seat,
            k: cards.length,
            turn: trick.turn,
            sets: [TableSet(owner: seat, kind: 'lead', cards: cards)],
            discards: const [],
          ),
          seats: _mutateSeat(seat, (s) => s.copyWith(handCount: s.handCount - cards.length)),
        );

      case 'beaten':
        final seat = (m['seat'] as num).toInt();
        final pairing = <int, int>{
          for (final p in (m['pairs'] as List? ?? const []))
            (asMap(p)['target'] as num).toInt(): (asMap(p)['card'] as num).toInt(),
        };
        final trick = state.trick;
        if (trick != null) {
          state = state.copyWith(
            trick: trick.copyWith(sets: [
              ...trick.sets,
              TableSet(owner: seat, kind: 'beat', cards: pairing.values.toList(), pairing: pairing),
            ]),
            seats: _mutateSeat(seat, (s) => s.copyWith(handCount: s.handCount - pairing.length)),
          );
        }

      case 'discarded':
        final seat = (m['seat'] as num).toInt();
        final count = (m['count'] as num).toInt();
        final trick = state.trick;
        if (trick != null) {
          state = state.copyWith(
            trick: trick.copyWith(discards: [...trick.discards, DiscardMarker(seat, count)]),
            seats: _mutateSeat(seat, (s) => s.copyWith(handCount: s.handCount - count)),
          );
        }

      case 'trickEnded':
        final winner = (m['winner'] as num).toInt();
        final count = (m['cardCount'] as num).toInt();
        state = state.copyWith(
          trick: null,
          legal: null,
          seats: _mutateSeat(winner, (s) => s.copyWith(wonCount: s.wonCount + count)),
        );

      case 'pileReveal':
        state = state.copyWith(myWonPile: [...state.myWonPile, ...asIntList(m['cards'])]);

      case 'turn':
        final seat = (m['seat'] as num).toInt();
        final trick = state.trick;
        state = state.copyWith(
          phase: '${m['phase']}',
          deadline: (m['deadline'] as num?)?.toInt() ?? 0,
          trick: trick?.copyWith(turn: seat) ??
              TrickState(leader: seat, k: 0, turn: seat, sets: const [], discards: const []),
          // stale affordances die with the turn; our own arrive via snapshot
          legal: null,
        );

      case 'dealEnded':
        final results = (m['results'] as List? ?? const []).map((raw) {
          final r = asMap(raw);
          return DealResult(
            seat: (r['seat'] as num).toInt(),
            cardPoints: (r['cardPoints'] as num).toInt(),
            penalty: (r['penalty'] as num).toInt(),
            score: (r['score'] as num).toInt(),
          );
        }).toList();
        state = state.copyWith(
          lastDealResults: results,
          seats: [
            for (final s in state.seats)
              s.copyWith(score: results.firstWhere((r) => r.seat == s.seat, orElse: () => DealResult(seat: s.seat, cardPoints: 0, penalty: 0, score: s.score)).score),
          ],
        );

      case 'gameEnded':
        state = state.copyWith(
          roomPhase: RoomPhase.gameOver,
          phase: 'GAME_OVER',
          goats: asIntList(m['goats']),
          finalScores: asIntList(m['scores']),
          trick: null,
          legal: null,
        );

      case 'playerConnection':
        final seat = (m['seat'] as num).toInt();
        state = state.copyWith(
          seats: _mutateSeat(seat, (s) => s.copyWith(connected: m['connected'] == true)),
        );
    }
  }

  List<SeatState> _mutateSeat(int seat, SeatState Function(SeatState) fn) =>
      [for (final s in state.seats) s.seat == seat ? fn(s) : s];
}

final gameControllerProvider = NotifierProvider<GameController, GameUiState>(GameController.new);
