export const config = {
  port: Number(process.env['PORT'] ?? 2568),
  jwtSecret: process.env['JWT_SECRET'] ?? 'dev-secret-change-in-production',
  /**
   * Extra ms on top of the turn timer so client animations and the client's
   * presentation pacing queue (trick/deal holds) never eat decision time.
   */
  turnGraceMs: 3500,
  /** Autopilot acts this fast when the seat is disconnected or timed out. */
  autopilotDelayMs: 1200,
  reconnectionSeconds: Number(process.env['RECONNECTION_SECONDS'] ?? 120),
  /** Daily cap on rewarded-ad doublings per player (UTC day). */
  maxRewardedAdsPerDay: 5,
  /** How long a game/daily reward stays doubleable via a rewarded ad. */
  pendingDoubleTtlMs: 900_000,
  /** Games required before a player appears on the all-time leaderboard. */
  leaderboardMinGames: 5,
};
