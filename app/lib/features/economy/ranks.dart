/// The goat rank ladder — a Dart mirror of the canonical table in
/// packages/shared/src/economy.ts. Thresholds/emoji/RU must match the server;
/// the client uses [rankForRating] both to display the current rank and to
/// detect band crossings (rank-up celebration) locally.
library;

class RankDef {
  final String id;
  final String ru;
  final String emoji;

  /// Minimum rating for this rank (rating floor is 100 server-side).
  final int minRating;

  const RankDef({
    required this.id,
    required this.ru,
    required this.emoji,
    required this.minRating,
  });
}

/// Ascending by [RankDef.minRating]; rating starts at 1000.
const List<RankDef> rankDefs = [
  RankDef(id: 'kid', ru: 'Козлёнок', emoji: '🍼', minRating: 0),
  RankDef(id: 'young', ru: 'Молодой козлик', emoji: '🌱', minRating: 900),
  RankDef(id: 'common', ru: 'Козёл обыкновенный', emoji: '🐐', minRating: 1000),
  RankDef(id: 'scapegoat', ru: 'Козёл отпущения', emoji: '🙃', minRating: 1100),
  RankDef(id: 'trump', ru: 'Козырный козёл', emoji: '🃏', minRating: 1250),
  RankDef(id: 'aristocrat', ru: 'Козёл-аристократ', emoji: '🎩', minRating: 1400),
  RankDef(id: 'professor', ru: 'Козёл-профессор', emoji: '🎓', minRating: 1550),
  RankDef(id: 'seasoned', ru: 'Матёрый козёл', emoji: '🔥', minRating: 1750),
];

/// The highest rank whose threshold [rating] reaches (negative ratings clamp
/// to the first band).
RankDef rankForRating(int rating) {
  var result = rankDefs.first;
  for (final def in rankDefs) {
    if (rating >= def.minRating) result = def;
  }
  return result;
}
