import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  DECK_SIZE,
  RANKS,
  SHOHA,
  TOTAL_POINTS,
  cardName,
  cardOf,
  fullDeck,
  isShoha,
  pointsOf,
  rankOf,
  suitOf,
  sumPoints,
} from '@goat/shared';

test('deck has 36 unique cards totalling 120 points', () => {
  const deck = fullDeck();
  assert.equal(deck.length, DECK_SIZE);
  assert.equal(new Set(deck).size, DECK_SIZE);
  assert.equal(sumPoints(deck), TOTAL_POINTS);
});

test('rank order: 10 outranks K, Q, J; A is highest; 6 is lowest', () => {
  const order = RANKS.join(',');
  assert.equal(order, '6,7,8,9,J,Q,K,10,A');
  const ten = cardOf(0, 7);
  const king = cardOf(0, 6);
  assert.ok(rankOf(ten) > rankOf(king));
});

test('points: A=11 10=10 K=4 Q=3 J=2 rest=0', () => {
  assert.equal(pointsOf(cardOf(2, 8)), 11); // A♦
  assert.equal(pointsOf(cardOf(2, 7)), 10); // 10♦
  assert.equal(pointsOf(cardOf(2, 6)), 4); // K♦
  assert.equal(pointsOf(cardOf(2, 5)), 3); // Q♦
  assert.equal(pointsOf(cardOf(2, 4)), 2); // J♦
  assert.equal(pointsOf(cardOf(2, 3)), 0); // 9♦
});

test('shoha is the 6 of clubs', () => {
  assert.equal(suitOf(SHOHA), 1);
  assert.equal(rankOf(SHOHA), 0);
  assert.ok(isShoha(SHOHA));
  assert.equal(cardName(SHOHA), '6♣');
});
