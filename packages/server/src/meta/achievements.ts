import type { AchievementId } from '@goat/shared';

export interface PlayerStats {
  gamesPlayed: number;
  gamesWon: number;
  goats: number;
  winStreak: number;
  unlocked: Set<AchievementId>;
}

export const emptyStats = (): PlayerStats => ({
  gamesPlayed: 0,
  gamesWon: 0,
  goats: 0,
  winStreak: 0,
  unlocked: new Set(),
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

/**
 * Storage boundary: v1 keeps stats in process memory; the Postgres
 * implementation (M5) replaces this without touching the room.
 */
export interface MetaStore {
  load(playerId: string): Promise<PlayerStats>;
  save(playerId: string, stats: PlayerStats): Promise<void>;
}

export class InMemoryMetaStore implements MetaStore {
  private data = new Map<string, PlayerStats>();

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
}

export const defaultMetaStore = new InMemoryMetaStore();
