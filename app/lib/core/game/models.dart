/// Client-side game state, built from server snapshots + seq'd events.
/// Mirrors the wire types in `@goat/shared` (protocol.ts / view.ts).
library;

Map<String, Object?> asMap(Object? raw) =>
    (raw as Map).map((k, v) => MapEntry('$k', v));

List<int> asIntList(Object? raw) =>
    (raw as List? ?? const []).map((e) => (e as num).toInt()).toList();

class TableSet {
  final int owner;
  final String kind; // 'lead' | 'beat'
  final List<int> cards;

  /// For beats: target card id → beating card id (public info).
  final Map<int, int> pairing;

  const TableSet({required this.owner, required this.kind, required this.cards, this.pairing = const {}});

  factory TableSet.fromWire(Map<String, Object?> m) => TableSet(
        owner: (m['owner'] as num).toInt(),
        kind: '${m['kind']}',
        cards: asIntList(m['cards']),
        pairing: {
          for (final p in (m['pairing'] as List? ?? const []))
            (asMap(p)['target'] as num).toInt(): (asMap(p)['card'] as num).toInt(),
        },
      );
}

class DiscardMarker {
  final int seat;
  final int count;
  const DiscardMarker(this.seat, this.count);
}

class TrickState {
  final int leader;
  final int k;
  final int turn;
  final List<TableSet> sets;
  final List<DiscardMarker> discards;

  const TrickState({required this.leader, required this.k, required this.turn, required this.sets, required this.discards});

  factory TrickState.fromWire(Map<String, Object?> m) => TrickState(
        leader: (m['leader'] as num).toInt(),
        k: (m['k'] as num).toInt(),
        turn: (m['turn'] as num).toInt(),
        sets: [for (final s in m['sets'] as List? ?? const []) TableSet.fromWire(asMap(s))],
        discards: [
          for (final d in m['discards'] as List? ?? const [])
            DiscardMarker((asMap(d)['seat'] as num).toInt(), (asMap(d)['count'] as num).toInt()),
        ],
      );

  TrickState copyWith({int? turn, List<TableSet>? sets, List<DiscardMarker>? discards}) => TrickState(
        leader: leader,
        k: k,
        turn: turn ?? this.turn,
        sets: sets ?? this.sets,
        discards: discards ?? this.discards,
      );
}

class SeatState {
  final int seat;
  final String nickname;
  final bool connected;
  final int handCount;
  final int wonCount;
  final int score;

  const SeatState({
    required this.seat,
    required this.nickname,
    required this.connected,
    required this.handCount,
    required this.wonCount,
    required this.score,
  });

  SeatState copyWith({String? nickname, bool? connected, int? handCount, int? wonCount, int? score}) => SeatState(
        seat: seat,
        nickname: nickname ?? this.nickname,
        connected: connected ?? this.connected,
        handCount: handCount ?? this.handCount,
        wonCount: wonCount ?? this.wonCount,
        score: score ?? this.score,
      );
}

/// Legal-action affordances for the local player (server-computed).
class LegalActions {
  final String kind; // 'lead' | 'respond' | 'leaderDecision'
  final int maxCount;
  final Map<int, List<int>> rankGroups;
  final Map<int, List<int>> suitGroups;
  final Map<int, List<int>> beatMatrix;
  final bool canBeat;
  final int discardCount;

  const LegalActions({
    required this.kind,
    this.maxCount = 0,
    this.rankGroups = const {},
    this.suitGroups = const {},
    this.beatMatrix = const {},
    this.canBeat = false,
    this.discardCount = 0,
  });

