import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SHOHA, cardOf, type Suit } from '@goat/shared';
import { beats, findPerfectMatching, hasPerfectMatching, isLegalLeadShape } from '../src/rules.js';

// Suits: 0=♠ 1=♣ 2=♦ 3=♥. Ranks: 0=6 1=7 2=8 3=9 4=J 5=Q 6=K 7=10 8=A.
const TRUMP: Suit = 3; // hearts

test('same suit, strictly higher rank beats', () => {
  assert.ok(beats(cardOf(0, 5), cardOf(0, 4), TRUMP, 'lead')); // Q♠ > J♠
  assert.ok(!beats(cardOf(0, 4), cardOf(0, 5), TRUMP, 'lead'));
  assert.ok(!beats(cardOf(0, 4), cardOf(0, 4), TRUMP, 'lead')); // equal never beats
});

test('ten beats king, queen, jack; ace beats ten', () => {
  assert.ok(beats(cardOf(0, 7), cardOf(0, 6), TRUMP, 'lead')); // 10♠ > K♠
  assert.ok(beats(cardOf(0, 8), cardOf(0, 7), TRUMP, 'lead')); // A♠ > 10♠
  assert.ok(!beats(cardOf(0, 6), cardOf(0, 7), TRUMP, 'lead')); // K♠ < 10♠
});

test('trump beats any non-trump; non-trump off-suit never beats', () => {
  assert.ok(beats(cardOf(TRUMP, 0), cardOf(0, 8), TRUMP, 'lead')); // 6♥ beats A♠
  assert.ok(!beats(cardOf(2, 8), cardOf(0, 0), TRUMP, 'lead')); // A♦ can't beat 6♠
});

test('trump-on-trump requires higher rank', () => {
  assert.ok(beats(cardOf(TRUMP, 7), cardOf(TRUMP, 6), TRUMP, 'lead'));
  assert.ok(!beats(cardOf(TRUMP, 6), cardOf(TRUMP, 7), TRUMP, 'lead'));
});

test('shoha beats anything as a beating card, incl. trump ace', () => {
  assert.ok(beats(SHOHA, cardOf(TRUMP, 8), TRUMP, 'lead'));
  assert.ok(beats(SHOHA, cardOf(TRUMP, 8), TRUMP, 'beat'));
});

test('shoha in a BEAT set is unbeatable; led, it is an ordinary 6♣', () => {
  const trumpAce = cardOf(TRUMP, 8);
  assert.ok(!beats(trumpAce, SHOHA, TRUMP, 'beat'));
  // led as ordinary: 7♣ beats it, trump beats it
  assert.ok(beats(cardOf(1, 1), SHOHA, TRUMP, 'lead'));
  assert.ok(beats(cardOf(TRUMP, 0), SHOHA, TRUMP, 'lead'));
  // clubs as trump: led shoha is just the lowest trump
  assert.ok(beats(cardOf(1, 1), SHOHA, 1, 'lead'));
});

test('lead shape: same rank OR same suit', () => {
  assert.ok(isLegalLeadShape([cardOf(0, 3)]));
  assert.ok(isLegalLeadShape([cardOf(0, 3), cardOf(1, 3), cardOf(2, 3)])); // three 9s
  assert.ok(isLegalLeadShape([cardOf(0, 0), cardOf(0, 5), cardOf(0, 8)])); // spades
  assert.ok(!isLegalLeadShape([cardOf(0, 0), cardOf(1, 5)]));
  assert.ok(!isLegalLeadShape([]));
});

test('per-target candidates may exist while NO perfect matching exists', () => {
  // Both targets are only beatable by the same single card.
  const onlyCard = cardOf(TRUMP, 8);
  const matrix = { [cardOf(0, 0)]: [onlyCard], [cardOf(0, 1)]: [onlyCard] };
  assert.equal(hasPerfectMatching(matrix), false);
});

test('perfect matching found when a valid assignment requires swapping', () => {
  const a = cardOf(0, 5);
  const b = cardOf(0, 6);
  // t1 can be beaten by a or b; t2 only by b → t1 must take a.
  const t1 = cardOf(0, 3);
  const t2 = cardOf(0, 4);
  const pairs = findPerfectMatching({ [t1]: [b, a], [t2]: [b] });
  assert.ok(pairs);
  const byTarget = new Map(pairs.map((p) => [p.target, p.card]));
  assert.equal(byTarget.get(t1), a);
  assert.equal(byTarget.get(t2), b);
});
