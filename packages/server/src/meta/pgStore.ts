import pg from 'pg';
import type { AchievementId } from '@goat/shared';
import { type MetaStore, type PlayerStats, emptyStats } from './achievements.js';

/**
 * Postgres-backed meta store. Schema is created on first use so a fresh
 * database works with zero manual steps.
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
    `);
  }

  async load(playerId: string): Promise<PlayerStats> {
    await this.ready;
    const stats = emptyStats();
    const [row, unlocked] = await Promise.all([
      this.pool.query('SELECT games_played, games_won, goats, win_streak FROM player_stats WHERE player_id = $1', [playerId]),
      this.pool.query('SELECT achievement_id FROM achievements WHERE player_id = $1', [playerId]),
    ]);
    const r = row.rows[0];
    if (r) {
      stats.gamesPlayed = r.games_played;
      stats.gamesWon = r.games_won;
      stats.goats = r.goats;
      stats.winStreak = r.win_streak;
    }
    for (const a of unlocked.rows) stats.unlocked.add(a.achievement_id as AchievementId);
    return stats;
  }

  async save(playerId: string, stats: PlayerStats): Promise<void> {
    await this.ready;
    await this.pool.query(
      `INSERT INTO player_stats (player_id, games_played, games_won, goats, win_streak, updated_at)
       VALUES ($1, $2, $3, $4, $5, now())
       ON CONFLICT (player_id) DO UPDATE SET
         games_played = EXCLUDED.games_played,
         games_won    = EXCLUDED.games_won,
         goats        = EXCLUDED.goats,
         win_streak   = EXCLUDED.win_streak,
         updated_at   = now()`,
      [playerId, stats.gamesPlayed, stats.gamesWon, stats.goats, stats.winStreak],
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

  async close(): Promise<void> {
    await this.pool.end();
  }
}
