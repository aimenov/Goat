/**
 * IAP receipt verification seam.
 *
 * v1 trust gaps (deliberate, documented for the v2 roadmap):
 * - Receipts are NOT verified against Google/Apple — TrustingVerifier accepts
 *   any well-formed redeem call and logs it. v2 replaces it behind this same
 *   interface with Play Developer API / App Store Server API checks (+ RTDN
 *   for refunds/renewals).
 * - Rewarded ads trust the client's claim that an ad finished; the AdMob
 *   server-side verification (SSV) callback is the v2 seam for that.
 * - On Postgres, spend (trySpendCoins) and grant are separate statements, not
 *   one transaction: a crash in between can lose a grant, never duplicate one
 *   (receipt dedupe runs before the grant).
 * - pendingDouble consumption (/ads/reward) is a read-modify-write: on
 *   Postgres two concurrent requests could both see the pending double and
 *   double-credit. v2 seam: clear it with a conditional UPDATE ... WHERE
 *   pending_double IS NOT NULL RETURNING, analogous to trySpendCoins.
 */
export interface IapVerifier {
  verify(platform: string, productId: string, token: string): Promise<{ ok: boolean }>;
}

/** v1: grants everything, loudly — every grant is traceable in the logs. */
export class TrustingVerifier implements IapVerifier {
  verify(platform: string, productId: string, token: string): Promise<{ ok: boolean }> {
    console.warn(`[iap] UNVERIFIED grant platform=${platform} product=${productId} token=${token.slice(0, 8)}…`);
    return Promise.resolve({ ok: true });
  }
}

let verifier: IapVerifier | null = null;

export function getIapVerifier(): IapVerifier {
  if (!verifier) verifier = new TrustingVerifier();
  return verifier;
}
