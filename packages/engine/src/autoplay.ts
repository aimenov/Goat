import { type CardId, type GameAction, pointsOf, rankOf } from '@goat/shared';
import { splitmix32 } from './rng.js';
import { legalActions } from './legal.js';
import type { GameState } from './types.js';

/** Lowest points, then lowest rank, then lowest id — a stable "cheapest card" order. */
const byCheapness = (a: CardId, b: CardId): number =>
  pointsOf(a) - pointsOf(b) || rankOf(a) - rankOf(b) || a - b;

/**
 * Default action for the seat to move (turn timeout / disconnected autopilot).
 * Deterministic given the state, but discard choices are seeded-random so
 * opponents cannot infer the face-down cards from the policy.
 */
export function defaultAction(state: GameState): GameAction {
  const trick = state.trick!;
  const seat = trick.turn;
  const legal = legalActions(state, seat)!;
  const hand = state.players[seat]!.hand;

  switch (legal.kind) {
    case 'lead': {
      const card = [...hand].sort(byCheapness)[0]!;
      return { type: 'LEAD', seat, cards: [card] };
    }
    case 'respond': {
      // Seeded by immutable state facts: same state → same action (replayable),
      // but not the predictable "k lowest cards".
      const rnd = splitmix32(
        (state.options.seed ^ (state.dealIndex * 2654435761) ^ (trick.sets.length * 40503) ^ (seat * 97)) >>> 0,
      );
      const pool = [...hand];
      const picked: CardId[] = [];
      for (let i = 0; i < legal.discardCount; i++) {
        picked.push(pool.splice(rnd() % pool.length, 1)[0]!);
      }
      return { type: 'DISCARD', seat, cards: picked };
    }
    case 'leaderDecision':
      return { type: 'END_TRICK', seat };
  }
}
