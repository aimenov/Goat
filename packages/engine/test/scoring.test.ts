import { test } from 'node:test';
import assert from 'node:assert/strict';
import { dealMultiplier, findGoats, penaltyBand } from '../src/scoring.js';

test('penalty bands: >60 → 0, 41–60 → 2, 1–40 → 4, 0 points → 6', () => {
  assert.equal(penaltyBand(120), 0);
  assert.equal(penaltyBand(61), 0);
  assert.equal(penaltyBand(60), 2);
  assert.equal(penaltyBand(41), 2);
  assert.equal(penaltyBand(40), 4);
  assert.equal(penaltyBand(1), 4);
  // 0 points → +6 even when the pile holds zero-point cards (user ruling)
  assert.equal(penaltyBand(0), 6);
});

test('multiplier: trump-6 → ×2; trump-6 + any equal pair (incl. 0–0) → ×3; else ×1', () => {
  assert.equal(dealMultiplier(false, [0, 0]), 1);
  assert.equal(dealMultiplier(true, [2, 4, 6]), 2);
  assert.equal(dealMultiplier(true, [0, 0]), 3);
  assert.equal(dealMultiplier(true, [4, 6, 4, 8]), 3);
  assert.equal(dealMultiplier(false, [4, 4]), 1);
});

test('no goats below both conditions', () => {
  assert.equal(findGoats([10, 8, 0], 24), null); // max<12
  assert.equal(findGoats([23, 2, 4], 24), null); // no zero, below limit
});

test('threshold: highest score only; exact top ties share', () => {
  assert.deepEqual(findGoats([24, 10, 2], 24), [0]);
  assert.deepEqual(findGoats([26, 30, 2], 24), [1]);
  assert.deepEqual(findGoats([26, 26, 2], 24), [0, 1]);
  assert.deepEqual(findGoats([36, 20], 36), [0]);
});

test('12-0 instant rule fires below the limit and picks the highest', () => {
  assert.deepEqual(findGoats([12, 0], 24), [0]);
  assert.deepEqual(findGoats([14, 0, 6], 24), [0]);
  assert.equal(findGoats([11, 0], 24), null);
  assert.equal(findGoats([12, 2], 24), null); // no one at 0
});

test('12-0 and threshold in the same deal: highest is the goat', () => {
  assert.deepEqual(findGoats([26, 12, 0], 24), [0]);
});
