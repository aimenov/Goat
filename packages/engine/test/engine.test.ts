import { test } from 'node:test';
import assert from 'node:assert/strict';
import { HAND_SIZE, SHOHA, cardOf, suitOf, type CardId, type Suit } from '@goat/shared';
import { initGame, reduce } from '../src/reduce.js';
import { legalActions } from '../src/legal.js';
import { redact, redactEvent } from '../src/redact.js';
import { defaultAction } from '../src/autoplay.js';
import type { EngineEvent, GameState } from '../src/types.js';

// Suits: 0=♠ 1=♣ 2=♦ 3=♥. Ranks: 0=6 1=7 2=8 3=9 4=J 5=Q 6=K 7=10 8=A.

/** Hand-crafted state for scenario tests (bypasses dealing). */
function makeState(partial: {
  playerCount: number;
  hands: CardId[][];
  trumpSuit: Suit;
  leader?: number;
  stock?: CardId[];
  scores?: number[];
  multiplier?: 1 | 2 | 3;
}): GameState {
  const leader = partial.leader ?? 0;
  return {
    options: { playerCount: partial.playerCount, scoreLimit: 24, seed: 1 },
    rng: [1, 2, 3, 4],
    phase: 'TRICK_LEAD',
    dealIndex: 0,
    players: partial.hands.map((hand, i) => ({
      hand: [...hand],
      won: [],
      score: partial.scores?.[i] ?? 0,
    })),
    stock: partial.stock ?? [],
    trumpSuit: partial.trumpSuit,
    trumpCard: null,
    initialTrumpRank: 3, // a 9 — no multiplier by default
    multiplier: partial.multiplier ?? 1,
    trick: { leader, k: 0, turn: leader, sets: [], discards: [] },
    lastTrickWinner: null,
    goats: null,
  };
}

function apply(state: GameState, action: Parameters<typeof reduce>[1]): { state: GameState; events: EngineEvent[] } {
  const r = reduce(state, action);
  assert.ok(r.ok, `action rejected: ${(r as { error?: string }).error} ${JSON.stringify(action)}`);
  return r;
}

/* ------------------------------------------------------------------ *
 * Deal setup                                                          *
 * ------------------------------------------------------------------ */

test('initGame (4p): 6 cards each, trump revealed, trump card at stock bottom', () => {
  const { state, events } = initGame({ playerCount: 4, scoreLimit: 24, seed: 42 });
  assert.ok(state.players.every((p) => p.hand.length === HAND_SIZE));
  assert.equal(state.stock.length, 36 - 24);
  const reveal = events.find((e) => e.type === 'trumpRevealed');
  assert.ok(reveal && reveal.type === 'trumpRevealed');
  assert.equal(reveal.source, 'initial');
  // the revealed trump card is drawn last
  assert.equal(state.stock[state.stock.length - 1], reveal.card);
  assert.equal(state.trumpSuit, suitOf(reveal.card));
  assert.equal(state.phase, 'TRICK_LEAD');
});

test('initGame (6p): no stock, last-dealt card is the fixed trump', () => {
  const { state, events } = initGame({ playerCount: 6, scoreLimit: 24, seed: 7 });
  assert.equal(state.stock.length, 0);
  assert.ok(state.players.every((p) => p.hand.length === HAND_SIZE));
  const reveal = events.find((e) => e.type === 'trumpRevealed');
  assert.ok(reveal && reveal.type === 'trumpRevealed');
  assert.equal(reveal.source, 'lastDealt');
  assert.notEqual(reveal.toSeat, undefined);
  // the trump card stays in its recipient's hand
  assert.ok(state.players[reveal.toSeat!]!.hand.includes(reveal.card));
});

/* ------------------------------------------------------------------ *
 * Full-circle trick flow                                              *
 * ------------------------------------------------------------------ */

