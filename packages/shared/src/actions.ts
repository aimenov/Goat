import type { CardId, Seat } from './cards.js';

/** One covered card: `card` (from the actor's hand) beats `target` (on the table). */
export interface BeatPair {
  target: CardId;
  card: CardId;
}

export type GameAction =
  | { type: 'LEAD'; seat: Seat; cards: CardId[] }
  | { type: 'BEAT'; seat: Seat; pairs: BeatPair[] }
  | { type: 'DISCARD'; seat: Seat; cards: CardId[] }
  | { type: 'END_TRICK'; seat: Seat };

/**
 * Legal-action affordances for the seat to move. The server computes these with the
 * engine and sends them with every turn — the client never re-implements rules.
 */
export type LegalActions =
  | {
      kind: 'lead';
      /** Max cards in a lead (= own hand size; hands are always equal). */
      maxCount: number;
      /** rankIndex → cardIds in hand of that rank (only ranks with ≥1 card). */
      rankGroups: Record<number, CardId[]>;
      /** suit → cardIds in hand of that suit (only suits with ≥1 card). */
      suitGroups: Record<number, CardId[]>;
    }
  | {
      kind: 'respond';
      /** target cardId (in the newest table set) → hand cardIds that beat it. */
      beatMatrix: Record<number, CardId[]>;
      /** True iff a full k-card cover exists (bipartite perfect matching). */
      canBeat: boolean;
      /** Number of face-down cards a discard requires (= k). */
      discardCount: number;
    }
  | {
      kind: 'leaderDecision';
      beatMatrix: Record<number, CardId[]>;
      canBeat: boolean;
      /** Ending the trick is always legal for the leader. */
      canEnd: true;
    };
