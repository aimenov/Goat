import type { AchievementId, QuestId } from '@goat/shared';

/** One of today's three quests with its live progress. */
export interface QuestSlot {
  id: QuestId;
  progress: number;
  /** Completed quests are auto-credited immediately — no claim step. */
  completed: boolean;
}

/** Daily quest state; regenerated when `date` (UTC day key) rolls over. */
export interface QuestState {
  date: string;
  quests: QuestSlot[];
}

/** A reward the player may double by watching one rewarded ad (short TTL). */
export interface PendingDouble {
  kind: 'game' | 'daily';
  amount: number;
  expiresAt: number;
}

export interface PlayerStats {
  gamesPlayed: number;
  gamesWon: number;
  goats: number;
  winStreak: number;
  unlocked: Set<AchievementId>;
  /** Snapshot of the last seen nickname — display only, never identity. */
  nickname: string;
  coins: number;
  rating: number;
  /** ISO-Monday week key the weeklyCoins counter belongs to. */
  weekKey: string;
  weeklyCoins: number;
  dailyStreak: number;
  /** UTC day key of the last daily-bonus claim ('' = never claimed). */
  lastClaimDate: string;
  questState: QuestState | null;
  ownedCosmetics: Set<string>;
  equipped: { cardBack: string; felt: string };
  removeAds: boolean;
  /** UTC day key + count implementing the daily rewarded-ad cap. */
  rewardedDate: string;
  rewardedCount: number;
  pendingDouble: PendingDouble | null;
}

export const emptyStats = (): PlayerStats => ({
  gamesPlayed: 0,
  gamesWon: 0,
  goats: 0,
  winStreak: 0,
  unlocked: new Set(),
  nickname: '',
  coins: 0,
  rating: 1000,
  weekKey: '',
  weeklyCoins: 0,
  dailyStreak: 0,
  lastClaimDate: '',
  questState: null,
  ownedCosmetics: new Set(),
  equipped: { cardBack: 'back_classic', felt: 'felt_classic' },
  removeAds: false,
  rewardedDate: '',
  rewardedCount: 0,
  pendingDouble: null,
});

/** Humorous titles (EN/RU) — RU strings need a native review pass before store release. */
export const ACHIEVEMENTS: Record<AchievementId, { en: string; ru: string }> = {
  first_win: { en: 'Not the Goat Today', ru: 'Сегодня не козёл' },
  wins_10: { en: 'Herd Leader', ru: 'Вожак стада' },
  wins_100: { en: 'The Goatfather', ru: 'Крёстный козёл' },
  shoha_ace: { en: 'Shoha Says No', ru: 'Шоха всему голова' },
  full_120: { en: 'Greedy Hooves', ru: 'Гребёт копытами' },
  triple_win: { en: 'Triple Trouble', ru: 'Три шкуры' },
  exact_limit: { en: 'Certified Goat', ru: 'Дипломированный козёл' },
  instant_goat: { en: 'Speedrun Goat', ru: 'Козёл-экспресс' },
  comeback_win: { en: 'The Prodigal Goat', ru: 'Блудный козёл' },
  games_100: { en: 'Barn Regular', ru: 'Завсегдатай хлева' },
  streak_5: { en: 'Hot Hooves', ru: 'Горячие копыта' },
  zero_hero: { en: 'Untouchable', ru: 'Рожки да ножки' },
};

/** Per-game flags collected by the room while the game runs. */
export interface GameFlags {
  shohaKilledTrumpAce: boolean;
  took120InADeal: boolean;
  wonTripleDeal: boolean;
  reconnected: boolean;
  tookZeroWholeGame: boolean;
}

export const emptyFlags = (): GameFlags => ({
  shohaKilledTrumpAce: false,
  took120InADeal: false,
  wonTripleDeal: false,
  reconnected: false,
  tookZeroWholeGame: false,
});

export interface GameOutcome {
  isGoat: boolean;
  score: number;
  scoreLimit: number;
  instantRule: boolean;
  flags: GameFlags;
}

