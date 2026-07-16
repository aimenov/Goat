import { type MetaStore, InMemoryMetaStore } from './achievements.js';
import { PgMetaStore } from './pgStore.js';

let store: MetaStore | null = null;

/**
 * DATABASE_URL set → Postgres (durable stats/achievements);
 * otherwise in-memory (dev / tests).
 */
export function getMetaStore(): MetaStore {
  if (!store) {
    const url = process.env['DATABASE_URL'];
    store = url ? new PgMetaStore(url) : new InMemoryMetaStore();
  }
  return store;
}
