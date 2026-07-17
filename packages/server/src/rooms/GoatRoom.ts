import { Room, updateLobby, type Client } from '@colyseus/core';
import {
  type CardId,
  type ClientIntent,
  type CreateRoomOptions,
  type EmojiId,
  type ErrorCode,
  type GameAction,
  type LobbySeat,
  type Seat,
  type ServerEvent,
  EMOJI_IDS,
  MSG,
  PROTOCOL_VERSION,
  normalizeRoomOptions,
} from '@goat/shared';
import {
  type EngineEvent,
  type GameState,
  defaultAction,
  redact,
  reduce,
  initGame,
} from '@goat/engine';
import { randomInt } from 'node:crypto';
import { SHOHA, rankOf, suitOf } from '@goat/shared';
import { config } from '../config.js';
import { sanitizeNickname, verifyToken } from '../auth.js';
import { type GameFlags, applyGameOutcome, emptyFlags } from '../meta/achievements.js';
import { getMetaStore } from '../meta/store.js';

interface SeatInfo {
  sessionId: string | null;
  playerId: string;
  nickname: string;
  connected: boolean;
  ready: boolean;
  rematchVote: boolean;
  emojiBucket: { tokens: number; last: number };
}

interface JoinOptions {
  token?: string;
  nickname?: string;
}

export class GoatRoom extends Room {
  options!: CreateRoomOptions;
  seats: SeatInfo[] = [];
  game: GameState | null = null;
  seq = 0;
  turnTimer: ReturnType<Room['clock']['setTimeout']> | null = null;
  turnDeadline = 0;
  started = false;
  flags: GameFlags[] = [];

  // ---------------------------------------------------------------- lifecycle

  onCreate(rawOptions: unknown): void {
    this.options = normalizeRoomOptions(rawOptions);
    this.maxClients = this.options.playerCount;
    this.autoDispose = true;
    this.patchRate = null; // no schema state sync — explicit messages only
    void this.setMetadata({
      name: this.options.name ?? 'Козёл',
      playerCount: this.options.playerCount,
      scoreLimit: this.options.scoreLimit,
      turnSeconds: this.options.turnSeconds,
      seatsTaken: 0,
      started: false,
    });

    this.onMessage(MSG.intent, (client: Client, message: ClientIntent) => {
      try {
        this.handleIntent(client, message);
      } catch {
        this.sendAck(client, (message as { actionId?: string }).actionId ?? '', 'INVALID_PAYLOAD');
      }
    });
  }

  onAuth(_client: Client, options: JoinOptions): { playerId: string; nickname: string } {
    if (options?.token) {
      const claims = verifyToken(options.token);
      return { playerId: claims.playerId, nickname: sanitizeNickname(options.nickname ?? claims.nickname) };
    }
    // dev/anonymous fallback: identity lives only as long as the room
    return { playerId: `anon-${Math.random().toString(36).slice(2, 10)}`, nickname: sanitizeNickname(options?.nickname) };
  }

  onJoin(client: Client): void {
    const auth = client.auth as { playerId: string; nickname: string };
    const seat: SeatInfo = {
      sessionId: client.sessionId,
      playerId: auth.playerId,
      nickname: auth.nickname,
      connected: true,
      ready: false,
      rematchVote: false,
      emojiBucket: { tokens: 3, last: Date.now() },
    };
    this.seats.push(seat);
    void this.setMetadata({ seatsTaken: this.seats.length }).then(() => updateLobby(this));
    this.broadcastLobby();
    if (this.started && this.game) this.sendSnapshot(client);
  }

  async onDrop(client: Client): Promise<void> {
    const seat = this.seatOf(client.sessionId);
    if (seat === -1) return;
    this.seats[seat]!.connected = false;
    this.pushEvent({ type: 'playerConnection', seq: this.seq, seat, connected: false });
    if (!this.started) {
      // lobby: a dropped player just leaves
      this.removeSeat(seat);
      return;
    }
    // In game: hold the seat on autopilot and wait for reconnection.
    if (this.game && this.game.phase !== 'GAME_OVER' && this.game.trick?.turn === seat) {
      this.armTurnTimer(config.autopilotDelayMs);
    }
    try {
      await this.allowReconnection(client, config.reconnectionSeconds);
    } catch {
      // window expired — the seat stays on autopilot; if everyone is gone, dispose
      if (this.seats.every((s) => !s.connected)) this.disconnect();
    }
  }

