import type { CardId, Seat, Suit, RankIndex } from './cards.js';
import type { Phase } from './enums.js';
import type { BeatPair, LegalActions } from './actions.js';

/** A set of cards thrown onto the table (a lead, or a beat covering the previous set). */
export interface ThrowSetView {
  owner: Seat;
  kind: 'lead' | 'beat';
  cards: CardId[];
  /** For beats: how `cards` cover the previous set (public information). */
  pairing?: BeatPair[];
}

export interface TrickView {
  leader: Seat;
  /** Cards per set this trick (fixed by the lead). */
  k: number;
  /** Seat to move. */
  turn: Seat;
  sets: ThrowSetView[];
  /** Face-down discards: contents hidden, counts public. */
  discards: { seat: Seat; count: number }[];
}

export interface SeatView {
  seat: Seat;
  handCount: number;
  wonCount: number;
  score: number;
}

/**
 * Everything one player may know. The server builds this with `redact(state, seat)`
 * and it is the ONLY game state that ever leaves the server.
 */
export interface PlayerView {
  seat: Seat;
  phase: Phase;
  dealIndex: number;
  playerCount: number;
  scoreLimit: number;
  trumpSuit: Suit;
  /** Currently face-up trump card (initial reveal or last rotation), if any. */
  trumpCard: CardId | null;
  /** Rank of the deal's FIRST revealed trump card (drives ×2/×3). */
  initialTrumpRank: RankIndex;
  multiplier: 1 | 2 | 3;
  stockCount: number;
  seats: SeatView[];
  myHand: CardId[];
  /** Own won pile, including face-down cards collected — owner may always review it. */
  myWonPile: CardId[];
  trick: TrickView | null;
  lastTrickWinner: Seat | null;
  goats: Seat[] | null;
  /** Present iff it is this player's turn. */
  legal: LegalActions | null;
}

/** Per-player deal result, broadcast at deal end (pile contents are never broadcast). */
export interface DealResult {
  seat: Seat;
  cardPoints: number;
  penalty: number; // already multiplied
  score: number; // running score after this deal
}
