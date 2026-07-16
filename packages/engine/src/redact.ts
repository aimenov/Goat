import type { EngineEvent } from './types.js';
import type { PlayerView, Seat } from '@goat/shared';
import { legalActions } from './legal.js';
import type { GameState } from './types.js';

/**
 * The only game state that may ever be sent to a client. Hides other hands
 * (counts only), the stock, face-down discards, and other players' won piles.
 */
export function redact(state: GameState, viewer: Seat): PlayerView {
  const me = state.players[viewer]!;
  return {
    seat: viewer,
    phase: state.phase,
    dealIndex: state.dealIndex,
    playerCount: state.options.playerCount,
    scoreLimit: state.options.scoreLimit,
    trumpSuit: state.trumpSuit,
    trumpCard: state.trumpCard,
    initialTrumpRank: state.initialTrumpRank,
    multiplier: state.multiplier,
    stockCount: state.stock.length,
    seats: state.players.map((p, seat) => ({
      seat,
      handCount: p.hand.length,
      wonCount: p.won.length,
      score: p.score,
    })),
    myHand: [...me.hand],
    myWonPile: [...me.won],
    trick: state.trick
      ? {
          leader: state.trick.leader,
          k: state.trick.k,
          turn: state.trick.turn,
          sets: state.trick.sets.map((s) => ({
            owner: s.owner,
            kind: s.kind,
            cards: [...s.cards],
            ...(s.pairing ? { pairing: s.pairing.map((p) => ({ ...p })) } : {}),
          })),
          discards: state.trick.discards.map((d) => ({ seat: d.seat, count: d.cards.length })),
        }
      : null,
    lastTrickWinner: state.lastTrickWinner,
    goats: state.goats,
    legal: legalActions(state, viewer),
  };
}

/**
 * Redact a full-information engine event for one viewer. Returns null when the
 * viewer receives nothing beyond the public variant (callers send the public
 * form separately). Private data flows through dedicated messages:
 * - `cardsDealt` / `cardDrawn`: card identities only to their owner
 * - `discarded`: card identities to no one (count is public)
 * - `trickEnded`: face-down contents only to the winner
 */
export function redactEvent(event: EngineEvent, viewer: Seat): EngineEvent | { type: string; [k: string]: unknown } {
  switch (event.type) {
    case 'cardsDealt':
      return { type: 'cardsDealt', hands: event.hands.map((h, seat) => (seat === viewer ? [...h] : h.map(() => -1))) };
    case 'cardDrawn':
      return viewer === event.seat ? event : { ...event, card: -1 };
    case 'discarded':
      return viewer === event.seat ? event : { type: 'discarded', seat: event.seat, cards: event.cards.map(() => -1) };
    case 'trickEnded':
      return viewer === event.winner ? event : { ...event, faceDown: event.faceDown.map(() => -1) };
    default:
      return event;
  }
}
