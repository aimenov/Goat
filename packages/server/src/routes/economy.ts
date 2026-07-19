/**
 * Economy HTTP endpoints. All mutating routes take identity from the Bearer
 * JWT via bearerClaims() — playerId NEVER comes from a request body. Grants
 * are exclusively server-side; the client only displays what it is told.
 */
import { createEndpoint } from '@colyseus/core';
import { z } from 'zod';
import { COSMETICS, IAP_PRODUCTS } from '@goat/shared';
import { bearerClaims } from '../auth.js';
import { config } from '../config.js';
import { getIapVerifier } from '../meta/iap.js';
import {
  canWatchRewardedAd,
  claimDaily,
  rankBadge,
  rolloverWeek,
  tryConsumeRewardedAd,
  utcWeekKey,
} from '../meta/economy.js';
import { getMetaStore } from '../meta/store.js';

/** Narrow view of the endpoint context that auth needs (status stays a literal
 * so it remains assignable to better-call's Status union). */
interface AuthCtx {
  getHeader(key: string): string | null;
  error(status: 401, body?: { message?: string; code?: string }): Error;
}

function requireClaims(ctx: AuthCtx): { playerId: string; nickname: string } {
  const claims = bearerClaims(ctx.getHeader);
  if (!claims) throw ctx.error(401, { code: 'UNAUTHORIZED' });
  return claims;
}

