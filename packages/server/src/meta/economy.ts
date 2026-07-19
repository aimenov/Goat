/**
 * Pure economy math: coin rewards, ELO deltas, daily bonus, quests, weekly
 * rollover, rewarded-ad doubling. Everything takes time as a `now` parameter —
 * no Date.now() in here — so all of it is unit-testable at fixed instants.
 */
import { createHash } from 'node:crypto';
import {
  DAILY_BONUS,
  QUESTS,
  RANKS,
  type CoinBreakdown,
  type QuestId,
  type QuestProgressView,
  type RankInfo,
  type RewardLine,
} from '@goat/shared';
import type { GameFlags, PendingDouble, PlayerStats, QuestState } from './achievements.js';

/* ------------------------------------------------------------------ time */

/** UTC day key, e.g. '2026-07-19'. */
export function utcDateKey(now: number): string {
  return new Date(now).toISOString().slice(0, 10);
}

/** ISO-8601 week key (weeks start Monday), e.g. '2026-W29'. */
export function utcWeekKey(now: number): string {
  const d = new Date(now);
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const isoDay = date.getUTCDay() || 7; // Mon=1 .. Sun=7
  date.setUTCDate(date.getUTCDate() + 4 - isoDay); // shift to this week's Thursday
  const yearStart = Date.UTC(date.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((date.getTime() - yearStart) / 86_400_000 + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

export function isYesterday(dateKey: string, now: number): boolean {
  return dateKey !== '' && dateKey === utcDateKey(now - 86_400_000);
}

/* ------------------------------------------------------------------ coins */

/** Everything the reward formula needs to know about one finished game. */
export interface GameFact {
  isGoat: boolean;
  score: number;
  /** Highest (worst) penalty score at the table — margin is distance from it. */
  maxScore: number;
  scoreLimit: number;
  playerCount: number;
  flags: GameFlags;
  /** Post-game win streak (applyGameOutcome must run first). */
  winStreak: number;
}

/**
 * 🥬 per game. Goat: flat consolation 5. Winner: table-size base + margin over
 * the goat + flashy-flag bonuses + capped streak bonus. questBonus is filled
 * in later by the quest auto-credit pass.
 */
export function coinReward(fact: GameFact): CoinBreakdown {
  if (fact.isGoat) {
    return { base: 5, margin: 0, flagBonus: 0, streakBonus: 0, questBonus: 0, total: 5 };
  }
  const base = 20 + 5 * (fact.playerCount - 2);
  const margin = Math.min(10, Math.max(0, Math.round((10 * (fact.maxScore - fact.score)) / fact.scoreLimit)));
  let flagBonus = 0;
  if (fact.flags.wonTripleDeal) flagBonus += 15;
  if (fact.flags.took120InADeal) flagBonus += 20;
  if (fact.flags.shohaKilledTrumpAce) flagBonus += 10;
  const streakBonus = 5 * Math.min(fact.winStreak, 5);
  const total = base + margin + flagBonus + streakBonus;
  return { base, margin, flagBonus, streakBonus, questBonus: 0, total };
}

/* ------------------------------------------------------------------ rating */

/**
 * Pairwise ELO, winners vs goats only: every winner plays a virtual match
 * against every goat. K=40 for players under 10 games, 24 after. Each seat's
 * summed contribution is divided by (playerCount − 1) and rounded. Zero goats
 * or all goats → all-zero deltas. The CALLER floors ratings at 100.
 */
export function ratingDeltas(ratings: number[], gamesPlayed: number[], goats: number[]): number[] {
  const n = ratings.length;
  const raw = new Array<number>(n).fill(0);
  const goatSet = new Set(goats);
  const winners = ratings.map((_, i) => i).filter((i) => !goatSet.has(i));
  if (goatSet.size === 0 || winners.length === 0 || n < 2) return raw;
  for (const w of winners) {
    for (const g of goatSet) {
      const kW = gamesPlayed[w]! < 10 ? 40 : 24;
      const kG = gamesPlayed[g]! < 10 ? 40 : 24;
      const eW = 1 / (1 + 10 ** ((ratings[g]! - ratings[w]!) / 400));
      const eG = 1 / (1 + 10 ** ((ratings[w]! - ratings[g]!) / 400));
      raw[w] = raw[w]! + kW * (1 - eW);
      raw[g] = raw[g]! - kG * eG;
    }
  }
  return raw.map((r) => Math.round(r / (n - 1)));
}

export function rankFor(rating: number): RankInfo {
  let rank = RANKS[0]!;
  for (const r of RANKS) {
    if (rating >= r.minRating) rank = r;
  }
  return rank;
}

/** Wire-shaped rank badge (drops minRating). */
export function rankBadge(rating: number): { id: RankInfo['id']; ru: string; emoji: string } {
  const { id, ru, emoji } = rankFor(rating);
  return { id, ru, emoji };
}

/* ------------------------------------------------------------------ daily */

/**
 * Claims today's bonus: bumps the streak (reset unless yesterday was claimed),
 * credits coins + weeklyCoins (caller runs rolloverWeek first), and arms the
 * ad-double offer. Returns null when today is already claimed.
 */
export function claimDaily(stats: PlayerStats, now: number, ttlMs: number): { amount: number; streak: number } | null {
  const today = utcDateKey(now);
  if (stats.lastClaimDate === today) return null;
  stats.dailyStreak = isYesterday(stats.lastClaimDate, now) ? stats.dailyStreak + 1 : 1;
  stats.lastClaimDate = today;
  const amount = DAILY_BONUS[Math.min(stats.dailyStreak, DAILY_BONUS.length) - 1]!;
  stats.coins += amount;
  stats.weeklyCoins += amount;
  stats.pendingDouble = { kind: 'daily', amount, expiresAt: now + ttlMs };
  return { amount, streak: stats.dailyStreak };
}

/**
 * Previews what the NEXT claim will pay without mutating anything. The streak
 * continues only when the last claim was today (next claim = tomorrow) or
 * yesterday; a lapse resets to day 1 — the client shows this instead of
 * guessing from dailyStreak (which over-promises after a missed day).
 */
export function nextDaily(stats: PlayerStats, now: number): { streak: number; amount: number } {
  const continues = stats.lastClaimDate === utcDateKey(now) || isYesterday(stats.lastClaimDate, now);
  const streak = continues ? stats.dailyStreak + 1 : 1;
  return { streak, amount: DAILY_BONUS[Math.min(streak, DAILY_BONUS.length) - 1]! };
}

/* ------------------------------------------------------------------ quests */

/**
 * Deterministic 3-of-12 pick for the day: sha256(playerId:date) seeds an
 * xorshift32 stream so every device computes the same set without storage.
 */
export function selectDailyQuests(playerId: string, date: string): QuestId[] {
  const hash = createHash('sha256').update(`${playerId}:${date}`).digest();
  let s = hash.readUInt32BE(0) || 0x9e3779b9; // xorshift state must be non-zero
  const next = (): number => {
    s ^= (s << 13) >>> 0;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= (s << 5) >>> 0;
    s >>>= 0;
    return s;
  };
  const ids = Object.keys(QUESTS) as QuestId[];
  const picked: QuestId[] = [];
  while (picked.length < 3) {
    const id = ids[next() % ids.length]!;
    if (!picked.includes(id)) picked.push(id);
  }
  return picked;
}

/** Lazily rolls quest state to today's set. Returns true when it changed. */
export function ensureQuestState(stats: PlayerStats, playerId: string, now: number): boolean {
  const today = utcDateKey(now);
  if (stats.questState && stats.questState.date === today) return false;
  stats.questState = {
    date: today,
    quests: selectDailyQuests(playerId, today).map((id) => ({ id, progress: 0, completed: false })),
  };
  return true;
}

/** Quest-relevant facts about one finished game. */
export interface QuestGameFact {
  isGoat: boolean;
  score: number;
  playerCount: number;
  /** Post-game streak of non-goat games (equals winStreak in this ruleset). */
  winStreak: number;
  flags: GameFlags;
}

/**
 * AUTO-CREDIT variant: advances progress and, when a quest crosses its target,
 * marks it completed immediately and returns its reward as a breakdown line —
 * the caller adds `questBonus` to the coin grant. Completed quests never
 * re-credit.
 */
export function applyGameToQuests(state: QuestState, fact: QuestGameFact): { questBonus: number; lines: RewardLine[] } {
  const win = !fact.isGoat;
  let questBonus = 0;
  const lines: RewardLine[] = [];
  for (const slot of state.quests) {
    if (slot.completed) continue;
    const def = QUESTS[slot.id];
    let progress = slot.progress;
    switch (slot.id) {
      case 'play_3':
      case 'play_5':
        progress += 1;
        break;
      case 'win_1':
      case 'win_2':
        if (win) progress += 1;
        break;
      case 'play_4p':
        if (fact.playerCount >= 4) progress += 1;
        break;
      case 'clean_win':
        if (win && fact.score === 0) progress += 1;
        break;
      case 'streak_2':
      case 'no_goat_3':
        progress = Math.max(progress, fact.winStreak);
        break;
      case 'triple_deal':
        if (win && fact.flags.wonTripleDeal) progress += 1;
        break;
      case 'comeback_win':
        if (win && fact.flags.reconnected) progress += 1;
        break;
      case 'take_120':
        if (fact.flags.took120InADeal) progress += 1;
        break;
      case 'shoha_ace':
        if (fact.flags.shohaKilledTrumpAce) progress += 1;
        break;
    }
    slot.progress = Math.min(progress, def.target);
    if (slot.progress >= def.target) {
      slot.completed = true;
      questBonus += def.reward;
      lines.push({ ru: `Задание дня: ${def.ru}`, amount: def.reward });
    }
  }
  return { questBonus, lines };
}

/** Display shape for the profile payload and the gameRewards event. */
export function questProgressView(state: QuestState): QuestProgressView[] {
  return state.quests.map((slot) => {
    const def = QUESTS[slot.id];
    return { id: slot.id, ru: def.ru, progress: slot.progress, target: def.target, completed: slot.completed };
  });
}

/* ------------------------------------------------------------------ weekly */

/** Lazily resets the weekly coin counter on week change. True when it rolled. */
export function rolloverWeek(stats: PlayerStats, now: number): boolean {
  const week = utcWeekKey(now);
  if (stats.weekKey === week) return false;
  stats.weekKey = week;
  stats.weeklyCoins = 0;
  return true;
}

/* ------------------------------------------------------------- rewarded ads */

/** Whether the daily rewarded-ad cap still has room (drives `canDouble`). */
export function canWatchRewardedAd(stats: PlayerStats, now: number, maxPerDay: number): boolean {
  const used = stats.rewardedDate === utcDateKey(now) ? stats.rewardedCount : 0;
  return used < maxPerDay;
}

export type RewardedAdResult =
  | { ok: true; granted: number }
  | { ok: false; error: 'RATE_LIMITED' | 'NOTHING_TO_DOUBLE' };

/**
 * Consumes the pending double offer after a (client-reported) rewarded ad:
 * enforces the daily cap, matches the requested kind against pendingDouble,
 * checks TTL, then credits the doubled amount and clears the offer. Caller
 * runs rolloverWeek first and saves on success.
 */
export function tryConsumeRewardedAd(
  stats: PlayerStats,
  kind: 'doubleGame' | 'doubleDaily',
  now: number,
  cfg: { maxRewardedAdsPerDay: number },
): RewardedAdResult {
  const today = utcDateKey(now);
  if (stats.rewardedDate !== today) {
    stats.rewardedDate = today;
    stats.rewardedCount = 0;
  }
  if (stats.rewardedCount >= cfg.maxRewardedAdsPerDay) return { ok: false, error: 'RATE_LIMITED' };
  const wanted: PendingDouble['kind'] = kind === 'doubleGame' ? 'game' : 'daily';
  const pending = stats.pendingDouble;
  if (!pending || pending.kind !== wanted || pending.expiresAt < now) {
    return { ok: false, error: 'NOTHING_TO_DOUBLE' };
  }
  stats.pendingDouble = null;
  stats.rewardedCount += 1;
  stats.coins += pending.amount;
  stats.weeklyCoins += pending.amount;
  return { ok: true, granted: pending.amount };
}
