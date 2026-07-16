import { INSTANT_GOAT_SCORE } from '@goat/shared';

/**
 * Penalty band from won-pile card points.
 * 0 points → +6 even if the pile contains (zero-point) cards — user ruling.
 */
export function penaltyBand(points: number): 0 | 2 | 4 | 6 {
  if (points > 60) return 0;
  if (points >= 41) return 2;
  if (points >= 1) return 4;
  return 6;
}

/**
 * Deal multiplier, decided at deal start:
 * first trump rank 6 → ×2; additionally any two equal running scores (0–0 counts) → ×3.
 */
export function dealMultiplier(firstTrumpIsSix: boolean, scoresAtDealStart: readonly number[]): 1 | 2 | 3 {
  if (!firstTrumpIsSix) return 1;
  const seen = new Set<number>();
  for (const s of scoresAtDealStart) {
    if (seen.has(s)) return 3;
    seen.add(s);
  }
  return 2;
}

/**
 * Game-over check, in priority order:
 * 1. Instant rule: someone ≥ 12 while an opponent is still at 0.
 * 2. Threshold: someone ≥ scoreLimit.
 * Goats = all players sharing the highest score.
 */
export function findGoats(scores: readonly number[], scoreLimit: number): number[] | null {
  const max = Math.max(...scores);
  const min = Math.min(...scores);
  const instant = max >= INSTANT_GOAT_SCORE && min === 0;
  const threshold = max >= scoreLimit;
  if (!instant && !threshold) return null;
  return scores.flatMap((s, seat) => (s === max ? [seat] : []));
}