export function economyRoutes() {
  return {
    /** Top-50 boards; a Bearer token additionally locates the caller. */
    leaderboard: createEndpoint(
      '/leaderboard',
      { method: 'GET', query: z.object({ scope: z.enum(['weekly', 'alltime']).optional() }) },
      async (ctx) => {
        const now = Date.now();
        const store = getMetaStore();
        const scope = ctx.query?.scope ?? 'alltime';
        const weekKey = utcWeekKey(now);
        const rows =
          scope === 'weekly'
            ? await store.topByWeeklyCoins(weekKey, 50)
            : await store.topByRating(50, config.leaderboardMinGames);
        const entries = rows.map((r, i) => ({
          position: i + 1,
          playerId: r.playerId,
          nickname: r.nickname,
          rating: r.rating,
          weeklyCoins: r.weeklyCoins,
          rank: rankBadge(r.rating),
        }));
        const claims = bearerClaims(ctx.getHeader);
        let me: { position: number | null; nickname: string; rating: number; weeklyCoins: number } | null = null;
        if (claims) {
          const stats = await store.load(claims.playerId);
          me = {
            position: entries.find((e) => e.playerId === claims.playerId)?.position ?? null,
            nickname: stats.nickname || claims.nickname,
            rating: stats.rating,
            weeklyCoins: stats.weekKey === weekKey ? stats.weeklyCoins : 0,
          };
        }
        return { scope, weekKey, entries, me };
      },
    ),

    /** Daily bonus claim; arms the ad-double offer on success. */
    dailyClaim: createEndpoint('/daily/claim', { method: 'POST' }, async (ctx) => {
      const claims = requireClaims(ctx);
      const now = Date.now();
      const store = getMetaStore();
      const stats = await store.load(claims.playerId);
      rolloverWeek(stats, now);
      const result = claimDaily(stats, now, config.pendingDoubleTtlMs);
      if (!result) throw ctx.error(409, { code: 'ALREADY_CLAIMED' });
      await store.save(claims.playerId, stats);
      return {
        amount: result.amount,
        streak: result.streak,
        coins: stats.coins,
        canDouble: canWatchRewardedAd(stats, now, config.maxRewardedAdsPerDay),
      };
    }),

    /** Coin purchase of a non-premium cosmetic. */
    shopPurchase: createEndpoint(
      '/shop/purchase',
      { method: 'POST', body: z.object({ itemId: z.string().min(1).max(64) }) },
      async (ctx) => {
        const claims = requireClaims(ctx);
        const item = COSMETICS.find((c) => c.id === ctx.body.itemId);
        if (!item) throw ctx.error(404, { code: 'UNKNOWN_ITEM' });
        if (item.premium) throw ctx.error(403, { code: 'PREMIUM_ONLY' });
        const store = getMetaStore();
        const stats = await store.load(claims.playerId);
        if (item.isDefault || stats.ownedCosmetics.has(item.id)) throw ctx.error(409, { code: 'ALREADY_OWNED' });
        if (!(await store.trySpendCoins(claims.playerId, item.price))) {
          throw ctx.error(402, { code: 'INSUFFICIENT_FUNDS' });
        }
        // Reload after the atomic spend so the save below cannot restore coins.
        const fresh = await store.load(claims.playerId);
        fresh.ownedCosmetics.add(item.id);
        await store.save(claims.playerId, fresh);
        return { coins: fresh.coins, owned: [...fresh.ownedCosmetics] };
      },
    ),

    /** Equips an owned (or default) cosmetic; slot comes from the catalog. */
    shopEquip: createEndpoint(
      '/shop/equip',
      { method: 'POST', body: z.object({ itemId: z.string().min(1).max(64) }) },
      async (ctx) => {
        const claims = requireClaims(ctx);
        const item = COSMETICS.find((c) => c.id === ctx.body.itemId);
        if (!item) throw ctx.error(404, { code: 'UNKNOWN_ITEM' });
        const store = getMetaStore();
        const stats = await store.load(claims.playerId);
        if (!item.isDefault && !stats.ownedCosmetics.has(item.id)) throw ctx.error(403, { code: 'NOT_OWNED' });
        if (item.slot === 'cardBack') stats.equipped.cardBack = item.id;
        else stats.equipped.felt = item.id;
        await store.save(claims.playerId, stats);
        return { equipped: stats.equipped };
      },
    ),

    /** IAP redemption: verify (v1: trusting), dedupe receipt, then grant. */
    iapRedeem: createEndpoint(
      '/iap/redeem',
      {
        method: 'POST',
        body: z.object({
          platform: z.string().min(1).max(16),
          productId: z.string().min(1).max(64),
          token: z.string().min(1).max(4096),
        }),
      },
      async (ctx) => {
        const claims = requireClaims(ctx);
        const product = IAP_PRODUCTS.find((p) => p.productId === ctx.body.productId);
        if (!product) throw ctx.error(404, { code: 'UNKNOWN_PRODUCT' });
        const verdict = await getIapVerifier().verify(ctx.body.platform, ctx.body.productId, ctx.body.token);
        if (!verdict.ok) throw ctx.error(403, { code: 'VERIFICATION_FAILED' });
        const store = getMetaStore();
        if (!(await store.redeemReceipt(ctx.body.platform, ctx.body.token, claims.playerId, ctx.body.productId))) {
          throw ctx.error(409, { code: 'ALREADY_REDEEMED' });
        }
        const stats = await store.load(claims.playerId);
        // Bought капуста never counts toward the weekly (earned) leaderboard.
        if (product.grants.coins) stats.coins += product.grants.coins;
        if (product.grants.removeAds) stats.removeAds = true;
        if (product.grants.cosmeticId) stats.ownedCosmetics.add(product.grants.cosmeticId);
        await store.save(claims.playerId, stats);
        return {
          granted: product.grants,
          coins: stats.coins,
          removeAds: stats.removeAds,
          owned: [...stats.ownedCosmetics],
        };
      },
    ),

    /** Doubles a pending reward after a rewarded ad (v1: client-trusted). */
    adsReward: createEndpoint(
      '/ads/reward',
      { method: 'POST', body: z.object({ kind: z.enum(['doubleGame', 'doubleDaily']) }) },
      async (ctx) => {
        const claims = requireClaims(ctx);
        const now = Date.now();
        const store = getMetaStore();
        const stats = await store.load(claims.playerId);
        rolloverWeek(stats, now);
        const result = tryConsumeRewardedAd(stats, ctx.body.kind, now, config);
        if (!result.ok) {
          throw ctx.error(result.error === 'RATE_LIMITED' ? 429 : 409, { code: result.error });
        }
        await store.save(claims.playerId, stats);
        return { granted: result.granted, coins: stats.coins };
      },
    ),
  };
}
