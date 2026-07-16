import {
  type CardId,
  type DealResult,
  type GameAction,
  type RankIndex,
  type Seat,
  type Suit,
  DECK_SIZE,
  HAND_SIZE,
  PLAYER_COUNTS,
  fullDeck,
  rankOf,
  suitOf,
  sumPoints,
} from '@goat/shared';
import { nextInt, seedRng, shuffle } from './rng.js';
import { beats, isLegalLeadShape } from './rules.js';
import { dealMultiplier, findGoats, penaltyBand } from './scoring.js';
import type { EngineEvent, EngineOptions, GameState, ReduceResult, ThrowSet, TrickState } from './types.js';

/** Rank 6 is rankIndex 0. */
const RANK_SIX: RankIndex = 0;

export function initGame(options: EngineOptions): { state: GameState; events: EngineEvent[] } {
  if (!PLAYER_COUNTS.includes(options.playerCount as never)) {
    throw new Error(`invalid playerCount ${options.playerCount}`);
  }
  const rng = seedRng(options.seed);
  const state: GameState = {
    options,
    rng,
    phase: 'TRICK_LEAD',
    dealIndex: -1,
    players: Array.from({ length: options.playerCount }, () => ({ hand: [], won: [], score: 0 })),
    stock: [],
    trumpSuit: 0,
    trumpCard: null,
    initialTrumpRank: 0,
    multiplier: 1,
    trick: null,
    lastTrickWinner: null,
    goats: null,
  };
  const events: EngineEvent[] = [];
  const firstLeader = nextInt(state.rng, options.playerCount);
  setupDeal(state, firstLeader, events);
  assertInvariants(state);
  return { state, events };
}

function setupDeal(state: GameState, leader: Seat, events: EngineEvent[]): void {
  const n = state.options.playerCount;
  state.dealIndex += 1;

  const deck = shuffle(state.rng, fullDeck());
  const hands: CardId[][] = Array.from({ length: n }, () => []);
  for (let i = 0; i < HAND_SIZE * n; i++) {
    hands[(leader + i) % n]!.push(deck[i]!);
  }
  state.players.forEach((p, seat) => {
    p.hand = hands[seat]!;
    p.won = [];
  });

  if (n < 6) {
    // Reveal the first undealt card; it goes face-up to the stock bottom (drawn last).
    const trumpCard = deck[HAND_SIZE * n]!;
    state.trumpCard = trumpCard;
    state.trumpSuit = suitOf(trumpCard);
    state.initialTrumpRank = rankOf(trumpCard);
    state.stock = [...deck.slice(HAND_SIZE * n + 1), trumpCard];
  } else {
    // 6 players: everything is dealt; the 36th card (seat right of leader) is the fixed trump.
    const lastCard = deck[DECK_SIZE - 1]!;
    state.trumpCard = lastCard;
    state.trumpSuit = suitOf(lastCard);
    state.initialTrumpRank = rankOf(lastCard);
    state.stock = [];
  }

  state.multiplier = dealMultiplier(
    state.initialTrumpRank === RANK_SIX,
    state.players.map((p) => p.score),
  );
  state.trick = { leader, k: 0, turn: leader, sets: [], discards: [] };
  state.phase = 'TRICK_LEAD';

  events.push({ type: 'dealStarted', dealIndex: state.dealIndex, leader, multiplier: state.multiplier });
  events.push({ type: 'cardsDealt', hands: hands.map((h) => [...h]) });
  events.push({
    type: 'trumpRevealed',
    card: state.trumpCard!,
    suit: state.trumpSuit,
    source: n < 6 ? 'initial' : 'lastDealt',
    ...(n === 6 ? { toSeat: ((leader + n - 1) % n) as Seat } : {}),
  });
  events.push({ type: 'turn', seat: leader, phase: 'TRICK_LEAD' });
}

const nextSeat = (state: GameState, seat: Seat): Seat => (seat + 1) % state.options.playerCount;

/** Remove `cards` from `hand`; returns false if any card is missing or duplicated. */
function takeFromHand(hand: CardId[], cards: readonly CardId[]): boolean {
  if (new Set(cards).size !== cards.length) return false;
  if (!cards.every((c) => hand.includes(c))) return false;
  for (const c of cards) hand.splice(hand.indexOf(c), 1);
  return true;
}

