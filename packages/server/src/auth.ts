import jwt from 'jsonwebtoken';
import { createHash } from 'node:crypto';
import { config } from './config.js';

export interface GuestClaims {
  playerId: string;
  nickname: string;
}

/**
 * Guest-first identity: the device sends a stable random deviceId; we derive a
 * playerId from it and sign a long-lived JWT. Account providers can merge onto
 * the same playerId later (M5).
 */
export function issueGuestToken(deviceId: string, nickname: string): { token: string; claims: GuestClaims } {
  const playerId = createHash('sha256').update(`goat:${deviceId}`).digest('hex').slice(0, 24);
  const claims: GuestClaims = { playerId, nickname };
  const token = jwt.sign(claims, config.jwtSecret, { expiresIn: '180d' });
  return { token, claims };
}

export function verifyToken(token: string): GuestClaims {
  const payload = jwt.verify(token, config.jwtSecret) as GuestClaims & { iat: number };
  if (!payload.playerId || typeof payload.nickname !== 'string') throw new Error('malformed token');
  return { playerId: payload.playerId, nickname: payload.nickname };
}

/**
 * Claims from an `Authorization: Bearer <jwt>` header, or null when the header
 * is absent/malformed/invalid. Endpoints take playerId ONLY from here — never
 * from a request body.
 */
export function bearerClaims(getHeader: (key: string) => string | null): GuestClaims | null {
  const match = /^Bearer\s+(.+)$/i.exec(getHeader('authorization') ?? '');
  if (!match) return null;
  try {
    return verifyToken(match[1]!);
  } catch {
    return null;
  }
}

export function sanitizeNickname(raw: unknown): string {
  const nick = String(raw ?? '')
    .trim()
    .replace(/[\u0000-\u001f<>]/g, String())
    .slice(0, 20);
  return nick || `Гость-${Math.floor(Math.random() * 9000 + 1000)}`;
}
