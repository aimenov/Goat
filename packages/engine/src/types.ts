import type { BeatPair, CardId, DealResult, ErrorCode, Phase, RankIndex, Seat, Suit } from '@goat/shared';
import type { RngState } from './rng.js';

export interface EngineOptions {
  playerCount: number; // 2 | 3 | 4 | 6
  scoreLimit: number; // 24 | 36
  seed: number;
}

export interface PlayerState {
  hand: CardId[];
  /** Won pile: every card taken in tricks, incl. face-down discards. Owner-visible only. */
  won: CardId[];
  score: number;
}

export interface ThrowSet {
  owner: Seat;
  kind: 'lead' | 'beat';
  cards: CardId[];
  pairing?: BeatPair[];
}

export interface DiscardPile {
  seat: Seat;
  /** Hidden from everyone until the trick winner collects them. */
  cards: CardId[];
}

export interface TrickState {
  leader: Seat;
  /** Set size, fixed by the lead (0 before the lead). */
  k: number;
  turn: Seat;
  sets: ThrowSet[];
  discards: DiscardPile[];
}

/**
 * FULL game state — perfect information. Never leaves the server.
 * Clients only ever see `redact(state, seat)`.
 */
export interface GameState {
  options: EngineOptions;
  rng: RngState;
  phase: Phase;
  dealIndex: number;
  players: PlayerState[];
  /** stock[0] is drawn next; the initial trump card sits at the end (drawn last). */
  stock: CardId[];
  trumpSuit: Suit;
  trumpCard: CardId | null;
  initialTrumpRank: RankIndex;
  multiplier: 1 | 2 | 3;
  trick: TrickState | null;
  /** Winner of the most recent trick (leads next; carries into the next deal). */
  lastTrickWinner: Seat | null;
  goats: Seat[] | null;
}

/**
 * Full-information events emitted by the reducer, in order. The server redacts
 * them per viewer before sending; the client animates from them.
 */
export type EngineEvent =
  | { type: 'dealStarted'; dealIndex: number; leader: Seat; multiplier: 1 | 2 | 3 }
  | { type: 'cardsDealt'; hands: CardId[][] }
  | { type: 'trumpRevealed'; card: CardId; suit: Suit; source: 'initial' | 'rotation' | 'lastDealt'; toSeat?: Seat }
  | { type: 'led'; seat: Seat; cards: CardId[] }
  | { type: 'beaten'; seat: Seat; pairs: BeatPair[] }
  | { type: 'discarded'; seat: Seat; cards: CardId[] }
  | { type: 'trickEnded'; winner: Seat; faceUp: CardId[]; faceDown: CardId[] }
  | { type: 'cardDrawn'; seat: Seat; card: CardId; stockCount: number }
  | { type: 'turn'; seat: Seat; phase: Phase }
  | { type: 'dealEnded'; results: DealResult[] }
  | { type: 'gameEnded'; goats: Seat[]; scores: number[] };

export type ReduceResult = { ok: true; state: GameState; events: EngineEvent[] } | { ok: false; error: ErrorCode };