  factory LegalActions.fromWire(Map<String, Object?> m) {
    Map<int, List<int>> groups(Object? raw) =>
        (raw as Map? ?? const {}).map((k, v) => MapEntry(int.parse('$k'), asIntList(v)));
    return LegalActions(
      kind: '${m['kind']}',
      maxCount: (m['maxCount'] as num?)?.toInt() ?? 0,
      rankGroups: groups(m['rankGroups']),
      suitGroups: groups(m['suitGroups']),
      beatMatrix: groups(m['beatMatrix']),
      canBeat: m['canBeat'] == true,
      discardCount: (m['discardCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class LobbySeat {
  final int seat;
  final String nickname;
  final bool ready;
  final bool connected;
  final bool isHost;
  const LobbySeat({required this.seat, required this.nickname, required this.ready, required this.connected, required this.isHost});
}

class DealResult {
  final int seat;
  final int cardPoints;
  final int penalty;
  final int score;
  const DealResult({required this.seat, required this.cardPoints, required this.penalty, required this.score});
}

enum RoomPhase { connecting, lobby, playing, reconnecting, gameOver }

class GameUiState {
  final RoomPhase roomPhase;
  final String phase; // engine phase
  final int mySeat;
  final int dealIndex;
  final int playerCount;
  final int scoreLimit;
  final int multiplier;
  final int trumpSuit;
  final int? trumpCard;
  final int stockCount;
  final List<SeatState> seats;
  final List<int> myHand;
  final List<int> myWonPile;
  final TrickState? trick;
  final LegalActions? legal;
  final int deadline; // ms epoch, 0 = none
  final List<LobbySeat> lobbySeats;
  final bool lobbyCanStart;
  final List<DealResult>? lastDealResults;
  final List<int>? goats;
  final List<int>? finalScores;

  const GameUiState({
    this.roomPhase = RoomPhase.connecting,
    this.phase = '',
    this.mySeat = -1,
    this.dealIndex = 0,
    this.playerCount = 0,
    this.scoreLimit = 24,
    this.multiplier = 1,
    this.trumpSuit = 0,
    this.trumpCard,
    this.stockCount = 0,
    this.seats = const [],
    this.myHand = const [],
    this.myWonPile = const [],
    this.trick,
    this.legal,
    this.deadline = 0,
    this.lobbySeats = const [],
    this.lobbyCanStart = false,
    this.lastDealResults,
    this.goats,
    this.finalScores,
  });

  bool get isMyTurn => trick != null && trick!.turn == mySeat && legal != null;

  GameUiState copyWith({
    RoomPhase? roomPhase,
    String? phase,
    int? mySeat,
    int? dealIndex,
    int? playerCount,
    int? scoreLimit,
    int? multiplier,
    int? trumpSuit,
    Object? trumpCard = _sentinel,
    int? stockCount,
    List<SeatState>? seats,
    List<int>? myHand,
    List<int>? myWonPile,
    Object? trick = _sentinel,
    Object? legal = _sentinel,
    int? deadline,
    List<LobbySeat>? lobbySeats,
    bool? lobbyCanStart,
    Object? lastDealResults = _sentinel,
    Object? goats = _sentinel,
    Object? finalScores = _sentinel,
  }) =>
      GameUiState(
        roomPhase: roomPhase ?? this.roomPhase,
        phase: phase ?? this.phase,
        mySeat: mySeat ?? this.mySeat,
        dealIndex: dealIndex ?? this.dealIndex,
        playerCount: playerCount ?? this.playerCount,
        scoreLimit: scoreLimit ?? this.scoreLimit,
        multiplier: multiplier ?? this.multiplier,
        trumpSuit: trumpSuit ?? this.trumpSuit,
        trumpCard: trumpCard == _sentinel ? this.trumpCard : trumpCard as int?,
        stockCount: stockCount ?? this.stockCount,
        seats: seats ?? this.seats,
        myHand: myHand ?? this.myHand,
        myWonPile: myWonPile ?? this.myWonPile,
        trick: trick == _sentinel ? this.trick : trick as TrickState?,
        legal: legal == _sentinel ? this.legal : legal as LegalActions?,
        deadline: deadline ?? this.deadline,
        lobbySeats: lobbySeats ?? this.lobbySeats,
        lobbyCanStart: lobbyCanStart ?? this.lobbyCanStart,
        lastDealResults: lastDealResults == _sentinel ? this.lastDealResults : lastDealResults as List<DealResult>?,
        goats: goats == _sentinel ? this.goats : goats as List<int>?,
        finalScores: finalScores == _sentinel ? this.finalScores : finalScores as List<int>?,
      );
}

const _sentinel = Object();
