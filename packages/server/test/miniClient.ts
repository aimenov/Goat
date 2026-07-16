/**
 * Minimal Colyseus 0.17 client — matchmake HTTP + WS envelope + MessagePack.
 * Deliberately tiny: it is the reference implementation for the Flutter/Dart
 * transport (app/lib/core/net), so keep the two in sync.
 *
 * Wire format (verified against @colyseus/core 0.17):
 *   join:      POST /matchmake/{method}/{roomName} {options} → {name, sessionId, roomId, processId}
 *   connect:   ws://host/{processId}/{roomId}?sessionId=S[&reconnectionToken=T]
 *   handshake: server → [10][msgpack str reconnectionToken][msgpack str serializerId][...]
 *              client → [10]                      (confirms join)
 *   data:      [13][msgpack type][msgpack payload]  (both directions)
 *   ping:      server ← [18] → client replies [18]
 *   leave:     client → [12]; consented close code = 4000
 */
import WebSocket from 'ws';
import { Packr, unpackMultiple } from 'msgpackr';

const packr = new Packr({ useRecords: false });

const JOIN_ROOM = 10;
const LEAVE_ROOM = 12;
const ROOM_DATA = 13;
const PING = 18;

export interface SeatReservation {
  name: string;
  sessionId: string;
  roomId: string;
  processId: string;
}

export class MiniRoom {
  private ws!: WebSocket;
  private handlers = new Map<string, ((message: unknown) => void)[]>();
  private joined = false;
  reconnectionToken = '';
  serializerId = '';

  constructor(
    readonly httpEndpoint: string,
    readonly reservation: SeatReservation,
  ) {}

  get roomId(): string {
    return this.reservation.roomId;
  }
  get sessionId(): string {
    return this.reservation.sessionId;
  }

  connect(reconnectionToken?: string): Promise<void> {
    const wsEndpoint = this.httpEndpoint.replace(/^http/, 'ws');
    const params = new URLSearchParams({ sessionId: this.reservation.sessionId });
    if (reconnectionToken) params.set('reconnectionToken', reconnectionToken);
    const url = `${wsEndpoint}/${this.reservation.processId}/${this.reservation.roomId}?${params}`;
    this.ws = new WebSocket(url);
    this.ws.binaryType = 'nodebuffer';

    return new Promise((resolve, reject) => {
      this.ws.on('error', reject);
      this.ws.on('close', (code) => {
        if (!this.joined) reject(new Error(`closed before join (code ${code})`));
      });
      this.ws.on('message', (data: Buffer) => {
        const code = data[0]!;
        if (code === JOIN_ROOM) {
          // [10][len][token utf8][len][serializerId utf8][handshake bytes...]
          let offset = 1;
          const tokenLen = data[offset++]!;
          const token = data.subarray(offset, offset + tokenLen).toString('utf8');
          offset += tokenLen;
          const serializerLen = data[offset++]!;
          this.serializerId = data.subarray(offset, offset + serializerLen).toString('utf8');
          this.reconnectionToken = `${this.reservation.roomId}:${token}`;
          this.ws.send(Buffer.from([JOIN_ROOM]));
          this.joined = true;
          resolve();
        } else if (code === ROOM_DATA) {
          const values: unknown[] = [];
          unpackMultiple(data.subarray(1), (v: unknown) => {
            values.push(v);
            return values.length < 2;
          });
          const [type, payload] = values;
          for (const handler of this.handlers.get(String(type)) ?? []) handler(payload);
        } else if (code === PING) {
          this.ws.send(Buffer.from([PING]));
        }
      });
    });
  }

  onMessage(type: string, handler: (message: unknown) => void): void {
    const list = this.handlers.get(type) ?? [];
    list.push(handler);
    this.handlers.set(type, list);
  }

  send(type: string, payload: unknown): void {
    this.ws.send(Buffer.concat([Buffer.from([ROOM_DATA]), packr.pack(type), packr.pack(payload)]));
  }

  /** Consented leave. */
  leave(): Promise<void> {
    return new Promise((resolve) => {
      this.ws.once('close', () => resolve());
      this.ws.send(Buffer.from([LEAVE_ROOM]));
    });
  }

  /** Simulate a transport drop (no consent — server should hold the seat). */
  drop(): void {
    this.ws.terminate();
  }
}

export class MiniClient {
  constructor(readonly endpoint: string) {}

  private async matchmake(method: string, roomName: string, options: unknown): Promise<SeatReservation> {
    const res = await fetch(`${this.endpoint}/matchmake/${method}/${roomName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(options ?? {}),
    });
    const body = (await res.json()) as SeatReservation & { code?: number; error?: string };
    if (!res.ok) throw new Error(`matchmake ${method} failed: ${body.error ?? res.status}`);
    return body;
  }

  async joinOrCreate(roomName: string, options: unknown): Promise<MiniRoom> {
    const room = new MiniRoom(this.endpoint, await this.matchmake('joinOrCreate', roomName, options));
    await room.connect();
    return room;
  }

  async create(roomName: string, options: unknown): Promise<MiniRoom> {
    const room = new MiniRoom(this.endpoint, await this.matchmake('create', roomName, options));
    await room.connect();
    return room;
  }

  async joinById(roomId: string, options: unknown): Promise<MiniRoom> {
    const room = new MiniRoom(this.endpoint, await this.matchmake('joinById', roomId, options));
    await room.connect();
    return room;
  }

  /** reconnectionToken format: "{roomId}:{token}" (as colyseus.js). */
  async reconnect(reconnectionToken: string): Promise<MiniRoom> {
    const [roomId, token] = reconnectionToken.split(':');
    const reservation = await this.matchmake('reconnect', roomId!, { reconnectionToken: token });
    const room = new MiniRoom(this.endpoint, reservation);
    await room.connect(token);
    return room;
  }

  async getAvailableRooms(_roomName: string): Promise<{ roomId: string; metadata?: Record<string, unknown> }[]> {
    const res = await fetch(`${this.endpoint}/rooms`);
    return (await res.json()) as { roomId: string; metadata?: Record<string, unknown> }[];
  }
}
