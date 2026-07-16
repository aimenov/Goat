export const config = {
  port: Number(process.env['PORT'] ?? 2568),
  jwtSecret: process.env['JWT_SECRET'] ?? 'dev-secret-change-in-production',
  /** Extra ms on top of the turn timer so client animations never eat decision time. */
  turnGraceMs: 2500,
  /** Autopilot acts this fast when the seat is disconnected or timed out. */
  autopilotDelayMs: 1200,
  reconnectionSeconds: Number(process.env['RECONNECTION_SECONDS'] ?? 120),
};
