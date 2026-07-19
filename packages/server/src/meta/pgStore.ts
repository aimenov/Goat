import pg from 'pg';
import type { AchievementId } from '@goat/shared';
import {
  type LeaderboardRow,
  type MetaStore,
  type PendingDouble,
  type PlayerStats,
  type QuestState,
  emptyStats,
} from './achievements.js';

/**
 * Postgres-backed meta store. Schema is created on first use so a fresh
 * database works with zero manual steps; economy columns arrive as idempotent
 * ALTERs so pre-economy databases upgrade in place.
 */
export class PgMetaStore implements MetaStore {
  private pool: pg.Pool;
  private ready: Promise<void>;

  constructor(connectionString: string) {
    this.pool = new pg.Pool({ connectionString, max: 5 });
    this.ready = this.migrate();
  }

  private async migrate(): Promise<void> {
    await this.pool.query(`
      CREATE TABLE IF NOT EXISTS player_stats (
        player_id    text PRIMARY KEY,
        games_played integer NOT NULL DEFAULT 0,
        games_won    integer NOT NULL DEFAULT 0,
        goats        integer NOT NULL DEFAULT 0,
        win_streak   integer NOT NULL DEFAULT 0,
        updated_at   timestamptz NOT NULL DEFAULT now()
      );
      CREATE TABLE IF NOT EXISTS achievements (
        player_id      text NOT NULL,
        achievement_id text NOT NULL,
        unlocked_at    timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (player_id, achievement_id)
      );
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS nickname        text    NOT NULL DEFAULT '';
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS coins           integer NOT NULL DEFAULT 0;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS rating          integer NOT NULL DEFAULT 1000;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS week_key        text    NOT NULL DEFAULT '';
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS weekly_coins    integer NOT NULL DEFAULT 0;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS daily_streak    integer NOT NULL DEFAULT 0;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS last_claim_date text    NOT NULL DEFAULT '';
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS quest_state     jsonb;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS owned_cosmetics text[]  NOT NULL DEFAULT '{}';
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS equipped        jsonb;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS remove_ads      boolean NOT NULL DEFAULT false;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS rewarded_date   text    NOT NULL DEFAULT '';
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS rewarded_count  integer NOT NULL DEFAULT 0;
      ALTER TABLE player_stats ADD COLUMN IF NOT EXISTS pending_double  jsonb;
      CREATE INDEX IF NOT EXISTS player_stats_rating_idx ON player_stats (rating DESC);
      CREATE INDEX IF NOT EXISTS player_stats_weekly_idx ON player_stats (week_key, weekly_coins DESC);
      CREATE TABLE IF NOT EXISTS iap_receipts (
        platform   text NOT NULL,
        token      text NOT NULL,
        player_id  text NOT NULL,
        product_id text NOT NULL,
        granted_at timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY (platform, token)
      );
    `);
  }

  async load(playerId: string): Promise<PlayerStats> {
    await this.ready;
    const stats = emptyStats();
    const [row, unlocked] = await Promise.all([
      this.pool.query(
        `SELECT games_played, games_won, goats, win_streak, nickname, coins, rating, week_key,
                weekly_coins, daily_streak, last_claim_date, quest_state, owned_cosmetics,
                equipped, remove_ads, rewarded_date, rewarded_count, pending_double
           FROM player_stats WHERE player_id = $1`,
        [playerId],
      ),
      this.pool.query('SELECT achievement_id FROM achievements WHERE player_id = $1', [playerId]),
    ]);
    const r = row.rows[0];
    if (r) {
      stats.gamesPlayed = r.games_played;
      stats.gamesWon = r.games_won;
      stats.goats = r.goats;
      stats.winStreak = r.win_streak;
      stats.nickname = r.nickname ?? '';
      stats.coins = r.coins ?? 0;
      stats.rating = r.rating ?? 1000;
      stats.weekKey = r.week_key ?? '';
      stats.weeklyCoins = r.weekly_coins ?? 0;
      stats.dailyStreak = r.daily_streak ?? 0;
      stats.lastClaimDate = r.last_claim_date ?? '';
      stats.questState = (r.quest_state as QuestState | null) ?? null;
      stats.ownedCosmetics = new Set((r.owned_cosmetics as string[] | null) ?? []);
      if (r.equipped) stats.equipped = r.equipped as PlayerStats['equipped'];
      stats.removeAds = r.remove_ads ?? false;
      stats.rewardedDate = r.rewarded_date ?? '';
      stats.rewardedCount = r.rewarded_count ?? 0;
      stats.pendingDouble = (r.pending_double as PendingDouble | null) ?? null;
    }
    for (const a of unlocked.rows) stats.unlocked.add(a.achievement_id as AchievementId);
    return stats;
  }

