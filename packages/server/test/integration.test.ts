/**
 * M2 gate: a scripted 4-player game over a real Colyseus server + WebSockets.
 * Random-but-legal players (driven by server-sent legal actions) play until the
 * game ends; asserts protocol shape, privacy, reconnection, and ack semantics.
 */
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import type {
  IntentAck,
  LegalActions,
  PlayerView,
  ServerEvent,
  SnapshotMessage,
} from '@goat/shared';
import { findPerfectMatching } from '@goat/engine';
import { createGameServer } from '../src/index.js';
import { MiniClient, MiniRoom } from './miniClient.js';

const PORT = 25_670;
const HTTP = `http://localhost:${PORT}`;

let server: ReturnType<typeof createGameServer>;

before(async () => {
  server = createGameServer();
  await server.listen(PORT);
});

after(async () => {
  await server.gracefullyShutdown(false);
});

interface Player {
  room: MiniRoom;
  seat: number;
  view: PlayerView | null;
  viewSeq: number;
  deadline: number;
  events: ServerEvent[];
  acks: IntentAck[];
  yourDraws: number[][];
  pileReveals: number[][];
}

function wirePlayer(room: MiniRoom): Player {
  const p: Player = { room, seat: -1, view: null, viewSeq: -1, deadline: 0, events: [], acks: [], yourDraws: [], pileReveals: [] };
  room.onMessage('event', (raw) => {
    const msg = raw as ServerEvent;
    p.events.push(msg);
    if (msg.type === 'yourDraw') p.yourDraws.push(msg.cards);
    if (msg.type === 'pileReveal') p.pileReveals.push(msg.cards);
  });
  room.onMessage('snapshot', (raw) => {
    const msg = raw as SnapshotMessage;
    p.view = msg.view;
    p.viewSeq = msg.seq;
    p.seat = msg.view.seat;
    p.deadline = msg.deadline;
  });
  room.onMessage('ack', (raw) => p.acks.push(raw as IntentAck));
  room.onMessage('pong', () => {});
  return p;
}

const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function until(cond: () => boolean, ms = 8000, what = 'condition'): Promise<void> {
  const t0 = Date.now();
  while (!cond()) {
    if (Date.now() - t0 > ms) throw new Error(`timeout waiting for ${what}`);
    await wait(10);
  }
}

/** Play one move from the player's snapshot-provided legal actions. */
function play(p: Player, actionId: string): void {
  const legal = p.view!.legal as LegalActions;
  if (legal.kind === 'lead') {
    const first = Object.values(legal.rankGroups)[0]![0]!;
    p.room.send('intent', { type: 'lead', actionId, cards: [first] });
  } else if (legal.kind === 'respond') {
    const pairs = legal.canBeat ? findPerfectMatching(legal.beatMatrix) : null;
    if (pairs) {
      p.room.send('intent', { type: 'beat', actionId, pairs });
    } else {
      p.room.send('intent', { type: 'discard', actionId, cards: p.view!.myHand.slice(0, legal.discardCount) });
    }
  } else {
    p.room.send('intent', { type: 'endTrick', actionId });
  }
}

