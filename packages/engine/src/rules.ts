import { type BeatPair, type CardId, type Suit, isShoha, rankOf, suitOf } from '@goat/shared';
import type { ThrowSet } from './types.js';

/** A lead is 1+ cards, all of one rank OR all of one suit. */
export function isLegalLeadShape(cards: readonly CardId[]): boolean {
  if (cards.length === 0) return false;
  const first = cards[0]!;
  return (
    cards.every((c) => rankOf(c) === rankOf(first)) || cards.every((c) => suitOf(c) === suitOf(first))
  );
}

/**
 * Does `b` beat `t`?
 * - A shoha played as part of a BEAT set is unbeatable; led, it is an ordinary 6♣.
 * - The shoha as the beating card beats anything.
 * - Otherwise: same suit + strictly higher rank (rankIndex IS strength), or trump over non-trump.
 */
export function beats(b: CardId, t: CardId, trump: Suit, targetSetKind: 'lead' | 'beat'): boolean {
  if (isShoha(t) && targetSetKind === 'beat') return false;
  if (isShoha(b)) return true;
  if (suitOf(b) === suitOf(t)) return rankOf(b) > rankOf(t);
  return suitOf(b) === trump && suitOf(t) !== trump;
}

/** target card → hand cards that beat it. */
export function beatMatrix(targetSet: ThrowSet, hand: readonly CardId[], trump: Suit): Record<number, CardId[]> {
  const m: Record<number, CardId[]> = {};
  for (const t of targetSet.cards) {
    m[t] = hand.filter((b) => beats(b, t, trump, targetSet.kind));
  }
  return m;
}

/**
 * Find a perfect matching covering every target (Kuhn's algorithm), or null.
 * Sizes are ≤ 6, so complexity is irrelevant.
 */
export function findPerfectMatching(matrix: Record<number, CardId[]>): BeatPair[] | null {
  const targets = Object.keys(matrix).map(Number);
  const matchedBy = new Map<CardId, number>(); // hand card -> target

  const tryAssign = (t: number, visited: Set<CardId>): boolean => {
    for (const c of matrix[t] ?? []) {
      if (visited.has(c)) continue;
      visited.add(c);
      const holder = matchedBy.get(c);
      if (holder === undefined || tryAssign(holder, visited)) {
        matchedBy.set(c, t);
        return true;
      }
    }
    return false;
  };

  if (!targets.every((t) => tryAssign(t, new Set()))) return null;
  return [...matchedBy.entries()].map(([card, target]) => ({ target, card }));
}

export const hasPerfectMatching = (matrix: Record<number, CardId[]>): boolean =>
  findPerfectMatching(matrix) !== null;