export function reduce(prev: GameState, action: GameAction): ReduceResult {
  if (prev.phase === 'GAME_OVER') return { ok: false, error: 'GAME_ALREADY_OVER' };
  const state = structuredClone(prev);
  const trick = state.trick!;
  if (action.seat !== trick.turn) return { ok: false, error: 'NOT_YOUR_TURN' };
  const events: EngineEvent[] = [];
  const hand = state.players[action.seat]!.hand;

  switch (action.type) {
    case 'LEAD': {
      if (state.phase !== 'TRICK_LEAD') return { ok: false, error: 'WRONG_PHASE' };
      if (!isLegalLeadShape(action.cards)) return { ok: false, error: 'ILLEGAL_LEAD_SHAPE' };
      if (!takeFromHand(hand, action.cards)) return { ok: false, error: 'CARD_NOT_IN_HAND' };
      trick.k = action.cards.length;
      trick.sets.push({ owner: action.seat, kind: 'lead', cards: [...action.cards] });
      events.push({ type: 'led', seat: action.seat, cards: [...action.cards] });
      advanceTurn(state, events);
      break;
    }

    case 'BEAT': {
      if (state.phase !== 'TRICK_RESPOND' && state.phase !== 'TRICK_LEADER_DECISION') {
        return { ok: false, error: 'WRONG_PHASE' };
      }
      const target = trick.sets[trick.sets.length - 1]!;
      if (action.pairs.length !== trick.k) return { ok: false, error: 'WRONG_CARD_COUNT' };
      const targetsUsed = action.pairs.map((p) => p.target);
      if (
        new Set(targetsUsed).size !== trick.k ||
        !targetsUsed.every((t) => target.cards.includes(t))
      ) {
        return { ok: false, error: 'ILLEGAL_BEAT' };
      }
      if (!action.pairs.every((p) => beats(p.card, p.target, state.trumpSuit, target.kind))) {
        return { ok: false, error: 'ILLEGAL_BEAT' };
      }
      const used = action.pairs.map((p) => p.card);
      if (!takeFromHand(hand, used)) return { ok: false, error: 'CARD_NOT_IN_HAND' };
      trick.sets.push({
        owner: action.seat,
        kind: 'beat',
        cards: used,
        pairing: action.pairs.map((p) => ({ ...p })),
      });
      events.push({ type: 'beaten', seat: action.seat, pairs: action.pairs.map((p) => ({ ...p })) });
      advanceTurn(state, events);
      break;
    }

    case 'DISCARD': {
      // Only responders discard; the leader ends the trick instead.
      if (state.phase !== 'TRICK_RESPOND') return { ok: false, error: 'WRONG_PHASE' };
      if (action.cards.length !== trick.k) return { ok: false, error: 'WRONG_CARD_COUNT' };
      if (!takeFromHand(hand, action.cards)) return { ok: false, error: 'CARD_NOT_IN_HAND' };
      trick.discards.push({ seat: action.seat, cards: [...action.cards] });
      events.push({ type: 'discarded', seat: action.seat, cards: [...action.cards] });
      advanceTurn(state, events);
      break;
    }

    case 'END_TRICK': {
      if (state.phase !== 'TRICK_LEADER_DECISION') return { ok: false, error: 'WRONG_PHASE' };
      resolveTrick(state, events);
      break;
    }

    default:
      return { ok: false, error: 'INVALID_PAYLOAD' };
  }

  // reduce must never create or destroy cards within a deal; a new deal
  // reshuffles the full 36-card deck.
  assertInvariants(state, state.dealIndex === prev.dealIndex ? totalCards(prev) : DECK_SIZE);
  return { ok: true, state, events };
}

/** After a lead / beat / discard: pass the turn clockwise; back at the leader = leader decision. */
function advanceTurn(state: GameState, events: EngineEvent[]): void {
  const trick = state.trick!;
  trick.turn = nextSeat(state, trick.turn);
  state.phase = trick.turn === trick.leader ? 'TRICK_LEADER_DECISION' : 'TRICK_RESPOND';
  events.push({ type: 'turn', seat: trick.turn, phase: state.phase });
}

