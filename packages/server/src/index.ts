import { LobbyRoom, createEndpoint, createRouter, defineRoom, defineServer, matchMaker } from '@colyseus/core';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { z } from 'zod';
import { GoatRoom } from './rooms/GoatRoom.js';
import { issueGuestToken, sanitizeNickname } from './auth.js';
import { config } from './config.js';
import { ACHIEVEMENTS } from './meta/achievements.js';
import { getMetaStore } from './meta/store.js';

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
      /** Player stats + unlocked achievements for the achievements screen. */
      profile: createEndpoint('/profile/:playerId', { method: 'GET' }, async (ctx) => {
        const playerId = (ctx.params as { playerId: string }).playerId;
        const stats = await getMetaStore().load(playerId);
        return {
          stats: {
            gamesPlayed: stats.gamesPlayed,
            gamesWon: stats.gamesWon,
            goats: stats.goats,
            winStreak: stats.winStreak,
          },
          achievements: [...stats.unlocked].map((id) => ({ id, ...ACHIEVEMENTS[id] })),
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
