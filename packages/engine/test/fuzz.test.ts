import { test } from 'node:test';
import assert from 'node:assert/strict';
import { playRandomGame, replay } from '../src/simulate.js';

test('fuzz: 60 random games across all player counts hold every invariant', () => {
  for (let seed = 1; seed <= 60; seed++) {
    const playerCount = [2, 3, 4, 6][seed % 4]!;
    const scoreLimit = seed % 2 ? 24 : 36;
    const stats = playRandomGame(seed, playerCount, scoreLimit);
    assert.ok(stats.goats.length >= 1);
    assert.ok(stats.deals >= 1);
  }
});

test('determinism: replaying the action log reproduces the exact final state', () => {
  const stats = playRandomGame(12345, 4, 24);
  const replayed = replay(12345, 4, 24, stats.actionLog);
  assert.deepEqual(replayed, stats.finalState);
});