test('3p: discard does not end the trick; leader END gives cards to last beater', () => {
  const lead = cardOf(0, 3); // 9♠
  const beatCard = cardOf(0, 7); // 10♠
  const s0 = makeState({
    playerCount: 3,
    trumpSuit: 3,
    hands: [
      [lead, cardOf(2, 0)],
      [beatCard, cardOf(2, 1)],
      [cardOf(1, 2), cardOf(2, 2)],
    ],
  });

  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  assert.equal(r.state.phase, 'TRICK_RESPOND');
  assert.equal(r.state.trick!.turn, 1);

  // seat 1 beats
  r = apply(r.state, { type: 'BEAT', seat: 1, pairs: [{ target: lead, card: beatCard }] });
  assert.equal(r.state.phase, 'TRICK_RESPOND');
  assert.equal(r.state.trick!.turn, 2);

  // seat 2 discards — trick does NOT end; turn returns to the leader
  r = apply(r.state, { type: 'DISCARD', seat: 2, cards: [cardOf(1, 2)] });
  assert.equal(r.state.phase, 'TRICK_LEADER_DECISION');
  assert.equal(r.state.trick!.turn, 0);

  // leader ends: seat 1 (last beater) takes lead + beat + face-down discard
  r = apply(r.state, { type: 'END_TRICK', seat: 0 });
  const trickEnd = r.events.find((e) => e.type === 'trickEnded');
  assert.ok(trickEnd && trickEnd.type === 'trickEnded');
  assert.equal(trickEnd.winner, 1);
  assert.deepEqual([...r.state.players[1]!.won].sort((a, b) => a - b), [lead, beatCard, cardOf(1, 2)].sort((a, b) => a - b));
  // winner leads the next trick
  assert.equal(r.state.trick!.leader, 1);
  assert.equal(r.state.phase, 'TRICK_LEAD');
});

