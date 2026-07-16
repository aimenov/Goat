import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyGameOutcome, emptyFlags, emptyStats } from '../src/meta/achievements.js';

const outcome = (over: Partial<Parameters<typeof applyGameOutcome>[1]>) => ({
  isGoat: false,
  score: 10,
  scoreLimit: 24,
  instantRule: false,
  flags: emptyFlags(),
  ...over,
});

test('first win unlocks first_win; goat does not', () => {
  const stats = emptyStats();
  assert.deepEqual(applyGameOutcome(stats, outcome({ isGoat: true, score: 26 })), []);
  assert.deepEqual(applyGameOutcome(stats, outcome({})), ['first_win']);
  // second win: no re-unlock
  assert.deepEqual(applyGameOutcome(stats, outcome({})), []);
  assert.equal(stats.gamesPlayed, 3);
  assert.equal(stats.gamesWon, 2);
  assert.equal(stats.goats, 1);
});

test('streak_5 unlocks on the fifth consecutive win and resets on goat', () => {
  const stats = emptyStats();
  for (let i = 0; i < 4; i++) applyGameOutcome(stats, outcome({}));
  applyGameOutcome(stats, outcome({ isGoat: true, score: 24 }));
  assert.equal(stats.winStreak, 0);
  let fresh: string[] = [];
  for (let i = 0; i < 5; i++) fresh = applyGameOutcome(stats, outcome({}));
  assert.ok(fresh.includes('streak_5'));
});

test('situational achievements: shoha_ace, exact_limit, instant_goat, comeback', () => {
  const s1 = emptyStats();
  const flags = emptyFlags();
  flags.shohaKilledTrumpAce = true;
  flags.reconnected = true;
  assert.deepEqual(
    applyGameOutcome(s1, outcome({ flags })).sort(),
    ['comeback_win', 'first_win', 'shoha_ace'].sort(),
  );

  const s2 = emptyStats();
  assert.deepEqual(
    applyGameOutcome(s2, outcome({ isGoat: true, score: 24, instantRule: false })),
    ['exact_limit'],
  );

  const s3 = emptyStats();
  assert.deepEqual(
    applyGameOutcome(s3, outcome({ isGoat: true, score: 14, instantRule: true })),
    ['instant_goat'],
  );
});