  async save(playerId: string, stats: PlayerStats): Promise<void> {
    await this.ready;
    await this.pool.query(
      `INSERT INTO player_stats (player_id, games_played, games_won, goats, win_streak, nickname,
         coins, rating, week_key, weekly_coins, daily_streak, last_claim_date, quest_state,
         owned_cosmetics, equipped, remove_ads, rewarded_date, rewarded_count, pending_double, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, now())
       ON CONFLICT (player_id) DO UPDATE SET
         games_played    = EXCLUDED.games_played,
         games_won       = EXCLUDED.games_won,
         goats           = EXCLUDED.goats,
         win_streak      = EXCLUDED.win_streak,
         nickname        = EXCLUDED.nickname,
         coins           = EXCLUDED.coins,
         rating          = EXCLUDED.rating,
         week_key        = EXCLUDED.week_key,
         weekly_coins    = EXCLUDED.weekly_coins,
         daily_streak    = EXCLUDED.daily_streak,
         last_claim_date = EXCLUDED.last_claim_date,
         quest_state     = EXCLUDED.quest_state,
         owned_cosmetics = EXCLUDED.owned_cosmetics,
         equipped        = EXCLUDED.equipped,
         remove_ads      = EXCLUDED.remove_ads,
         rewarded_date   = EXCLUDED.rewarded_date,
         rewarded_count  = EXCLUDED.rewarded_count,
         pending_double  = EXCLUDED.pending_double,
         updated_at      = now()`,
      [
        playerId,
        stats.gamesPlayed,
        stats.gamesWon,
        stats.goats,
        stats.winStreak,
        stats.nickname,
        stats.coins,
        stats.rating,
        stats.weekKey,
        stats.weeklyCoins,
        stats.dailyStreak,
        stats.lastClaimDate,
        stats.questState,
        [...stats.ownedCosmetics],
        stats.equipped,
        stats.removeAds,
        stats.rewardedDate,
        stats.rewardedCount,
        stats.pendingDouble,
      ],
    );
    if (stats.unlocked.size > 0) {
      await this.pool.query(
        `INSERT INTO achievements (player_id, achievement_id)
         SELECT $1, unnest($2::text[])
         ON CONFLICT DO NOTHING`,
        [playerId, [...stats.unlocked]],
      );
    }
  }

  async topByRating(limit: number, minGames: number): Promise<LeaderboardRow[]> {
    await this.ready;
    const res = await this.pool.query(
      `SELECT player_id, nickname, rating, weekly_coins, games_played
         FROM player_stats WHERE games_played >= $2
         ORDER BY rating DESC LIMIT $1`,
      [limit, minGames],
    );
    return res.rows.map((r) => this.toRow(r));
  }

  async topByWeeklyCoins(weekKey: string, limit: number): Promise<LeaderboardRow[]> {
    await this.ready;
    const res = await this.pool.query(
      `SELECT player_id, nickname, rating, weekly_coins, games_played
         FROM player_stats WHERE week_key = $1 AND weekly_coins > 0
         ORDER BY weekly_coins DESC LIMIT $2`,
      [weekKey, limit],
    );
    return res.rows.map((r) => this.toRow(r));
  }

  /** Atomic conditional spend — a single UPDATE guarded by the balance. */
  async trySpendCoins(playerId: string, amount: number): Promise<boolean> {
    await this.ready;
    const res = await this.pool.query(
      'UPDATE player_stats SET coins = coins - $2, updated_at = now() WHERE player_id = $1 AND coins >= $2',
      [playerId, amount],
    );
    return (res.rowCount ?? 0) > 0;
  }

  /** First insert wins; a duplicate (platform, token) receipt is a no-op. */
  async redeemReceipt(platform: string, token: string, playerId: string, productId: string): Promise<boolean> {
    await this.ready;
    const res = await this.pool.query(
      `INSERT INTO iap_receipts (platform, token, player_id, product_id)
       VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
      [platform, token, playerId, productId],
    );
    return (res.rowCount ?? 0) > 0;
  }

  async close(): Promise<void> {
    await this.pool.end();
  }

  private toRow(r: {
    player_id: string;
    nickname: string;
    rating: number;
    weekly_coins: number;
    games_played: number;
  }): LeaderboardRow {
    return {
      playerId: r.player_id,
      nickname: r.nickname ?? '',
      rating: r.rating ?? 1000,
      weeklyCoins: r.weekly_coins ?? 0,
      gamesPlayed: r.games_played ?? 0,
    };
  }
}
