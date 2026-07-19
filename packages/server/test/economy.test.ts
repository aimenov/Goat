/**
 * Unit coverage for the pure economy math (packages/server/src/meta/economy.ts).
 * All time-dependent functions take `now` explicitly, so every case runs at a
 * fixed instant.
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { QUESTS, type QuestId } from '@goat/shared';
import { type PlayerStats, type QuestState, emptyFlags, emptyStats } from '../src/meta/achievements.js';
import { nextDaily } from '../src/meta/economy.js';
import {
  applyGameToQuests,
  claimDaily,
  coinReward,
  ensureQuestState,
  isYesterday,
  rankFor,
  ratingDeltas,
  rolloverWeek,
  selectDailyQuests,
  tryConsumeRewardedAd,
  utcDateKey,
  utcWeekKey,
} from '../src/meta/economy.js';

const T = Date.UTC(2026, 6, 15, 12); // Wed 2026-07-15 12:00 UTC
const DAY = 86_400_000;
const TTL = 900_000;

const winnerFact = (over: Partial<Parameters<typeof coinReward>[0]> = {}) => ({
  isGoat: false,
  score: 10,
  maxScore: 24,
  scoreLimit: 24,
  playerCount: 2,
  flags: emptyFlags(),
  winStreak: 1,
  ...over,
});

// ------------------------------------------------------------------ coins

test('coinReward: winner = base + margin + flags + streak', () => {
  // base 20 (2p), margin round(10*14/24)=6, streak 5*1
  assert.deepEqual(coinReward(winnerFact()), { base: 20, margin: 6, flagBonus: 0, streakBonus: 5, questBonus: 0, total: 31 });
  // 4 players: base 30
  assert.equal(coinReward(winnerFact({ playerCount: 4 })).base, 30);
  // margin clamps at 10
  assert.equal(coinReward(winnerFact({ score: 0, maxScore: 240 })).margin, 10);
  // flags: triple +15, 120 pts +20, shoha-ace +10
  const flags = emptyFlags();
  flags.wonTripleDeal = true;
  flags.took120InADeal = true;
  flags.shohaKilledTrumpAce = true;
  assert.equal(coinReward(winnerFact({ flags })).flagBonus, 45);
  // streak bonus caps at 5 wins
  assert.equal(coinReward(winnerFact({ winStreak: 9 })).streakBonus, 25);
});

test('coinReward: goat gets the flat consolation 5', () => {
  const flags = emptyFlags();
  flags.took120InADeal = true; // goat gets no bonuses whatsoever
  assert.deepEqual(coinReward(winnerFact({ isGoat: true, score: 26, flags })), {
    base: 5,
    margin: 0,
    flagBonus: 0,
    streakBonus: 0,
    questBonus: 0,
    total: 5,
  });
});

// ------------------------------------------------------------------ rating

test('ratingDeltas: 2p equal ratings, new players → ±20 (K=40)', () => {
  assert.deepEqual(ratingDeltas([1000, 1000], [0, 0], [1]), [20, -20]);
});

test('ratingDeltas: K drops to 24 after 10 games', () => {
  assert.deepEqual(ratingDeltas([1000, 1000], [10, 10], [1]), [12, -12]);
});

test('ratingDeltas: favorite winning gains less', () => {
  const [w, g] = ratingDeltas([1200, 1000], [0, 0], [1]);
  assert.equal(w, 10); // 40 * (1 - 0.76) ≈ 9.6
  assert.equal(g, -10);
});

test('ratingDeltas: multi-goat and single-goat 4p tables', () => {
  // one goat: each winner beats it once, sums ÷ 3
  assert.deepEqual(ratingDeltas([1000, 1000, 1000, 1000], [0, 0, 0, 0], [3]), [7, 7, 7, -20]);
  // two goats: two pairwise matches per seat
  assert.deepEqual(ratingDeltas([1000, 1000, 1000, 1000], [0, 0, 0, 0], [2, 3]), [13, 13, -13, -13]);
});

test('ratingDeltas: zero goats or all goats → zero deltas; caller floors at 100', () => {
  assert.deepEqual(ratingDeltas([1000, 1000], [0, 0], []), [0, 0]);
  assert.deepEqual(ratingDeltas([1000, 1000], [0, 0], [0, 1]), [0, 0]);
  // the award path floors: Math.max(100, rating + delta)
  const [, goatDelta] = ratingDeltas([1000, 1000], [0, 0], [1]);
  assert.equal(Math.max(100, 105 + goatDelta!), 100);
});

// ------------------------------------------------------------------ ranks

test('rankFor: exact band boundaries', () => {
  const at = (rating: number) => rankFor(rating).id;
  assert.equal(at(100), 'kid');
  assert.equal(at(899), 'kid');
  assert.equal(at(900), 'young');
  assert.equal(at(999), 'young');
  assert.equal(at(1000), 'common');
  assert.equal(at(1099), 'common');
  assert.equal(at(1100), 'scapegoat');
  assert.equal(at(1249), 'scapegoat');
  assert.equal(at(1250), 'trump');
  assert.equal(at(1399), 'trump');
  assert.equal(at(1400), 'aristocrat');
  assert.equal(at(1549), 'aristocrat');
  assert.equal(at(1550), 'professor');
  assert.equal(at(1749), 'professor');
  assert.equal(at(1750), 'seasoned');
  assert.equal(at(9999), 'seasoned');
});

// ------------------------------------------------------------------ daily

test('claimDaily: first claim, streak growth, idempotence per day', () => {
  const stats = emptyStats();
  const first = claimDaily(stats, T, TTL);
  assert.deepEqual(first, { amount: 10, streak: 1 });
  assert.equal(stats.coins, 10);
  assert.deepEqual(stats.pendingDouble, { kind: 'daily', amount: 10, expiresAt: T + TTL });
  // same UTC day again → null, nothing changes
  assert.equal(claimDaily(stats, T + 3_600_000, TTL), null);
  assert.equal(stats.coins, 10);
  // next day → streak 2, amount 15
  assert.deepEqual(claimDaily(stats, T + DAY, TTL), { amount: 15, streak: 2 });
});

test('claimDaily: missed day resets the streak; day 8+ keeps the 50 cap', () => {
  const stats = emptyStats();
  claimDaily(stats, T, TTL);
  claimDaily(stats, T + DAY, TTL);
  // skip a day → back to streak 1 / amount 10
  assert.deepEqual(claimDaily(stats, T + 3 * DAY, TTL), { amount: 10, streak: 1 });
  // 8 consecutive days: day 7 and day 8 both pay 50
  const s2 = emptyStats();
  let last: { amount: number; streak: number } | null = null;
  for (let day = 0; day < 8; day++) last = claimDaily(s2, T + day * DAY, TTL);
  assert.deepEqual(last, { amount: 50, streak: 8 });
});

// ------------------------------------------------------------------ quests

test('selectDailyQuests: deterministic, 3 distinct valid ids', () => {
  const a = selectDailyQuests('player-abc', '2026-07-15');
  assert.deepEqual(a, selectDailyQuests('player-abc', '2026-07-15'));
  assert.equal(a.length, 3);
  assert.equal(new Set(a).size, 3);
  for (const id of a) assert.ok(id in QUESTS, `unknown quest ${id}`);
  // seed covers playerId AND date
  assert.deepEqual(selectDailyQuests('player-abc', '2026-07-15'), a);
  const otherDay = selectDailyQuests('player-abc', '2026-07-16');
  const otherPlayer = selectDailyQuests('player-xyz', '2026-07-15');
  assert.equal(otherDay.length, 3);
  assert.equal(otherPlayer.length, 3);
});

test('ensureQuestState: creates once per day, rolls over at midnight UTC', () => {
  const stats = emptyStats();
  assert.equal(ensureQuestState(stats, 'p1', T), true);
  const state = stats.questState!;
  assert.equal(state.date, utcDateKey(T));
  assert.equal(state.quests.length, 3);
  assert.equal(ensureQuestState(stats, 'p1', T + 3_600_000), false);
  assert.equal(stats.questState, state); // untouched
  assert.equal(ensureQuestState(stats, 'p1', T + DAY), true);
  assert.notEqual(stats.questState!.date, state.date);
});

test('applyGameToQuests: progress, auto-credit once, no double-credit', () => {
  const state: QuestState = {
    date: '2026-07-15',
    quests: (['win_1', 'play_3', 'take_120'] as QuestId[]).map((id) => ({ id, progress: 0, completed: false })),
  };
  const flags = emptyFlags();
  flags.took120InADeal = true;
  const fact = { isGoat: false, score: 0, playerCount: 2, winStreak: 1, flags };

  const first = applyGameToQuests(state, fact);
  assert.equal(first.questBonus, QUESTS.win_1.reward + QUESTS.take_120.reward); // 20 + 50
  assert.deepEqual(
    first.lines.map((l) => l.ru),
    [`Задание дня: ${QUESTS.win_1.ru}`, `Задание дня: ${QUESTS.take_120.ru}`],
  );
  assert.equal(state.quests[1]!.progress, 1); // play_3 ticks 1/3

  // completed quests never re-credit; play_3 keeps counting
  const second = applyGameToQuests(state, fact);
  assert.equal(second.questBonus, 0);
  assert.equal(state.quests[1]!.progress, 2);
  const third = applyGameToQuests(state, fact);
  assert.equal(third.questBonus, QUESTS.play_3.reward);
  assert.equal(state.quests[1]!.completed, true);
});

test('applyGameToQuests: streak quests track the running streak', () => {
  const state: QuestState = {
    date: '2026-07-15',
    quests: (['streak_2', 'no_goat_3'] as QuestId[]).map((id) => ({ id, progress: 0, completed: false })),
  };
  const fact = (winStreak: number) => ({ isGoat: winStreak === 0, score: 10, playerCount: 2, winStreak, flags: emptyFlags() });
  applyGameToQuests(state, fact(1));
  assert.equal(state.quests[0]!.progress, 1);
  const credited = applyGameToQuests(state, fact(2));
  assert.equal(credited.questBonus, QUESTS.streak_2.reward);
  // losing resets nothing already banked but adds no progress
  applyGameToQuests(state, fact(0));
  assert.equal(state.quests[1]!.progress, 2);
  assert.equal(state.quests[1]!.completed, false);
});

// ------------------------------------------------------------------ weeks

test('utcWeekKey: ISO Monday boundary and year edges', () => {
  // Sun 2024-01-07 23:59 UTC is still W01; Mon 2024-01-08 00:00 starts W02
  assert.equal(utcWeekKey(Date.UTC(2024, 0, 7, 23, 59)), '2024-W01');
  assert.equal(utcWeekKey(Date.UTC(2024, 0, 8, 0, 0)), '2024-W02');
  // ISO year edge: Mon 2025-12-29 already belongs to 2026-W01
  assert.equal(utcWeekKey(Date.UTC(2025, 11, 28)), '2025-W52');
  assert.equal(utcWeekKey(Date.UTC(2025, 11, 29)), '2026-W01');
});

test('rolloverWeek: resets weeklyCoins exactly on week change', () => {
  const stats = emptyStats();
  assert.equal(rolloverWeek(stats, T), true);
  stats.weeklyCoins = 77;
  assert.equal(rolloverWeek(stats, T + DAY), false); // Wed → Thu, same week
  assert.equal(stats.weeklyCoins, 77);
  assert.equal(rolloverWeek(stats, T + 7 * DAY), true);
  assert.equal(stats.weeklyCoins, 0);
});

test('utcDateKey / isYesterday', () => {
  assert.equal(utcDateKey(T), '2026-07-15');
  assert.equal(isYesterday('2026-07-14', T), true);
  assert.equal(isYesterday('2026-07-13', T), false);
  assert.equal(isYesterday('', T), false);
});

// ------------------------------------------------------------------ rewarded ads

const withPending = (kind: 'game' | 'daily', amount: number, expiresAt: number): PlayerStats => {
  const stats = emptyStats();
  stats.pendingDouble = { kind, amount, expiresAt };
  return stats;
};

test('tryConsumeRewardedAd: doubles once, then nothing to double', () => {
  const stats = withPending('game', 30, T + TTL);
  const first = tryConsumeRewardedAd(stats, 'doubleGame', T, { maxRewardedAdsPerDay: 5 });
  assert.deepEqual(first, { ok: true, granted: 30 });
  assert.equal(stats.coins, 30);
  assert.equal(stats.pendingDouble, null);
  assert.equal(stats.rewardedCount, 1);
  assert.deepEqual(tryConsumeRewardedAd(stats, 'doubleGame', T, { maxRewardedAdsPerDay: 5 }), {
    ok: false,
    error: 'NOTHING_TO_DOUBLE',
  });
});

test('tryConsumeRewardedAd: kind must match and TTL must hold', () => {
  const daily = withPending('daily', 10, T + TTL);
  assert.deepEqual(tryConsumeRewardedAd(daily, 'doubleGame', T, { maxRewardedAdsPerDay: 5 }), {
    ok: false,
    error: 'NOTHING_TO_DOUBLE',
  });
  assert.equal(tryConsumeRewardedAd(daily, 'doubleDaily', T, { maxRewardedAdsPerDay: 5 }).ok, true);

  const expired = withPending('game', 30, T - 1);
  assert.deepEqual(tryConsumeRewardedAd(expired, 'doubleGame', T, { maxRewardedAdsPerDay: 5 }), {
    ok: false,
    error: 'NOTHING_TO_DOUBLE',
  });
});

test('tryConsumeRewardedAd: daily cap, reset on UTC day rollover', () => {
  const stats = withPending('game', 30, T + TTL);
  stats.rewardedDate = utcDateKey(T);
  stats.rewardedCount = 5;
  assert.deepEqual(tryConsumeRewardedAd(stats, 'doubleGame', T, { maxRewardedAdsPerDay: 5 }), {
    ok: false,
    error: 'RATE_LIMITED',
  });
  // yesterday's count does not block today
  stats.rewardedDate = utcDateKey(T - DAY);
  stats.pendingDouble = { kind: 'game', amount: 30, expiresAt: T + TTL };
  assert.deepEqual(tryConsumeRewardedAd(stats, 'doubleGame', T, { maxRewardedAdsPerDay: 5 }), { ok: true, granted: 30 });
  assert.equal(stats.rewardedCount, 1);
});

test('nextDaily: previews continuation, reset after a lapse, and same-day claim', () => {
  const stats = emptyStats();
  // never claimed: day 1
  assert.deepEqual(nextDaily(stats, T), { streak: 1, amount: 10 });
  // claimed yesterday with streak 3: next claim continues to day 4
  stats.dailyStreak = 3;
  stats.lastClaimDate = utcDateKey(T - DAY);
  assert.deepEqual(nextDaily(stats, T), { streak: 4, amount: 25 });
  // lapsed (last claim 2 days ago): next claim resets to day 1
  stats.lastClaimDate = utcDateKey(T - 2 * DAY);
  assert.deepEqual(nextDaily(stats, T), { streak: 1, amount: 10 });
  // claimed today: tomorrow continues the streak
  stats.lastClaimDate = utcDateKey(T);
  assert.deepEqual(nextDaily(stats, T), { streak: 4, amount: 25 });
});
