export const PLAYER_COUNTS = [2, 3, 4, 6] as const;
export type PlayerCount = (typeof PLAYER_COUNTS)[number];

export const SCORE_LIMITS = [24, 36] as const;
export type ScoreLimit = (typeof SCORE_LIMITS)[number];

export const TURN_SECONDS_OPTIONS = [15, 30, 45] as const;
export type TurnSeconds = (typeof TURN_SECONDS_OPTIONS)[number];

export interface CreateRoomOptions {
  playerCount: PlayerCount;
  scoreLimit: ScoreLimit;
  turnSeconds: TurnSeconds;
  /** Room title shown in the lobby list. */
  name?: string;
}

export const DEFAULT_ROOM_OPTIONS: CreateRoomOptions = {
  playerCount: 4,
  scoreLimit: 24,
  turnSeconds: 30,
};

/** Instant-goat rule: score ≥ 12 while an opponent is still at 0 ends the game. */
export const INSTANT_GOAT_SCORE = 12;

export const RECONNECTION_SECONDS = 120;

export function normalizeRoomOptions(raw: unknown): CreateRoomOptions {
  const o = (raw ?? {}) as Partial<CreateRoomOptions>;
  return {
    playerCount: PLAYER_COUNTS.includes(o.playerCount as never) ? (o.playerCount as PlayerCount) : DEFAULT_ROOM_OPTIONS.playerCount,
    scoreLimit: SCORE_LIMITS.includes(o.scoreLimit as never) ? (o.scoreLimit as ScoreLimit) : DEFAULT_ROOM_OPTIONS.scoreLimit,
    turnSeconds: TURN_SECONDS_OPTIONS.includes(o.turnSeconds as never) ? (o.turnSeconds as TurnSeconds) : DEFAULT_ROOM_OPTIONS.turnSeconds,
    ...(typeof o.name === 'string' && o.name.trim() ? { name: o.name.trim().slice(0, 40) } : {}),
  };
}
