/**
 * Card encoding: a card is a uint8 in [0, 35]: id = suit * 9 + rankIndex.
 *
 * Rank order (low → high) is Goat-specific: 6 < 7 < 8 < 9 < J < Q < K < 10 < A.
 * rankIndex IS the strength: comparing rankIndex compares rank.
 */

export type CardId = number; // 0..35
export type Suit = 0 | 1 | 2 | 3;
export type RankIndex = 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
export type Seat = number; // 0..playerCount-1

export const SUITS = ['spades', 'clubs', 'diamonds', 'hearts'] as const;
export const SUIT_SYMBOLS = ['♠', '♣', '♦', '♥'] as const;

/** Rank labels in strength order (index = rankIndex). */
export const RANKS = ['6', '7', '8', '9', 'J', 'Q', 'K', '10', 'A'] as const;

/** Card points by rankIndex. Deck total = 120. */
export const RANK_POINTS = [0, 0, 0, 0, 2, 3, 4, 10, 11] as const;

export const DECK_SIZE = 36;
export const HAND_SIZE = 6;
export const TOTAL_POINTS = 120;

/** Шоха — the 6 of clubs. Unbeatable when played as a beating card. */
export const SHOHA: CardId = 1 * 9 + 0; // 9

export const suitOf = (c: CardId): Suit => Math.floor(c / 9) as Suit;
export const rankOf = (c: CardId): RankIndex => (c % 9) as RankIndex;
export const pointsOf = (c: CardId): number => RANK_POINTS[rankOf(c)]!;
export const isShoha = (c: CardId): boolean => c === SHOHA;
export const cardOf = (suit: Suit, rank: RankIndex): CardId => suit * 9 + rank;

export const isValidCard = (c: unknown): c is CardId =>
  typeof c === 'number' && Number.isInteger(c) && c >= 0 && c < DECK_SIZE;

export const cardName = (c: CardId): string => `${RANKS[rankOf(c)]}${SUIT_SYMBOLS[suitOf(c)]}`;

export const sumPoints = (cards: readonly CardId[]): number =>
  cards.reduce((s, c) => s + pointsOf(c), 0);

/** All 36 cards, ordered by id. */
export const fullDeck = (): CardId[] => Array.from({ length: DECK_SIZE }, (_, i) => i);