  onReconnect(client: Client): void {
    const seat = this.seatOf(client.sessionId);
    if (seat === -1) return;
    this.seats[seat]!.connected = true;
    const flag = this.flags[seat];
    if (flag) flag.reconnected = true;
    this.pushEvent({ type: 'playerConnection', seq: this.seq, seat, connected: true });
    this.sendSnapshot(client);
  }

  onLeave(client: Client): void {
    const seat = this.seatOf(client.sessionId);
    if (seat === -1) return;
    if (!this.started) {
      this.removeSeat(seat);
      return;
    }
    // consented leave mid-game: seat goes to permanent autopilot
    this.seats[seat]!.connected = false;
    this.pushEvent({ type: 'playerConnection', seq: this.seq, seat, connected: false });
    if (this.game && this.game.phase !== 'GAME_OVER' && this.game.trick?.turn === seat) {
      this.armTurnTimer(config.autopilotDelayMs);
    }
    if (this.seats.every((s) => !s.connected)) this.disconnect();
  }

  // ---------------------------------------------------------------- intents

  private handleIntent(client: Client, msg: ClientIntent): void {
    const seat = this.seatOf(client.sessionId);
    if (seat === -1) return;

    switch (msg.type) {
      case 'ping':
        client.send(MSG.pong, { type: 'pong', t: msg.t });
        return;
      case 'resync':
        if (!this.started) {
          // Pre-start there is no snapshot; answer with a targeted lobby
          // event (same payload as broadcastLobby) so a client that missed
          // the initial broadcast still learns the seats.
          const seats: LobbySeat[] = this.seats.map((s, i) => ({
            seat: i,
            nickname: s.nickname,
            ready: s.ready,
            connected: s.connected,
            isHost: i === 0,
          }));
          client.send(MSG.event, {
            type: 'lobby',
            seq: this.seq,
            seats,
            canStart: this.seats.length === this.options.playerCount && this.seats.every((s) => s.ready),
            you: seat,
          });
          return;
        }
        this.sendSnapshot(client);
        return;
      case 'react':
        this.handleReaction(client, seat, msg.emoji);
        return;
      case 'ready':
        if (this.started) return;
        this.seats[seat]!.ready = msg.ready;
        this.broadcastLobby();
        this.maybeStart();
        return;
      case 'rematchVote':
        this.handleRematchVote(seat, msg.accept);
        return;
      case 'lead':
      case 'beat':
      case 'discard':
      case 'endTrick':
        this.handleGameIntent(client, seat, msg);
        return;
    }
  }

  private handleGameIntent(
    client: Client,
    seat: Seat,
    msg: Extract<ClientIntent, { type: 'lead' | 'beat' | 'discard' | 'endTrick' }>,
  ): void {
    if (!this.started || !this.game || this.game.phase === 'GAME_OVER') {
      this.sendAck(client, msg.actionId, 'GAME_ALREADY_OVER');
      return;
    }
    const action: GameAction =
      msg.type === 'lead'
        ? { type: 'LEAD', seat, cards: msg.cards as CardId[] }
        : msg.type === 'beat'
          ? { type: 'BEAT', seat, pairs: msg.pairs }
          : msg.type === 'discard'
            ? { type: 'DISCARD', seat, cards: msg.cards as CardId[] }
            : { type: 'END_TRICK', seat };

    const result = reduce(this.game, action);
    if (!result.ok) {
      this.sendAck(client, msg.actionId, result.error);
      return;
    }
    this.sendAck(client, msg.actionId);
    this.applyEngineResult(result.state, result.events);
  }

  // ---------------------------------------------------------------- game flow

  private maybeStart(): void {
    if (this.started) return;
    if (this.seats.length !== this.options.playerCount) return;
    if (!this.seats.every((s) => s.ready)) return;
    this.started = true;
    void this.setMetadata({ started: true }).then(() => updateLobby(this));
    this.lock();
    this.flags = this.seats.map(() => emptyFlags());
    const { state, events } = initGame({
      playerCount: this.options.playerCount,
      scoreLimit: this.options.scoreLimit,
      seed: randomInt(2 ** 31), // CSPRNG seed; the engine's shuffle stays replayable
    });
    this.applyEngineResult(state, events);
  }

