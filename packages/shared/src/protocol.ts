import type { CardId, Seat, Suit } from './cards.js';
import type { EmojiId, ErrorCode, AchievementId } from './enums.js';
import type { BeatPair } from './actions.js';
import type { PlayerView, DealResult } from './view.js';

export const PROTOCOL_VERSION = 1;

/* ------------------------------------------------------------------ *
 * Client → Server                                                     *
 * ------------------------------------------------------------------ */

/** Every game intent carries a client-chosen id echoed back in the ack. */
export type ClientIntent =
  | { type: 'lead'; actionId: string; cards: CardId[] }
  | { type: 'beat'; actionId: string; pairs: BeatPair[] }
  | { type: 'discard'; actionId: string; cards: CardId[] }
  | { type: 'endTrick'; actionId: string }
  | { type: 'react'; emoji: EmojiId }
  | { type: 'ready'; ready: boolean }
  | { type: 'rematchVote'; accept: boolean }
  | { type: 'resync' }
  | { type: 'ping'; t: number };

/* ------------------------------------------------------------------ *
 * Server → Client                                                     *
 * ------------------------------------------------------------------ */

export interface LobbySeat {
  seat: Seat;
  nickname: string;
  ready: boolean;
  connected: boolean;
  isHost: boolean;
}

/**
 * Semantic game events. All carry `seq` (per-room monotonic counter). A client
 * detecting a gap sends `resync` and receives a fresh `snapshot`.
 * Private payloads (own drawn cards, face-down reveals) are sent only to their owner.
 */
export type ServerEvent =
  | { type: 'dealStarted'; seq: number; dealIndex: number; leader: Seat; multiplier: 1 | 2 | 3 }
  | { type: 'trumpRevealed'; seq: number; card: CardId; suit: Suit; source: 'initial' | 'rotation' | 'lastDealt'; toSeat?: Seat }
  | { type: 'led'; seq: number; seat: Seat; cards: CardId[] }
  | { type: 'beaten'; seq: number; seat: Seat; pairs: BeatPair[] }
  | { type: 'discarded'; seq: number; seat: Seat; count: number }
  | { type: 'trickEnded'; seq: number; winner: Seat; cardCount: number }
  | { type: 'turn'; seq: number; seat: Seat; phase: 'TRICK_LEAD' | 'TRICK_RESPOND' | 'TRICK_LEADER_DECISION'; deadline: number }
  | { type: 'cardDrawn'; seq: number; seat: Seat; stockCount: number }
  /** Targeted to the drawer only — carries the card identity. */
  | { type: 'yourDraw'; seq: number; cards: CardId[] }
  /** Targeted to the trick winner only — face-down discards now in their pile. */
  | { type: 'pileReveal'; seq: number; cards: CardId[] }
  | { type: 'dealEnded'; seq: number; results: DealResult[] }
  | { type: 'gameEnded'; seq: number; goats: Seat[]; scores: number[] }
  | { type: 'reaction'; seq: number; seat: Seat; emoji: EmojiId }
  | { type: 'playerConnection'; seq: number; seat: Seat; connected: boolean }
  | { type: 'lobby'; seq: number; seats: LobbySeat[]; canStart: boolean; you: Seat }
  | { type: 'rematch'; seq: number; votes: Seat[] }
  | { type: 'achievementUnlocked'; seq: number; id: AchievementId };

/** Full personal view — sent on join, reconnect, resync, and after every own ack. */
export interface SnapshotMessage {
  type: 'snapshot';
  seq: number;
  protocolVersion: number;
  view: PlayerView;
  /** ms epoch deadline for the current turn (0 when no turn is active). */
  deadline: number;
  nicknames: string[];
  connected: boolean[];
}

export interface IntentAck {
  type: 'ack';
  actionId: string;
  ok: boolean;
  error?: ErrorCode;
}

export interface PongMessage {
  type: 'pong';
  t: number;
}

export type ServerMessage = ServerEvent | SnapshotMessage | IntentAck | PongMessage;

/* Colyseus message channel names */
export const MSG = {
  intent: 'intent',
  event: 'event',
  snapshot: 'snapshot',
  ack: 'ack',
  pong: 'pong',
} as const;