test('nobody beats: trick auto-resolves to the leader — no self-beat, no decision phase', () => {
  const lead = cardOf(3, 8); // trump A♥
  const s0 = makeState({
    playerCount: 3,
    trumpSuit: 3,
    hands: [
      [lead, cardOf(2, 0)],
      [cardOf(0, 0), cardOf(2, 1)],
      [cardOf(0, 1), cardOf(2, 2)],
    ],
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  r = apply(r.state, { type: 'DISCARD', seat: 1, cards: [cardOf(0, 0)] });
  // the last discard closes the circle: the newest set is the leader's own,
  // so the trick resolves immediately (a player can never beat his own cards)
  r = apply(r.state, { type: 'DISCARD', seat: 2, cards: [cardOf(0, 1)] });
  const trickEnd = r.events.find((e) => e.type === 'trickEnded');
  assert.ok(trickEnd && trickEnd.type === 'trickEnded');
  assert.equal(trickEnd.winner, 0);
  assert.equal(r.state.players[0]!.won.length, 3);
  assert.equal(r.state.phase, 'TRICK_LEAD');
  assert.equal(r.state.trick!.leader, 0);
});

test('leader may beat the newest set, starting another circle', () => {
  const lead = cardOf(0, 0); // 6♠
  const beat1 = cardOf(0, 4); // J♠
  const beat2 = cardOf(0, 8); // A♠ (leader's second-circle beat)
  const s0 = makeState({
    playerCount: 2,
    trumpSuit: 3,
    hands: [
      [lead, beat2],
      [beat1, cardOf(2, 1)],
    ],
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  r = apply(r.state, { type: 'BEAT', seat: 1, pairs: [{ target: lead, card: beat1 }] });
  assert.equal(r.state.phase, 'TRICK_LEADER_DECISION');

  // leader beats the J♠ with A♠ → new circle, seat 1 to move again
  r = apply(r.state, { type: 'BEAT', seat: 0, pairs: [{ target: beat1, card: beat2 }] });
  assert.equal(r.state.phase, 'TRICK_RESPOND');
  assert.equal(r.state.trick!.turn, 1);

  // seat 1 discards; the circle returns to the leader whose OWN set is
  // newest → auto-resolve (no self-beat), leader takes all
  r = apply(r.state, { type: 'DISCARD', seat: 1, cards: [cardOf(2, 1)] });
  const trickEnd = r.events.find((e) => e.type === 'trickEnded');
  assert.ok(trickEnd && trickEnd.type === 'trickEnded');
  assert.equal(trickEnd.winner, 0);
  // 3 face-up (lead + two beats) + 1 face-down discard, all to the leader
  assert.equal(trickEnd.faceUp.length + trickEnd.faceDown.length, 4);
  // hands emptied → the deal scored: leader took A♠(11)+J♠(2)+6♠(0)+7♦(0) = 13 pts
  const dealEnd = r.events.find((e) => e.type === 'dealEnded');
  assert.ok(dealEnd && dealEnd.type === 'dealEnded');
  assert.equal(dealEnd.results[0]!.cardPoints, 13);
  assert.equal(dealEnd.results[1]!.cardPoints, 0);
});

test('multi-card lead: responder covers all k with chosen pairing or discards exactly k', () => {
  const nine1 = cardOf(0, 3);
  const nine2 = cardOf(2, 3);
  const s0 = makeState({
    playerCount: 2,
    trumpSuit: 3,
    hands: [
      [nine1, nine2, cardOf(1, 1)],
      [cardOf(0, 7), cardOf(2, 5), cardOf(1, 2)],
    ],
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [nine1, nine2] });
  assert.equal(r.state.trick!.k, 2);

  // wrong count rejected
  const bad = reduce(r.state, { type: 'DISCARD', seat: 1, cards: [cardOf(1, 2)] });
  assert.ok(!bad.ok && bad.error === 'WRONG_CARD_COUNT');

  // responder chooses the pairing: 10♠ covers 9♠, Q♦ covers 9♦
  r = apply(r.state, {
    type: 'BEAT',
    seat: 1,
    pairs: [
      { target: nine1, card: cardOf(0, 7) },
      { target: nine2, card: cardOf(2, 5) },
    ],
  });
  assert.equal(r.state.phase, 'TRICK_LEADER_DECISION');
});

test('shoha led as ordinary card can be beaten; shoha in a beat set blocks further beating', () => {
  const trumpAce = cardOf(3, 8);
  const s0 = makeState({
    playerCount: 3,
    trumpSuit: 3,
    hands: [
      [trumpAce, cardOf(2, 0)],
      [SHOHA, cardOf(2, 1)],
      [cardOf(3, 7), cardOf(2, 2)], // 10♥ — a big trump, still can't beat shoha
    ],
  });
  // leader leads the TRUMP ACE; seat 1 kills it with the shoha
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [trumpAce] });
  r = apply(r.state, { type: 'BEAT', seat: 1, pairs: [{ target: trumpAce, card: SHOHA }] });

  // seat 2's legal actions: cannot beat the shoha with anything
  const legal = legalActions(r.state, 2);
  assert.ok(legal && legal.kind === 'respond');
  assert.equal(legal.canBeat, false);
  assert.deepEqual(legal.beatMatrix[SHOHA], []);

  r = apply(r.state, { type: 'DISCARD', seat: 2, cards: [cardOf(2, 2)] });
  // leader also cannot beat → only END; shoha owner takes the trump ace
  const leaderLegal = legalActions(r.state, 0);
  assert.ok(leaderLegal && leaderLegal.kind === 'leaderDecision');
  assert.equal(leaderLegal.canBeat, false);
  r = apply(r.state, { type: 'END_TRICK', seat: 0 });
  const trickEnd = r.events.find((e) => e.type === 'trickEnded');
  assert.ok(trickEnd && trickEnd.type === 'trickEnded');
  assert.equal(trickEnd.winner, 1);
});

/* ------------------------------------------------------------------ *
 * Validation                                                          *
 * ------------------------------------------------------------------ */

test('illegal actions are rejected with typed errors', () => {
  const lead = cardOf(0, 3);
  const s0 = makeState({
    playerCount: 2,
    trumpSuit: 3,
    hands: [
      [lead, cardOf(2, 0)],
      [cardOf(0, 1), cardOf(2, 1)],
    ],
  });

  let r = reduce(s0, { type: 'LEAD', seat: 1, cards: [cardOf(0, 1)] });
  assert.ok(!r.ok && r.error === 'NOT_YOUR_TURN');

  r = reduce(s0, { type: 'LEAD', seat: 0, cards: [lead, cardOf(2, 0)] });
  assert.ok(!r.ok && r.error === 'ILLEGAL_LEAD_SHAPE'); // 9♠ + 6♦: neither same rank nor suit

  r = reduce(s0, { type: 'LEAD', seat: 0, cards: [cardOf(1, 8)] });
  assert.ok(!r.ok && r.error === 'CARD_NOT_IN_HAND');

  r = reduce(s0, { type: 'END_TRICK', seat: 0 });
  assert.ok(!r.ok && r.error === 'WRONG_PHASE');

  const led = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  // 7♠ (rank 1) does not beat 9♠ (rank 3)
  r = reduce(led.state, { type: 'BEAT', seat: 1, pairs: [{ target: lead, card: cardOf(0, 1) }] });
  assert.ok(!r.ok && r.error === 'ILLEGAL_BEAT');
  // leader cannot DISCARD in leader decision
  const resp = apply(led.state, { type: 'DISCARD', seat: 1, cards: [cardOf(0, 1)] });
  r = reduce(resp.state, { type: 'DISCARD', seat: 0, cards: [cardOf(2, 0)] });
  assert.ok(!r.ok && r.error === 'WRONG_PHASE');
});

/* ------------------------------------------------------------------ *
 * Replenishment & trump rotation                                      *
 * ------------------------------------------------------------------ */

test('replenish: winner draws first; last drawn card rotates trump', () => {
  const lead = cardOf(0, 3);
  const beat = cardOf(0, 7);
  const stock = [cardOf(2, 4), cardOf(3, 0), cardOf(1, 3), cardOf(2, 8)]; // J♦ 6♥ 9♣ A♦
  const s0 = makeState({
    playerCount: 2,
    trumpSuit: 0,
    hands: [
      [lead, cardOf(2, 0)],
      [beat, cardOf(2, 1)],
    ],
    stock,
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  r = apply(r.state, { type: 'BEAT', seat: 1, pairs: [{ target: lead, card: beat }] });
  r = apply(r.state, { type: 'END_TRICK', seat: 0 });

  // winner is seat 1 → draws first: J♦ to 1, 6♥ to 0, 9♣ to 1... hands were 1 each,
  // need 5 each but stock has 4: draw order 1,0,1,0 → both at 3 cards, stock empty.
  const draws = r.events.filter((e) => e.type === 'cardDrawn');
  assert.deepEqual(
    draws.map((d) => (d.type === 'cardDrawn' ? [d.seat, d.card] : null)),
    [
      [1, cardOf(2, 4)],
      [0, cardOf(3, 0)],
      [1, cardOf(1, 3)],
      [0, cardOf(2, 8)],
    ],
  );
  assert.equal(r.state.players[0]!.hand.length, r.state.players[1]!.hand.length);

  // last drawn card was A♦ → diamonds become trump
  const rotation = r.events.find((e) => e.type === 'trumpRevealed');
  assert.ok(rotation && rotation.type === 'trumpRevealed');
  assert.equal(rotation.source, 'rotation');
  assert.equal(r.state.trumpSuit, 2);
  assert.equal(r.state.trumpCard, cardOf(2, 8));
});

/* ------------------------------------------------------------------ *
 * Deal scoring & game end                                             *
 * ------------------------------------------------------------------ */

test('final trick scores the deal; penalties apply with multiplier', () => {
  const lead = cardOf(0, 8); // A♠ = 11 pts
  const beat = cardOf(3, 8); // A♥ trump = 11 pts
  const s0 = makeState({
    playerCount: 2,
    trumpSuit: 3,
    hands: [[lead], [beat]],
    multiplier: 2,
    scores: [10, 4],
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  r = apply(r.state, { type: 'BEAT', seat: 1, pairs: [{ target: lead, card: beat }] });
  r = apply(r.state, { type: 'END_TRICK', seat: 0 });

  const dealEnd = r.events.find((e) => e.type === 'dealEnded');
  assert.ok(dealEnd && dealEnd.type === 'dealEnded');
  // seat 1 took 22 pts → band +4 ×2 = 8; seat 0 took 0 pts → +6 ×2 = 12
  assert.equal(dealEnd.results[0]!.penalty, 12);
  assert.equal(dealEnd.results[1]!.penalty, 8);
  assert.equal(dealEnd.results[0]!.score, 22);
  assert.equal(dealEnd.results[1]!.score, 12);
  // 22 ≥ 12 but nobody is at 0 → threshold 24 not reached either → next deal starts
  assert.notEqual(r.state.phase, 'GAME_OVER');
  const nextDeal = r.events.find((e) => e.type === 'dealStarted');
  assert.ok(nextDeal && nextDeal.type === 'dealStarted');
  // winner of the last trick (seat 1) leads the new deal — no dealer rotation
  assert.equal(nextDeal.leader, 1);
});

test('threshold goat: reaching the limit ends the game, highest score loses', () => {
  const lead = cardOf(0, 8);
  const beat = cardOf(3, 8);
  const s0 = makeState({
    playerCount: 2,
    trumpSuit: 3,
    hands: [[lead], [beat]],
    multiplier: 3,
    scores: [6, 4],
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: [lead] });
  r = apply(r.state, { type: 'BEAT', seat: 1, pairs: [{ target: lead, card: beat }] });
  r = apply(r.state, { type: 'END_TRICK', seat: 0 });
  // seat 0: 0 pts → +6 ×3 = +18 → 24 = limit; seat 1: 22 pts → +4 ×3 → 16.
  const gameEnd = r.events.find((e) => e.type === 'gameEnded');
  assert.ok(gameEnd && gameEnd.type === 'gameEnded');
  assert.deepEqual(gameEnd.goats, [0]);
  assert.equal(r.state.phase, 'GAME_OVER');
});

test('12-0 instant rule: 12+ while the big winner stays at 0 ends the game early', () => {
  // seat 0 leads 6 spades (30 pts); seat 1 dumps 50 pts of face-down discards;
  // seat 2 beats everything with 6 trumps (30 pts) and takes 110 pts → +0, stays at 0.
  const spades = [cardOf(0, 3), cardOf(0, 4), cardOf(0, 5), cardOf(0, 6), cardOf(0, 7), cardOf(0, 8)];
  const dumps = [cardOf(2, 8), cardOf(2, 7), cardOf(1, 8), cardOf(1, 7), cardOf(2, 6), cardOf(1, 6)];
  const hearts = [cardOf(3, 3), cardOf(3, 4), cardOf(3, 5), cardOf(3, 6), cardOf(3, 7), cardOf(3, 8)];
  const s0 = makeState({
    playerCount: 3,
    trumpSuit: 3,
    hands: [spades, dumps, hearts],
    scores: [6, 2, 0],
  });
  let r = apply(s0, { type: 'LEAD', seat: 0, cards: spades });
  r = apply(r.state, { type: 'DISCARD', seat: 1, cards: dumps });
  r = apply(r.state, {
    type: 'BEAT',
    seat: 2,
    pairs: spades.map((target, i) => ({ target, card: hearts[i]! })),
  });
  r = apply(r.state, { type: 'END_TRICK', seat: 0 });

  // scores: seat 0 → 6+6=12, seat 1 → 2+6=8, seat 2 → 0+0=0 → instant rule fires.
  const gameEnd = r.events.find((e) => e.type === 'gameEnded');
  assert.ok(gameEnd && gameEnd.type === 'gameEnded');
  assert.deepEqual(gameEnd.scores, [12, 8, 0]);
  assert.deepEqual(gameEnd.goats, [0]);
  assert.equal(r.state.phase, 'GAME_OVER');
});

/* ------------------------------------------------------------------ *
 * Redaction                                                           *
 * ------------------------------------------------------------------ */

test('redact hides other hands, stock, discard contents and foreign won piles', () => {
  const { state } = initGame({ playerCount: 4, scoreLimit: 24, seed: 5 });
  const view = redact(state, 2);
  assert.equal(view.seat, 2);
  assert.deepEqual(view.myHand, state.players[2]!.hand);
  assert.ok(view.seats.every((s) => s.handCount === HAND_SIZE));
  assert.equal((view as unknown as Record<string, unknown>)['stock'], undefined);
  assert.equal(view.stockCount, state.stock.length);
  // legal actions only for the seat to move
  assert.equal(view.legal !== null, state.trick!.turn === 2);
});

test('redactEvent masks private card identities for other viewers', () => {
  const dealt: EngineEvent = { type: 'cardsDealt', hands: [[1, 2], [3, 4]] };
  const forSeat0 = redactEvent(dealt, 0) as { hands: number[][] };
  assert.deepEqual(forSeat0.hands[0], [1, 2]);
  assert.deepEqual(forSeat0.hands[1], [-1, -1]);

  const discarded: EngineEvent = { type: 'discarded', seat: 1, cards: [5, 6] };
  assert.deepEqual((redactEvent(discarded, 0) as { cards: number[] }).cards, [-1, -1]);
  assert.deepEqual((redactEvent(discarded, 1) as { cards: number[] }).cards, [5, 6]);

  const ended: EngineEvent = { type: 'trickEnded', winner: 1, faceUp: [7], faceDown: [8, 9] };
  assert.deepEqual((redactEvent(ended, 0) as { faceDown: number[] }).faceDown, [-1, -1]);
  assert.deepEqual((redactEvent(ended, 1) as { faceDown: number[] }).faceDown, [8, 9]);

  const drawn: EngineEvent = { type: 'cardDrawn', seat: 1, card: 10, stockCount: 3 };
  assert.equal((redactEvent(drawn, 0) as { card: number }).card, -1);
  assert.equal((redactEvent(drawn, 1) as { card: number }).card, 10);
});

/* ------------------------------------------------------------------ *
 * Autopilot                                                           *
 * ------------------------------------------------------------------ */

test('a full game played by the autopilot alone always terminates legally', () => {
  for (const playerCount of [2, 3, 4, 6]) {
    let { state } = initGame({ playerCount, scoreLimit: 24, seed: 99 + playerCount });
    let guard = 100_000;
    while (state.phase !== 'GAME_OVER' && guard-- > 0) {
      const r = reduce(state, defaultAction(state));
      assert.ok(r.ok, `autopilot produced illegal action (${playerCount}p)`);
      state = r.state;
    }
    assert.equal(state.phase, 'GAME_OVER', `${playerCount}p game did not terminate`);
  }
});