  /** Commit a new engine state and fan its events out (redacted per client). */
  private applyEngineResult(state: GameState, events: EngineEvent[]): void {
    this.game = state;
    this.seq += 1;
    const seq = this.seq;
    this.trackAchievementSignals(state, events);

    // Deadline must be known before the `turn` event is serialized.
    const gameOver = state.phase === 'GAME_OVER';
    const turnSeat = gameOver ? null : state.trick!.turn;
    const turnMs = gameOver
      ? 0
      : !this.seats[turnSeat!]?.connected
        ? config.autopilotDelayMs
        : this.options.turnSeconds * 1000 + config.turnGraceMs;
    this.turnDeadline = gameOver ? 0 : Date.now() + turnMs;

    for (const event of events) {
      for (const wire of this.toWire(event, seq)) {
        if (wire.toSeat !== undefined) {
          this.clientAt(wire.toSeat)?.send(MSG.event, wire.message);
        } else {
          this.broadcast(MSG.event, wire.message);
        }
      }
    }

    if (gameOver) {
      this.clearTurnTimer();
      return;
    }

    // The seat to move gets its personal snapshot (carries legal actions).
    this.armTurnTimer(turnMs);
    const turnClient = this.clientAt(turnSeat!);
    if (turnClient) this.sendSnapshot(turnClient);
  }

  /**
   * Map a full-information engine event to wire messages. Private payloads
   * (hand contents, face-down reveals) go only to their owner.
   */
  private toWire(event: EngineEvent, seq: number): { message: ServerEvent; toSeat?: Seat }[] {
    switch (event.type) {
      case 'dealStarted':
        return [{ message: { type: 'dealStarted', seq, dealIndex: event.dealIndex, leader: event.leader, multiplier: event.multiplier } }];
      case 'cardsDealt':
        return event.hands.map((cards, seat) => ({ message: { type: 'yourDraw', seq, cards }, toSeat: seat as Seat }));
      case 'trumpRevealed':
        return [{ message: { type: 'trumpRevealed', seq, card: event.card, suit: event.suit, source: event.source, ...(event.toSeat !== undefined ? { toSeat: event.toSeat } : {}) } }];
      case 'led':
        return [{ message: { type: 'led', seq, seat: event.seat, cards: event.cards } }];
      case 'beaten':
        return [{ message: { type: 'beaten', seq, seat: event.seat, pairs: event.pairs } }];
      case 'discarded':
        return [{ message: { type: 'discarded', seq, seat: event.seat, count: event.cards.length } }];
      case 'trickEnded':
        return [
          { message: { type: 'trickEnded', seq, winner: event.winner, cardCount: event.faceUp.length + event.faceDown.length } },
          // the winner may review everything they took, incl. face-downs
          { message: { type: 'pileReveal', seq, cards: [...event.faceUp, ...event.faceDown] }, toSeat: event.winner },
        ];
      case 'cardDrawn':
        return [
          { message: { type: 'cardDrawn', seq, seat: event.seat, stockCount: event.stockCount } },
          { message: { type: 'yourDraw', seq, cards: [event.card] }, toSeat: event.seat },
        ];
      case 'turn':
        return [{ message: { type: 'turn', seq, seat: event.seat, phase: event.phase as 'TRICK_LEAD', deadline: this.turnDeadline } }];
      case 'dealEnded':
        return [{ message: { type: 'dealEnded', seq, results: event.results } }];
      case 'gameEnded':
        return [{ message: { type: 'gameEnded', seq, goats: event.goats, scores: event.scores } }];
    }
  }

  // ---------------------------------------------------------- achievements

  private trackAchievementSignals(state: GameState, events: EngineEvent[]): void {
    if (this.flags.length === 0) return;
    for (const event of events) {
      if (event.type === 'beaten') {
        const flag = this.flags[event.seat];
        if (
          flag &&
          event.pairs.some(
            (p) => p.card === SHOHA && suitOf(p.target) === state.trumpSuit && rankOf(p.target) === 8,
          )
        ) {
          flag.shohaKilledTrumpAce = true;
        }
      } else if (event.type === 'dealEnded') {
        for (const r of event.results) {
          const flag = this.flags[r.seat];
          if (!flag) continue;
          if (r.cardPoints === 120) flag.took120InADeal = true;
          if (r.cardPoints > 0) flag.tookZeroWholeGame = false;
          if (state.multiplier === 3 && r.penalty === 0) flag.wonTripleDeal = true;
        }
      } else if (event.type === 'gameEnded') {
        void this.awardAchievements(event.goats, event.scores);
      }
    }
  }