/** Mutates stats with the outcome, returns newly unlocked achievements. */
export function applyGameOutcome(stats: PlayerStats, outcome: GameOutcome): AchievementId[] {
  stats.gamesPlayed += 1;
  if (outcome.isGoat) {
    stats.goats += 1;
    stats.winStreak = 0;
  } else {
    stats.gamesWon += 1;
    stats.winStreak += 1;
  }

  const fresh: AchievementId[] = [];
  const unlock = (id: AchievementId, condition: boolean) => {
    if (condition && !stats.unlocked.has(id)) {
      stats.unlocked.add(id);
      fresh.push(id);
    }
  };

  unlock('first_win', !outcome.isGoat);
  unlock('wins_10', stats.gamesWon >= 10);
  unlock('wins_100', stats.gamesWon >= 100);
  unlock('games_100', stats.gamesPlayed >= 100);
  unlock('streak_5', stats.winStreak >= 5);
  unlock('shoha_ace', outcome.flags.shohaKilledTrumpAce);
  unlock('full_120', outcome.flags.took120InADeal);
  unlock('triple_win', outcome.flags.wonTripleDeal && !outcome.isGoat);
  unlock('exact_limit', outcome.isGoat && outcome.score === outcome.scoreLimit);
  unlock('instant_goat', outcome.isGoat && outcome.instantRule);
  unlock('comeback_win', !outcome.isGoat && outcome.flags.reconnected);
  unlock('zero_hero', outcome.isGoat && outcome.flags.tookZeroWholeGame);
  return fresh;
}

/** One leaderboard entry as stored (positions are assigned by the endpoint). */
export interface LeaderboardRow {
  playerId: string;
  nickname: string;
  rating: number;
  weeklyCoins: number;
  gamesPlayed: number;
}

/**
 * Storage boundary: v1 keeps stats in process memory; the Postgres
 * implementation (M5) replaces this without touching the room.
 */
export interface MetaStore {
  load(playerId: string): Promise<PlayerStats>;
  save(playerId: string, stats: PlayerStats): Promise<void>;
  topByRating(limit: number, minGames: number): Promise<LeaderboardRow[]>;
  topByWeeklyCoins(weekKey: string, limit: number): Promise<LeaderboardRow[]>;
  /** Atomic conditional spend — false when the balance is insufficient. */
  trySpendCoins(playerId: string, amount: number): Promise<boolean>;
  /** Records an IAP receipt once — false when (platform, token) was already redeemed. */
  redeemReceipt(platform: string, token: string, playerId: string, productId: string): Promise<boolean>;
}

export class InMemoryMetaStore implements MetaStore {
  private data = new Map<string, PlayerStats>();
  private receipts = new Set<string>();

  load(playerId: string): Promise<PlayerStats> {
    let stats = this.data.get(playerId);
    if (!stats) {
      stats = emptyStats();
      this.data.set(playerId, stats);
    }
    return Promise.resolve(stats);
  }

  save(_playerId: string, _stats: PlayerStats): Promise<void> {
    return Promise.resolve(); // stats objects are live references in memory
  }

  topByRating(limit: number, minGames: number): Promise<LeaderboardRow[]> {
    const rows = [...this.data.entries()]
      .filter(([, s]) => s.gamesPlayed >= minGames)
      .sort((a, b) => b[1].rating - a[1].rating)
      .slice(0, limit)
      .map(([playerId, s]) => this.toRow(playerId, s));
    return Promise.resolve(rows);
  }

  topByWeeklyCoins(weekKey: string, limit: number): Promise<LeaderboardRow[]> {
    const rows = [...this.data.entries()]
      .filter(([, s]) => s.weekKey === weekKey && s.weeklyCoins > 0)
      .sort((a, b) => b[1].weeklyCoins - a[1].weeklyCoins)
      .slice(0, limit)
      .map(([playerId, s]) => this.toRow(playerId, s));
    return Promise.resolve(rows);
  }

  async trySpendCoins(playerId: string, amount: number): Promise<boolean> {
    const stats = await this.load(playerId);
    if (stats.coins < amount) return false;
    stats.coins -= amount;
    return true;
  }

  redeemReceipt(platform: string, token: string, _playerId: string, _productId: string): Promise<boolean> {
    const key = `${platform}:${token}`;
    if (this.receipts.has(key)) return Promise.resolve(false);
    this.receipts.add(key);
    return Promise.resolve(true);
  }

  private toRow(playerId: string, s: PlayerStats): LeaderboardRow {
    return { playerId, nickname: s.nickname, rating: s.rating, weeklyCoins: s.weeklyCoins, gamesPlayed: s.gamesPlayed };
  }
}

export const defaultMetaStore = new InMemoryMetaStore();
