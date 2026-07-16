import { type CardId, type LegalActions, type Seat, rankOf, suitOf } from '@goat/shared';
import { beatMatrix, hasPerfectMatching } from './rules.js';
import type { GameState } from './types.js';

/**
 * The single source of legality. Returns null unless it is `seat`'s turn.
 * The server forwards the result to the client for UI affordances.
 */
export function legalActions(state: GameState, seat: Seat): LegalActions | null {
  if (state.phase === 'GAME_OVER' || !state.trick || state.trick.turn !== seat) return null;
  const hand = state.players[seat]!.hand;

  if (state.phase === 'TRICK_LEAD') {
    const rankGroups: Record<number, CardId[]> = {};
    const suitGroups: Record<number, CardId[]> = {};
    for (const c of hand) {
      (rankGroups[rankOf(c)] ??= []).push(c);
      (suitGroups[suitOf(c)] ??= []).push(c);
    }
    return { kind: 'lead', maxCount: hand.length, rankGroups, suitGroups };
  }

  const target = state.trick.sets[state.trick.sets.length - 1]!;
  const matrix = beatMatrix(target, hand, state.trumpSuit);
  const canBeat = hand.length >= state.trick.k && hasPerfectMatching(matrix);

  if (state.phase === 'TRICK_RESPOND') {
    return { kind: 'respond', beatMatrix: matrix, canBeat, discardCount: state.trick.k };
  }
  // TRICK_LEADER_DECISION
  return { kind: 'leaderDecision', beatMatrix: matrix, canBeat, canEnd: true };
}