  private async awardAchievements(goats: Seat[], scores: number[]): Promise<void> {
    const instantRule = scores.includes(0) && Math.max(...scores) < this.options.scoreLimit;
    for (let seat = 0; seat < this.seats.length; seat++) {
      const info = this.seats[seat]!;
      const flags = this.flags[seat] ?? emptyFlags();
      try {
        const stats = await getMetaStore().load(info.playerId);
        const fresh = applyGameOutcome(stats, {
          isGoat: goats.includes(seat),
          score: scores[seat]!,
          scoreLimit: this.options.scoreLimit,
          instantRule,
          flags,
        });
        await getMetaStore().save(info.playerId, stats);
        const client = this.clientAt(seat);
        for (const id of fresh) {
          client?.send(MSG.event, { type: 'achievementUnlocked', seq: this.seq, id });
        }
      } catch {
        // achievements must never break the game loop
      }
    }
  }

  // ---------------------------------------------------------------- timers

  private armTurnTimer(ms: number): void {
    this.clearTurnTimer();
    this.turnDeadline = Date.now() + ms;
    this.turnTimer = this.clock.setTimeout(() => {
      if (!this.game || this.game.phase === 'GAME_OVER') return;
      const result = reduce(this.game, defaultAction(this.game));
      if (result.ok) this.applyEngineResult(result.state, result.events);
    }, ms);
  }

  private clearTurnTimer(): void {
    this.turnTimer?.clear();
    this.turnTimer = null;
  }

  // ---------------------------------------------------------------- messaging

  private sendAck(client: Client, actionId: string, error?: ErrorCode): void {
    client.send(MSG.ack, { type: 'ack', actionId, ok: !error, ...(error ? { error } : {}) });
  }

  private sendSnapshot(client: Client): void {
    const seat = this.seatOf(client.sessionId);
    if (seat === -1 || !this.game) return;
    client.send(MSG.snapshot, {
      type: 'snapshot',
      seq: this.seq,
      protocolVersion: PROTOCOL_VERSION,
      view: redact(this.game, seat),
      deadline: this.turnDeadline,
      nicknames: this.seats.map((s) => s.nickname),
      connected: this.seats.map((s) => s.connected),
    });
  }

  private pushEvent(event: ServerEvent): void {
    this.broadcast(MSG.event, event);
  }

  private broadcastLobby(): void {
    const seats: LobbySeat[] = this.seats.map((s, i) => ({
      seat: i,
      nickname: s.nickname,
      ready: s.ready,
      connected: s.connected,
      isHost: i === 0,
    }));
    const canStart = this.seats.length === this.options.playerCount && this.seats.every((s) => s.ready);
    // per-client so each recipient learns which seat is theirs (`you`) —
    // nicknames are not unique and must never be used for identity
    for (const client of this.clients) {
      client.send(MSG.event, {
        type: 'lobby',
        seq: this.seq,
        seats,
        canStart,
        you: this.seatOf(client.sessionId),
      });
    }
  }

  private handleReaction(client: Client, seat: Seat, emoji: EmojiId): void {
    if (!EMOJI_IDS.includes(emoji)) return;
    const bucket = this.seats[seat]!.emojiBucket;
    const now = Date.now();
    bucket.tokens = Math.min(3, bucket.tokens + (now - bucket.last) / 2000);
    bucket.last = now;
    if (bucket.tokens < 1) {
      this.sendAck(client, '', 'RATE_LIMITED');
      return;
    }
    bucket.tokens -= 1;
    this.pushEvent({ type: 'reaction', seq: this.seq, seat, emoji });
  }

  private handleRematchVote(seat: Seat, accept: boolean): void {
    if (!this.game || this.game.phase !== 'GAME_OVER') return;
    this.seats[seat]!.rematchVote = accept;
    const votes = this.seats.flatMap((s, i) => (s.rematchVote ? [i] : []));
    this.pushEvent({ type: 'rematch', seq: this.seq, votes });
    if (votes.length === this.seats.filter((s) => s.connected).length && votes.length >= 2) {
      this.seats.forEach((s) => (s.rematchVote = false));
      this.flags = this.seats.map(() => emptyFlags());
      const { state, events } = initGame({
        playerCount: this.options.playerCount,
        scoreLimit: this.options.scoreLimit,
        seed: randomInt(2 ** 31),
      });
      this.applyEngineResult(state, events);
    }
  }

  // ---------------------------------------------------------------- helpers

  private seatOf(sessionId: string): number {
    return this.seats.findIndex((s) => s.sessionId === sessionId);
  }

  private clientAt(seat: Seat): Client | undefined {
    const sessionId = this.seats[seat]?.sessionId;
    return this.clients.find((c) => c.sessionId === sessionId);
  }

  private removeSeat(seat: number): void {
    this.seats.splice(seat, 1);
    void this.setMetadata({ seatsTaken: this.seats.length }).then(() => updateLobby(this));
    this.broadcastLobby();
  }
}
