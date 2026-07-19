import { LobbyRoom, createEndpoint, createRouter, defineRoom, defineServer, matchMaker } from '@colyseus/core';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { z } from 'zod';
import { GoatRoom } from './rooms/GoatRoom.js';
import { issueGuestToken, sanitizeNickname } from './auth.js';
import { config } from './config.js';
import { ACHIEVEMENTS } from './meta/achievements.js';
import { ensureQuestState, nextDaily, questProgressView, rankBadge, utcDateKey, utcWeekKey } from './meta/economy.js';
import { getMetaStore } from './meta/store.js';
import { economyRoutes } from './routes/economy.js';

export function createGameServer() {
  return defineServer({
    transport: new WebSocketTransport(),
    rooms: {
      goat: defineRoom(GoatRoom).enableRealtimeListing(),
      lobby: defineRoom(LobbyRoom),
    },
    routes: createRouter({
      guestAuth: createEndpoint(
        '/auth/guest',
        {
          method: 'POST',
          body: z.object({ deviceId: z.string().min(8).max(64), nickname: z.string().optional() }),
        },
        async (ctx) => {
          const nickname = sanitizeNickname(ctx.body.nickname);
          const { token, claims } = issueGuestToken(ctx.body.deviceId, nickname);
          return { token, playerId: claims.playerId, nickname };
        },
      ),
      health: createEndpoint('/health', { method: 'GET' }, async () => ({ ok: true })),
      /** Player stats, achievements, and the public economy profile. */
      profile: createEndpoint('/profile/:playerId', { method: 'GET' }, async (ctx) => {
        const playerId = (ctx.params as { playerId: string }).playerId;
        const now = Date.now();
        const store = getMetaStore();
        const stats = await store.load(playerId);
        // Quest rollover persists only for players that actually exist —
        // this endpoint is public, and saving for arbitrary ids would let
        // anyone create unbounded rows by fetching random profile URLs.
        // (The quest set is deterministic from playerId+date anyway.)
        const exists = stats.gamesPlayed > 0 || stats.coins > 0 || stats.unlocked.size > 0;
        if (ensureQuestState(stats, playerId, now) && exists) await store.save(playerId, stats);
        return {
          stats: {
            gamesPlayed: stats.gamesPlayed,
            gamesWon: stats.gamesWon,
            goats: stats.goats,
            winStreak: stats.winStreak,
          },
          achievements: [...stats.unlocked].map((id) => ({ id, ...ACHIEVEMENTS[id] })),
          nickname: stats.nickname,
          coins: stats.coins,
          rating: stats.rating,
          rank: rankBadge(stats.rating),
          dailyStreak: stats.dailyStreak,
          dailyClaimable: stats.lastClaimDate !== utcDateKey(now),
          // What the next claim actually pays — a lapsed streak resets to day
          // 1, which dailyStreak alone can't tell the client.
          nextClaimStreak: nextDaily(stats, now).streak,
          nextClaimAmount: nextDaily(stats, now).amount,
          weeklyCoins: stats.weekKey === utcWeekKey(now) ? stats.weeklyCoins : 0,
          quests: questProgressView(stats.questState!),
          ownedCosmetics: [...stats.ownedCosmetics],
          equipped: stats.equipped,
          removeAds: stats.removeAds,
        };
      }),
      /** Open-room list for the lobby screen. */
      rooms: createEndpoint('/rooms', { method: 'GET' }, async () => {
        const rooms = await matchMaker.query({ name: 'goat', locked: false, private: false });
        return rooms.map((r) => ({
          roomId: r.roomId,
          clients: r.clients,
          maxClients: r.maxClients,
          metadata: r.metadata ?? {},
        }));
      }),
      ...economyRoutes(),
    }),
  });
}

const entry = process.argv[1]?.replace(/\\/g, '/') ?? '';
if (entry.endsWith('src/index.ts') || entry.endsWith('dist/index.js')) {
  const server = createGameServer();
  void server.listen(config.port).then(() => {
    console.log(`goat server listening on ws://localhost:${config.port}`);
  });
}