function resolveTrick(state: GameState, events: EngineEvent[]): void {
  const trick = state.trick!;
  const winner = trick.sets[trick.sets.length - 1]!.owner;
  const faceUp = trick.sets.flatMap((s) => s.cards);
  const faceDown = trick.discards.flatMap((d) => d.cards);
  state.players[winner]!.won.push(...faceUp, ...faceDown);
  state.lastTrickWinner = winner;
  events.push({ type: 'trickEnded', winner, faceUp, faceDown });

  replenish(state, winner, events);
  if (state.players.every((p) => p.hand.length === 0)) {
    scoreDeal(state, events);
    return;
  }

  state.trick = { leader: winner, k: 0, turn: winner, sets: [], discards: [] };
  state.phase = 'TRICK_LEAD';
  events.push({ type: 'turn', seat: winner, phase: 'TRICK_LEAD' });
}

/**
 * Draw back to 6, one card at a time round-robin starting with the trick winner.
 * The last card drawn this phase is shown to all: its suit becomes the new trump.
 */
function replenish(state: GameState, winner: Seat, events: EngineEvent[]): void {
  const n = state.options.playerCount;
  let lastDrawn: CardId | null = null;
  let drew = true;
  while (drew && state.stock.length > 0) {
    drew = false;
    for (let i = 0; i < n && state.stock.length > 0; i++) {
      const seat = ((winner + i) % n) as Seat;
      const player = state.players[seat]!;
      if (player.hand.length >= HAND_SIZE) continue;
      const card = state.stock.shift()!;
      player.hand.push(card);
      lastDrawn = card;
      drew = true;
      events.push({ type: 'cardDrawn', seat, card, stockCount: state.stock.length });
    }
  }
  if (lastDrawn !== null) {
    state.trumpSuit = suitOf(lastDrawn);
    state.trumpCard = lastDrawn;
    events.push({ type: 'trumpRevealed', card: lastDrawn, suit: state.trumpSuit, source: 'rotation' });
  }
}

function scoreDeal(state: GameState, events: EngineEvent[]): void {
  const results: DealResult[] = state.players.map((p, seat) => {
    const cardPoints = sumPoints(p.won);
    const penalty = penaltyBand(cardPoints) * state.multiplier;
    p.score += penalty;
    return { seat, cardPoints, penalty, score: p.score };
  });
  events.push({ type: 'dealEnded', results });

  const scores = state.players.map((p) => p.score);
  const goats = findGoats(scores, state.options.scoreLimit);
  if (goats) {
    state.goats = goats;
    state.phase = 'GAME_OVER';
    state.trick = null;
    events.push({ type: 'gameEnded', goats, scores });
    return;
  }

  setupDeal(state, state.lastTrickWinner!, events);
}

/** Every card in play: hands + won piles + table + stock. */
export function totalCards(state: GameState): number {
  const inHands = state.players.reduce((s, p) => s + p.hand.length, 0);
  const inWon = state.players.reduce((s, p) => s + p.won.length, 0);
  const onTable = state.trick
    ? state.trick.sets.reduce((s, t) => s + t.cards.length, 0) +
      state.trick.discards.reduce((s, d) => s + d.cards.length, 0)
    : 0;
  return inHands + inWon + onTable + state.stock.length;
}

/**
 * Equal-hands invariant (user ruling) + card conservation. A violation is a
 * programmer error, never a legal game state.
 */
export function assertInvariants(state: GameState, expectedTotal: number = DECK_SIZE): void {
  if (state.phase === 'GAME_OVER') return;
  const sizes = state.players.map((p) => p.hand.length);
  // Mid-circle (TRICK_RESPOND) players who already acted hold k fewer cards; at
  // TRICK_LEAD and TRICK_LEADER_DECISION boundaries all hands must be equal.
  if (state.phase === 'TRICK_LEAD' || state.phase === 'TRICK_LEADER_DECISION') {
    if (!sizes.every((s) => s === sizes[0])) {
      throw new Error(`equal-hands invariant violated: ${sizes.join(',')} in ${state.phase}`);
    }
  }
  const total = totalCards(state);
  if (total !== expectedTotal) {
    throw new Error(`card conservation violated: ${total} != ${expectedTotal}`);
  }
}

export type { EngineOptions, GameState, TrickState, ThrowSet };