test('full 4-player game over WebSocket: privacy, acks, legality, completion', async () => {
  const client = new MiniClient(HTTP);
  const first = await client.joinOrCreate('goat', { nickname: 'Один', playerCount: 4, scoreLimit: 24, turnSeconds: 15 });
  const rooms: MiniRoom[] = [first];
  for (let i = 1; i < 4; i++) {
    rooms.push(await client.joinById(first.roomId, { nickname: `Игрок${i}` }));
  }
  const players = rooms.map(wirePlayer);

  // everyone readies up → game starts
  for (const p of players) p.room.send('intent', { type: 'ready', ready: true });
  await until(() => players.some((p) => p.view !== null), 8000, 'first snapshot');

  // give all players a snapshot for seat mapping
  for (const p of players) p.room.send('intent', { type: 'resync' });
  await until(() => players.every((p) => p.view !== null), 8000, 'all snapshots');

  // deal started: everyone got exactly 6 cards privately
  await until(() => players.every((p) => p.yourDraws.length > 0), 8000, 'hands dealt');
  for (const p of players) {
    assert.equal(p.yourDraws[0]!.length, 6, 'private hand of 6');
    assert.equal(p.view!.myHand.length, 6);
    // privacy: views expose only counts for other seats
    assert.ok(p.view!.seats.every((s) => s.handCount === 6));
    assert.equal((p.view as unknown as Record<string, unknown>)['stock'], undefined);
  }

  // play until the game ends (cap at 3000 moves; server enforces legality)
  let moves = 0;
  let gameEnded = false;
  while (!gameEnded && moves < 3000) {
    if (players[0]!.events.some((e) => e.type === 'gameEnded')) {
      gameEnded = true;
      break;
    }
    // the authoritative mover comes from the latest `turn` event; wait for
    // their snapshot to catch up so `legal` matches that turn (stale views
    // from earlier turns must never trigger a move)
    const turns = players[0]!.events.filter((e) => e.type === 'turn');
    const lastTurn = turns[turns.length - 1];
    if (!lastTurn || lastTurn.type !== 'turn') {
      await wait(15);
      continue;
    }
    const mover = players.find((p) => p.seat === lastTurn.seat)!;
    await until(
      () => players[0]!.events.some((e) => e.type === 'gameEnded') || (mover.viewSeq >= lastTurn.seq && mover.view?.legal != null),
      8000,
      `snapshot for turn seq ${lastTurn.seq}`,
    );
    if (players[0]!.events.some((e) => e.type === 'gameEnded')) {
      gameEnded = true;
      break;
    }
    const actionId = `m${moves}`;
    const ackCount = mover.acks.length;
    play(mover, actionId);
    await until(() => mover.acks.length > ackCount, 8000, `ack for move ${moves}`);
    const ack = mover.acks[mover.acks.length - 1]!;
    assert.equal(ack.ok, true, `move ${moves} rejected: ${ack.error}`);
    moves++;
  }
  assert.ok(gameEnded, `game did not end after ${moves} moves`);

  const end = players[0]!.events.find((e) => e.type === 'gameEnded');
  assert.ok(end && end.type === 'gameEnded');
  assert.ok(end.goats.length >= 1);
  assert.equal(end.scores.length, 4);

  // discarded events never leak card identities
  for (const p of players) {
    for (const e of p.events) {
      if (e.type === 'discarded') {
        assert.equal((e as unknown as Record<string, unknown>)['cards'], undefined);
      }
    }
  }

  for (const room of rooms) await room.leave();
});

test('reconnection: dropped player gets a fresh snapshot and keeps their seat', async () => {
  const client = new MiniClient(HTTP);
  const first = await client.joinOrCreate('goat', { nickname: 'А', playerCount: 2, scoreLimit: 24, turnSeconds: 15 });
  const second = await client.joinById(first.roomId, { nickname: 'Б' });
  const p0 = wirePlayer(first);
  const p1 = wirePlayer(second);
  first.send('intent', { type: 'ready', ready: true });
  second.send('intent', { type: 'ready', ready: true });
  await until(() => p0.view !== null || p1.view !== null, 8000, 'game start');
  first.send('intent', { type: 'resync' });
  await until(() => p0.view !== null, 8000, 'p0 snapshot');

  const token = first.reconnectionToken;
  const seatBefore = p0.view!.seat;
  const scoreLimitBefore = p0.view!.scoreLimit;

  // hard drop (no consented leave), then reconnect within the window
  first.drop();
  await wait(300);
  const rejoined = await client.reconnect(token);
  const p0b = wirePlayer(rejoined);
  rejoined.send('intent', { type: 'resync' });
  await until(() => p0b.view !== null, 8000, 'snapshot after reconnect');
  assert.equal(p0b.view!.seat, seatBefore);
  assert.equal(p0b.view!.scoreLimit, scoreLimitBefore);
  assert.equal(p0b.view!.myHand.length, 6);

  await rejoined.leave();
  await second.leave();
});

test('lobby: created rooms are listed with their options', async () => {
  const client = new MiniClient(HTTP);
  const room = await client.create('goat', { nickname: 'Хост', playerCount: 6, scoreLimit: 36, turnSeconds: 45 });
  await wait(100);
  const rooms = await client.getAvailableRooms('goat');
  const mine = rooms.find((r) => r.roomId === room.roomId);
  assert.ok(mine, 'room listed');
  assert.equal(mine.metadata?.['playerCount'], 6);
  assert.equal(mine.metadata?.['scoreLimit'], 36);
  await room.leave();
});

test('guest auth endpoint issues a token the room accepts', async () => {
  const res = await fetch(`${HTTP}/auth/guest`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ deviceId: 'device-12345678', nickname: 'Козлевич' }),
  });
  assert.equal(res.status, 200);
  const body = (await res.json()) as { token: string; playerId: string; nickname: string };
  assert.ok(body.token.length > 20);
  assert.equal(body.nickname, 'Козлевич');

  const client = new MiniClient(HTTP);
  const room = await client.joinOrCreate('goat', { token: body.token, playerCount: 2 });
  assert.ok(room.roomId);
  await room.leave();
});
