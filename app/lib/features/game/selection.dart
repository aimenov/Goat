/// Pure client-side helpers for selecting cards on the table.
library;

import '../../core/cards.dart';

/// A lead selection is valid when it is non-empty and all cards share
/// the same rank OR the same suit.
bool isValidLeadSelection(List<int> cards) {
  if (cards.isEmpty) return false;
  final sameRank = cards.every((c) => rankOf(c) == rankOf(cards.first));
  final sameSuit = cards.every((c) => suitOf(c) == suitOf(cards.first));
  return sameRank || sameSuit;
}

/// Finds a perfect matching target -> hand card over [beatMatrix]
/// (target card id -> beating candidates), or null if none exists.
/// Backtracking search; the matrix is at most 6x6.
Map<int, int>? autoPairing(Map<int, List<int>> beatMatrix) {
  final targets = beatMatrix.keys.toList()
    ..sort((a, b) =>
        (beatMatrix[a]?.length ?? 0).compareTo(beatMatrix[b]?.length ?? 0));
  final used = <int>{};
  final result = <int, int>{};

  bool solve(int i) {
    if (i == targets.length) return true;
    final target = targets[i];
    for (final card in beatMatrix[target] ?? const <int>[]) {
      if (used.contains(card)) continue;
      used.add(card);
      result[target] = card;
      if (solve(i + 1)) return true;
      used.remove(card);
      result.remove(target);
    }
    return false;
  }

  return solve(0) ? result : null;
}
