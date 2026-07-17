/// Wires a [GameRoom] message stream into [GameUiState] and exposes intents.
/// Events drive incremental updates (and, later, animations); snapshots are
/// authoritative full replacements (join, reconnect, own turn, seq gap).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/transport.dart';
import 'models.dart';

/// Transient one-shot events the UI reacts to (animations, toasts, reactions).
class TableEvent {
  final String type;
  final Map<String, Object?> data;
  const TableEvent(this.type, this.data);
}

class GameController extends Notifier<GameUiState> {
  GameRoom? _room;
  StreamSubscription<(String, Object?)>? _sub;
  int _lastSeq = -1;
  int _actionCounter = 0;
  final _tableEvents = StreamController<TableEvent>.broadcast();
  final _rejections = StreamController<String>.broadcast();

  Stream<TableEvent> get tableEvents => _tableEvents.stream;
  Stream<String> get rejections => _rejections.stream;

  @override
  GameUiState build() => const GameUiState();

  void attach(GameRoom room) {
    _sub?.cancel();
    _room = room;
    _lastSeq = -1;
    state = const GameUiState(roomPhase: RoomPhase.lobby);
    _sub = room.messages.listen(_onMessage);
    room.onClose.then((code) {
      // A stale room's close (after a re-attach) must not flip the healthy
      // session that replaced it into "reconnecting".
      if (!identical(_room, room)) return;
      if (code == 4000 || state.roomPhase == RoomPhase.gameOver) return;
      state = state.copyWith(roomPhase: RoomPhase.reconnecting);
    });
    send('resync', {});
  }

  void detach() {
    _sub?.cancel();
    _room = null;
    state = const GameUiState();
  }

  // ------------------------------------------------------------- intents

  void send(String type, Map<String, Object?> payload) {
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
        _applySnapshot(asMap(payload));
      case 'event':
        _applyEvent(asMap(payload));
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

  void _applySnapshot(Map<String, Object?> m) {
    final view = asMap(m['view']);
    final seq = (m['seq'] as num).toInt();
    _lastSeq = seq;
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

  void _applyEvent(Map<String, Object?> m) {
    final type = '${m['type']}';
    final seq = (m['seq'] as num?)?.toInt() ?? _lastSeq;
    if (seq > _lastSeq + 1 && type != 'lobby' && type != 'reaction') {
      send('resync', {});
    }
    _lastSeq = max(_lastSeq, seq);
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
