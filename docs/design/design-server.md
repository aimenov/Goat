# Goat (Козёл) — Colyseus Backend Design Document

**Target stack:** Colyseus **0.17** (released Feb 2026: `defineServer()`, `onDrop()` lifecycle, automatic reconnection, full-stack TS types) with `@colyseus/schema` 3.x (**StateView / `@view()`** per-client filtering, which replaced the old `@filter()` decorators in 0.16). Node.js 20+, TypeScript 5.x.

> ⚠️ **Version caveat (flagged):** the official client SDKs for 0.17 are JS/TS-first. The community **Dart/Flutter Colyseus SDK historically lags** behind the server protocol version. Before coding, verify which server protocol the Dart SDK supports; if it only supports 0.15/0.16, pin the server to **0.16** (StateView already exists there — everything in this document works on 0.16 with minor API renames: `onLeave(consented)` instead of `onDrop`, `Room<State>` generics, etc.). The design below is written against 0.17 idioms and notes 0.16 fallbacks where relevant.

---

## 0. Rules-engine assumptions (AMBIGUITIES — human must confirm)

The engine is built as a pure deterministic module, so every one of these is a single-function change later. All are **flagged**:

| # | Ambiguity | Assumption made |
|---|-----------|-----------------|
| **A1** | Fate of the initially revealed trump card | It is placed **face-up at the bottom of the stock** and is **drawn last** (classic Russian convention). It is a normal playable card once drawn. |
| **A2** | Trump rotation timing | After each trick, players replenish one-at-a-time from the winner; **the last card drawn in that replenishment round** is shown to all, its suit becomes the new trump, and it goes into the drawer's hand. (This satisfies "trump can change after each trick while stock lasts.") |
| **A3** | Turn flow with 3/4/6 players | The beat-chain proceeds **clockwise from the leader** and **may wrap around the table** (including back to the leader) until someone declines. Every seated player participates in every trick when the chain reaches them. |
| **A4** | Player has fewer than N cards when the chain reaches them | They are **forced to decline** and discard **all remaining cards** face-down (fewer than N). |
| **A5** | Multi-card beating pairing | The **defender chooses the pairing**: they submit explicit `(targetCard → beatingCard)` pairs; server validates each pair independently. |
| **A6** | 6 players (36 cards dealt, no stock) | Trump is determined by **revealing the dealer's last-dealt (36th) card** to everyone; it stays in the dealer's hand. Trump is fixed for the whole deal. No replenishment. |
| **A7** | Stock exhausted | No more replenishment; the **last announced trump stays fixed**; hands shrink; the deal ends when all hands are empty. |
| **A8** | First lead / dealer rotation | Deal 1: random dealer; the player **left of the dealer leads** the first trick. Dealer rotates clockwise each deal. Trick winner leads subsequent tricks. |
| **A9** | Won-pile visibility to opponents | Opponents see the **card count** of each won pile (taking is a public act) but never contents or point totals until deal end. |
| **A10** | "Two players had equal running scores" for triple game | Triple applies if **any two (or more) players** were tied at deal start (including 0–0 ties, i.e. the first deal with a 6 revealed is always a triple game). |
| **A11** | Game-end tie-breaks | If several players cross the limit in the same deal, **the highest score is the goat**; if still tied, **all tied players are goats** (stats record a shared loss). |
| **A12** | 12-vs-0 instant rule | Checked **after each deal's scoring**; if any player has ≥12 while any other player has exactly 0, the game ends immediately and the ≥12 player(s) are the goat(s). |
| **A13** | Shoha (6♣) semantics | Encoded: unbeatable as a *beating* card and beats anything; when part of a *lead* onto an empty table it is an ordinary 6♣ (beatable by higher club or any trump). If 6♣ ends up as the "most recent set" mid-chain (it was used to beat), the next player **cannot beat that card** and must decline against it — i.e., a set containing shoha ends the chain for that card. |
| **A14** | Timeout defaults | 30 s per action; timeout ⇒ server auto-acts (auto-lead lowest non-trump card; auto-decline discarding lowest-point cards). Configurable per room later. |

---

## 1. Project structure (TypeScript monorepo)

npm workspaces (Turborepo optional but nice for caching). The **rules engine is a pure package with zero Colyseus dependencies** — this is the single most important structural decision: it makes the engine unit-testable, reusable by bots, and portable.

```
goat/
├── package.json                  # workspaces: ["packages/*"]
├── turbo.json                    # optional
├── packages/
│   ├── shared/                   # @goat/shared — protocol contract & constants
│   │   └── src/
│   │       ├── cards.ts          # Card encoding (uint8 0..35), suits, RANK_ORDER, CARD_POINTS
│   │       ├── protocol.ts       # message type names + payload TypeScript types (single source of truth)
│   │       ├── enums.ts          # Phase, DeclineReason, ErrorCode, AchievementId, EmojiId
│   │       └── roomOptions.ts    # CreateRoomOptions type (playerCount, scoreLimit)
│   ├── engine/                   # @goat/engine — pure deterministic rules (no I/O, no Colyseus)
│   │   └── src/
│   │       ├── deck.ts           # build/shuffle (injectable RNG for tests)
│   │       ├── deal.ts           # dealing, trump reveal, stock management (A1/A2/A6)
│   │       ├── trick.ts          # lead validation, beat validation (A5), decline, chain (A3/A4)
│   │       ├── scoring.ts        # 120-point count, penalty table, x2/x3 multipliers, goat checks (A10–A12)
│   │       ├── autoplay.ts       # timeout default actions (A14) — future bot baseline
│   │       └── engine.ts         # GoatEngine: applyAction(state, action) -> events | ValidationError
│   ├── server/                   # @goat/server — Colyseus app
│   │   └── src/
│   │       ├── index.ts          # defineServer(), rooms, HTTP routes, /health
│   │       ├── rooms/GoatRoom.ts
│   │       ├── rooms/schema/     # GoatState, PlayerState, ThrowSet (@colyseus/schema)
│   │       ├── auth/             # guest JWT issuing + onAuth verification
│   │       ├── meta/             # achievements.ts, stats.ts, repositories (Postgres)
│   │       └── infra/            # db.ts (pg), redis.ts, rateLimit.ts, config.ts
│   └── web/                      # (future) web client — consumes @goat/shared directly
└── docker/                       # Dockerfile, compose.dev.yml (pg + redis)
```

**Flutter and the shared package (flagged decision):** Dart cannot import a TS package. `@goat/shared/protocol.ts` is the canonical contract; generate the Dart mirror with a small codegen step (e.g., quicktype from JSON-Schema emitted by `ts-json-schema-generator`, run in CI so drift fails the build). Card encoding (`uint8 0..35`, `id = suit*9 + rankIndex`) is trivial to mirror by hand and unit-test on both sides against a shared fixture file (`shared/fixtures/cards.json`).

---

## 2. GoatRoom schema & private state

### 2.1 Visibility matrix

| Data | Owner sees | Others see | Mechanism |
|---|---|---|---|
| Own hand contents | ✅ | ❌ (count only) | `@view()` field + `StateView` per client |
| Opponents' hand **counts** | — | ✅ always | plain public `handCount` field (product requirement) |
| Face-down decline discards | ❌ (even discarder, after playing) | ❌ | **never enters the schema at all** — server-private memory; only a public counter syncs |
| Won-pile contents | ✅ (reviewable) | ❌ (count only) | `@view()` field |
| Table face-up cards, trump, scores, timers | ✅ | ✅ | plain public fields |

The golden rule for card games: **anything secret must never be serialized to the wrong client** — filtering at render time is not security. StateView filters at the *encoder* level, and the face-down discards go one step further: they never live in synced state at all, so no serializer bug can ever leak them.

### 2.2 Schema classes (`@colyseus/schema` 3.x)

Cards are `uint8` ids (0–35), not Schema objects — smaller patches, simpler equality.

```ts
import { Schema, ArraySchema, MapSchema, type, view } from "@colyseus/schema";

export class PlayerState extends Schema {
  @type("string") playerId: string;      // stable identity (not sessionId!)
  @type("string") nickname: string;
  @type("uint8")  seat: number;
  @type("boolean") ready = false;
  @type("boolean") connected = true;
  @type("uint8")  handCount = 0;         // PUBLIC — product requirement
  @type("uint8")  wonCount = 0;          // PUBLIC count of cards taken (A9)
  @type("uint8")  gameScore = 0;         // PUBLIC running penalty score
  @type("boolean") isAutopilot = false;  // seat abandoned → engine plays defaults

  // Owner-only fields — synced ONLY to clients whose StateView contains this instance:
  @view() @type(["uint8"]) hand    = new ArraySchema<number>();
  @view() @type(["uint8"]) wonPile = new ArraySchema<number>();
}

export class ThrowSet extends Schema {
  @type("uint8") bySeat: number;
  @type(["uint8"]) cards = new ArraySchema<number>(); // face-up only
}

export class GoatState extends Schema {
  @type("string") phase: "lobby"|"trick"|"replenish"|"dealEnd"|"gameEnd" = "lobby";
  @type({ map: PlayerState }) players = new MapSchema<PlayerState>(); // key = playerId
  @type("uint8")  targetPlayers = 4;       // 2|3|4|6
  @type("uint8")  scoreLimit = 24;         // 24|36
  @type("uint8")  hostSeat = 0;
  @type("uint8")  dealerSeat = 0;
  @type("uint8")  trumpSuit = 255;         // 255 = none
  @type("uint8")  trumpCardShown = 255;    // currently revealed trump card id (UX)
  @type("uint8")  stockCount = 0;
  @type("uint8")  dealMultiplier = 1;      // 1 | 2 | 3 (set at deal start)
  @type([ThrowSet]) table = new ArraySchema<ThrowSet>(); // ordered sets this trick
  @type("uint8")  tableFaceDownCount = 0;  // counter only — contents never synced
  @type("uint8")  leaderSeat = 255;
  @type("uint8")  turnSeat = 255;
  @type("float64") turnDeadline = 0;       // epoch ms — client renders countdown
}
```

### 2.3 Wiring StateViews

```ts
export class GoatRoom extends Room<{ state: GoatState }> {
  state = new GoatState();

  // Server-private, NEVER synced:
  private secret = {
    stock: [] as number[],                       // ordered deck remainder
    faceDownOnTable: [] as number[],             // decline discards this trick
    hands: new Map<string, Set<number>>(),       // authoritative hand copies
  };

  async onAuth(client, options) {
    return verifyGuestJwt(options.token);        // -> { playerId, nickname }
  }

  onJoin(client, options, auth) {
    const p = this.state.players.get(auth.playerId) ?? this.createPlayer(auth);
    client.view = new StateView();
    client.view.add(p);   // exposes ONLY this player's @view() fields (hand, wonPile) to this client
    // note: view.add(p) reveals the @view-tagged fields of p; public fields of every
    // PlayerState are synced to everyone regardless — exactly the matrix above.
  }
}
```

**Why this beats per-client messages for hands:** views ride the normal delta-patch pipeline, so reconnection automatically re-sends the correct filtered snapshot — no bespoke "resend my hand" logic. Per-client `client.send()` is still used for *transient* things (errors, reactions, deal-end reveal fanfare data). One caveat from the docs: each `StateView` adds an encoding step per client; with ≤6 clients per room this is negligible.

**0.16 fallback:** identical — StateView shipped in 0.16; only the `Room` generic and lifecycle names differ.

---

## 3. Room lifecycle

### 3.1 Registration & lobby

```ts
// index.ts (0.17 style)
const server = defineServer({
  rooms: {
    goat:  defineRoom(GoatRoom, { filterBy: ["targetPlayers", "scoreLimit"] }),
    lobby: defineRoom(LobbyRoom),   // built-in realtime room listing
  },
});
```

- **Browse:** clients join the built-in `LobbyRoom` to receive realtime add/remove/update of listed `goat` rooms. Rooms publish `setMetadata({ name, hostNickname, targetPlayers, scoreLimit, seatsTaken, phase })` so lobby cards can render without joining. Set `state.phase` changes → update metadata.
- **Create:** `client.create("goat", { targetPlayers: 4, scoreLimit: 24, name, token })`. Server clamps/validates options (`targetPlayers ∈ {2,3,4,6}`, `scoreLimit ∈ {24,36}`).
- **Quick join:** `client.joinOrCreate("goat", { targetPlayers?, scoreLimit?, token })` — `filterBy` matches an open room with same options; omitted filters = "any". 
- **Lock:** `this.lock()` when seats are full **or** when the game starts (started games must never appear joinable); `unlock()` if someone leaves pre-start.

### 3.2 Seats, ready-up, host

- `maxClients = targetPlayers`. Seats assigned in join order; `swapSeat` allowed pre-start (host-mediated or free-pick of empty seats).
- Every non-host must send `ready`. Host (creator; migrates to lowest seat if host leaves pre-start) gets: `startGame` (enabled when all ready), `kick(seat)` (pre-start only), `updateOptions` (pre-start only, resets everyone's ready).
- Optional auto-start when full + all ready (recommended for "quick join" UX: 5-second countdown, host can cancel).

### 3.3 Reconnection (0.17 flow)

```ts
async onDrop(client) {                       // abnormal disconnect only (0.17)
  const p = this.playerOf(client);
  p.connected = false;
  if (this.state.phase === "lobby") return this.removeFromLobby(p);
  try {
    await this.allowReconnection(client, 120);   // 120s window mid-game
    p.connected = true;                          // StateView re-attaches automatically;
                                                 // full filtered snapshot re-sent by Colyseus
  } catch {
    p.isAutopilot = true;                        // seat survives, engine plays A14 defaults
    this.checkAbandonment();
  }
}
onLeave(client, code) {                      // consented .leave() mid-game = surrender
  const p = this.playerOf(client);
  if (this.state.phase !== "lobby") { p.connected = false; p.isAutopilot = true; this.checkAbandonment(); }
  else this.removeFromLobby(p);
}
```

- **Token:** Flutter client persists `room.reconnectionToken` (+ roomId) to local storage after every (re)connect — the token changes on each reconnection, always store the latest. On app relaunch within the window: `client.reconnect(cachedToken)`. (0.17 SDKs also auto-reconnect transparently on transient drops; the cached-token path covers app restarts.)
- **Turn timers do not pause** for disconnected players (protects the other 1–5 humans); their turns are auto-played by `autoplay.ts`. Reconnecting flips `isAutopilot` off before their next turn.
- **Rejoin identity** is `playerId` (from JWT), not sessionId — a player who exhausted the window can still late-rejoin via a normal `joinById` if the room admits them back to their autopilot seat (nice-to-have; v1 can skip).

### 3.4 Abandonment

`checkAbandonment()`: if **all** seats are autopilot/disconnected → dispose immediately (no stats written, match voided). If ≥1 human remains → play to completion with autopilots (humans get their earned result; autopilot seats record a "abandoned" stat, feeding achievement #10 below). `autoDispose = true` handles the empty-room case as backstop.

### 3.5 Spectators — recommendation: **NO in v1**

The StateView design makes spectators trivially safe later (join a spectator seat, `client.view` with *no* players added ⇒ they see only public state — exactly what a fair spectator should see). But they add lobby UI, seat-vs-spectator flows, and reaction-abuse surface. Defer; the architecture already supports it. Flagged as a v1.x candidate.

---

## 4. Message protocol

All secret-bearing or authoritative data flows via **state patches**; commands are **intents** that the engine validates. Message names & payload types live in `@goat/shared/protocol.ts`.

### 4.1 Client → Server commands

| Message | Payload | Valid phase | Notes |
|---|---|---|---|
| `ready` | `{ ready: boolean }` | lobby | |
| `start_game` | `{}` | lobby | host only, all ready |
| `update_options` | `{ targetPlayers?, scoreLimit?, name? }` | lobby | host only |
| `kick` | `{ seat: number }` | lobby | host only |
| `lead` | `{ cards: number[] }` | trick, `turnSeat`=you, empty table | 1+ cards, all same rank OR all same suit, all in hand |
| `beat` | `{ pairs: { target: number; card: number }[] }` | trick, `turnSeat`=you, table non-empty | pairing chosen by defender (A5); every target of most recent set covered exactly once; each `card` legally beats its `target` (same suit higher rank / trump over non-trump / shoha over anything); shoha targets unbeatable (A13) |
| `decline` | `{ discards: number[] }` | trick, `turnSeat`=you | count = size of most recent set (or entire hand per A4); cards in hand; contents go to `secret.faceDownOnTable`, only counter syncs |
| `emote` | `{ emoji: EmojiId }` | any | §7, rate-limited |
| `ping` | `{ t: number }` | any | RTT probe (§5) |

Every command gets an **ack or error reply** via `client.send("cmd_result", { reqId, ok, error? })` — clients attach a `reqId` so optimistic UI can reconcile (§5). Error codes: `NOT_YOUR_TURN`, `CARD_NOT_IN_HAND`, `INVALID_SET`, `PAIR_DOESNT_BEAT`, `WRONG_COUNT`, `BAD_PHASE`, `RATE_LIMITED`, `NOT_HOST`.

### 4.2 Server → Client events

State patches carry the durable truth; discrete events exist for **animation choreography** (things patches express poorly — order, cause, fanfare):

| Event | Payload | Broadcast/targeted |
|---|---|---|
| `deal_started` | `{ dealNo, dealerSeat, trumpCard, multiplier, tripleGame: boolean }` | broadcast |
| `cards_dealt` | — (hands arrive via filtered patch) | patch only |
| `led` | `{ seat, cards: number[] }` | broadcast |
| `beaten` | `{ seat, pairs }` | broadcast (drives beat animation card-onto-card) |
| `declined` | `{ seat, count }` | broadcast — **count only, never contents** |
| `trick_taken` | `{ bySeat, faceUpCards: number[], faceDownCount }` | broadcast (cards fly to winner; face-down fly as backs) |
| `card_drawn` | `{ seat }` / `{ seat, card }` | broadcast card-back for others; the drawn card reaches the owner via hand patch |
| `trump_changed` | `{ card, suit, bySeat }` | broadcast (A2 reveal moment — hero animation) |
| `deal_ended` | `{ perSeat: { cardPoints, penaltyAdded, wonPileReveal: number[] }[], multiplier }` | broadcast — full reveal is fine at deal end |
| `game_ended` | `{ goatSeats: number[], finalScores, instantGoat: boolean }` | broadcast |
| `turn_started` | `{ seat, deadline, mustCover: number }` | broadcast (also in state; event triggers timer ring animation) |
| `player_dropped` / `player_reconnected` / `autopilot_on` | `{ seat }` | broadcast |
| `reaction` | `{ seat, emoji }` | broadcast, transient (§7) |
| `cmd_result` | `{ reqId, ok, error? }` | targeted |
| `pong` | `{ t }` | targeted |

### 4.3 Authoritative validation flow

```
client: send("beat", payload, reqId)  ── optimistic animation starts
server: GoatRoom.onMessage → rateLimit → GoatEngine.applyAction(secretState, action)
        ├─ invalid → client.send("cmd_result", {reqId, ok:false, error}) → client rolls back
        └─ valid   → mutate schema (public + view fields) + broadcast discrete event
                     → Colyseus encodes per-view deltas at next patch tick
                     → arm next turn timer (clock.setTimeout)
```

The engine is the only mutator; `GoatRoom` is a thin adapter mapping engine events → schema mutations + broadcasts. Turn timer: `this.clock.setTimeout(30_000)` armed on every `turn_started`; on fire, engine executes the A14 default action for `turnSeat` and the flow proceeds identically to a client command.

---

## 5. Latency strategy

A turn-based card game doesn't need rollback netcode — it needs **perceived** instantaneity:

1. **Optimistic UI (client contract, designed here):** the moment the local player taps a legal-looking move, animate it (card slides to table) and send the intent with `reqId`. The server ack usually arrives mid-animation; on `ok:false` play a short "bounce back" animation. The client can pre-validate with the mirrored rules (from the shared contract) so rejections are near-zero in practice — server remains the authority.
2. **Discrete events are immediate:** `broadcast()`/`send()` bypass the patch interval — opponents see `led`/`beaten` animations without waiting for the next patch tick. State patches then confirm.
3. **Patch rate:** default 50 ms (`patchRate: 50`) is already overkill for cards; keep it — it costs almost nothing because…
4. **Tiny binary deltas:** schema encoding sends only changed fields; a typical move delta (a few uint8 array ops + turnSeat + deadline) is **tens of bytes**. Using `uint8` card ids instead of nested Card schemas keeps arrays cheap.
5. **Regional deployment:** single region **as close to the player base as possible** (for a Russian-speaking audience: a Frankfurt/Warsaw/Almaty VPS or Colyseus Cloud EU region — flagged: confirm audience geography). One region is correct for v1; card-game tolerance for 80–150 ms RTT is high, but reactions/animations feel best under 100 ms.
6. **RTT measurement:** client `ping`→`pong` every 5 s; show connection quality dot; use measured RTT to pad the rendered turn-timer so the local countdown never appears to expire before the server's.
7. **WebSocket keepalive:** rely on Colyseus pingInterval defaults for dead-connection detection (feeds `onDrop` quickly).

**Rate limiting & anti-cheat:**
- Per-client token bucket in-room: game commands 5/s (humans can't exceed this), `emote` per §7, `ping` 1/2s. Excess → `RATE_LIMITED`, repeated abuse → disconnect with error code.
- HTTP matchmaking endpoints behind reverse-proxy rate limit (e.g., 10 req/min/IP on create).
- **Why authoritative + view-filtered closes most cheats:** clients never *receive* opponents' hands, stock order, or face-down discards — a hacked client has nothing to peek at (the #1 card-game cheat class). Illegal moves are impossible (engine validates everything). Shuffle uses server-side CSPRNG (`crypto.randomInt` Fisher–Yates). Remaining threat is **collusion** (two humans sharing screens off-band) — unsolvable technically; mitigate later with report/matchmaking-trust features. Also never log secret state at info level.

---

## 6. Persistence & meta

### 6.1 Stack

- **Postgres** (managed or Docker): durable meta — players, stats, achievements, match history. One small DB, `pg` + a thin repository layer (no ORM needed at this size; Drizzle if preferred).
- **Redis**: (a) Colyseus **driver + presence** when scaling beyond one process (not required day 1, but wiring the config behind env flags now is free), (b) matchmaking-adjacent counters, (c) rate-limit state if it ever needs to be cross-process. V1 can run without Redis; include it in docker-compose from the start so the scale path is a config change.

### 6.2 Identity: guest-first

1. First launch: Flutter generates a device UUID → `POST /auth/guest { deviceId, nickname }` → server upserts `players` row, returns a **signed JWT** `{ playerId, nickname }` (long-lived, refreshable).
2. `onAuth` verifies the JWT — no DB hit on the hot path.
3. **Account upgrade later:** add `auth_providers(player_id, provider, provider_uid)`; Sign in with Apple/Google merges onto the same `player_id`, so guest progress survives. Nothing else changes.

```sql
players(id uuid pk, device_id text unique, nickname text, created_at, last_seen_at)
player_stats(player_id pk, games_played int, games_won int, goats int, deals_played int,
             tricks_taken int, shoha_kills int, triple_games_won int, best_deal_points int,
             instant_goats_inflicted int, reconnect_wins int, abandons int)
achievements(player_id, achievement_id text, unlocked_at, primary key(player_id, achievement_id))
matches(id, room_options jsonb, started_at, ended_at, result jsonb)   -- result: per-player scores/goat
```

### 6.3 Hook points

- `GoatRoom` emits domain events (`dealEnded`, `gameEnded`, `trickTaken`, …) to a `MetaService` (in-process, fire-and-forget with retry queue — **never block the game loop on the DB**).
- `gameEnded` → transaction: update `player_stats`, insert `matches`, evaluate achievements; newly unlocked achievements pushed back to the room → `client.send("achievement_unlocked", { id })` for an in-game toast.

### 6.4 Achievement definitions (v1, ~10, humorous EN/RU)

| id | Trigger | EN title | RU title |
|---|---|---|---|
| `first_win` | first game survived (not goat) | **Not the Goat Today** | «Сегодня не козёл» |
| `wins_10` | 10 wins | **Herd Leader** | «Вожак стада» |
| `wins_100` | 100 wins | **The Goatfather** | «Крёстный козёл» |
| `shoha_ace` | beat a trump Ace with the 6♣ | **Shoha Says No** | «Шоха всему голова» |
| `dry_deal` | opponent takes zero cards in a deal you scored best in | **Squeaky Clean** | «Всухую» |
| `full_120` | take all 120 points in one deal | **Greedy Hooves** | «Хапуга» |
| `triple_win` | best score in a triple game deal | **Triple Trouble** | «Тройная угроза» |
| `exact_24` | become goat with exactly the limit | **Certified Goat** | «Дипломированный козёл» |
| `instant_goat` | lose via the 12-vs-0 instant rule | **Speedrun Goat** | «Козёл-скороход» |
| `comeback_win` | win a game in which you reconnected mid-game | **The Prodigal Goat** | «Блудный козёл» |
| `games_100` | play 100 games | **Barn Regular** | «Завсегдатай хлева» |
| `streak_5` | 5 wins in a row | **Hot Hooves** | «Горячие копыта» |

(RU titles are idea-level; a native review pass is recommended — flagged.)

---

## 7. Emoji reactions

- **Transient, never in schema:** `onMessage("emote")` → validate `emoji ∈ EMOJI_SET` (server-defined enum of ~12 ids: 👍😂😱🐐🔥😭🤔👏😴🫠🎉😈 — clients render their own art per id, enabling animated stickers without protocol changes) → `broadcast("reaction", { seat, emoji })`. No persistence, no reconnection replay (a reconnecting player missing a 3-second emoji is correct behavior).
- **Rate limit:** per-player token bucket — **burst 3, refill 1 per 2 s**; on exceed, silently drop + targeted `cmd_result RATE_LIMITED` (client greys the emoji tray with a cooldown ring — pleasant, not punitive). Hard cap 30/min → escalate to a 60 s mute for that player.
- Client renders reactions as a bubble over the sender's avatar, auto-dismissing; multiple reactions queue, never stack unbounded.

---

## 8. Future-proofing hooks

### 8.1 Bots
- The seams already exist: (a) the **pure engine** with `applyAction` + full server-side state view, (b) `isAutopilot` seats with `autoplay.ts` (a degenerate bot). 
- Formalize now (interfaces only, ~1 hour): `interface BotStrategy { chooseAction(view: BotView): GoatAction }` where `BotView` exposes exactly what a human at that seat may know (own hand, public state) — **bots must not see secrets either**, both for fairness and so strategies stay honest. A `SeatDriver` abstraction (`HumanDriver | BotDriver`) in GoatRoom means "fill with bot" is a lobby button later, not a refactor. Bots run in-process on `clock.setTimeout` with a humanizing 600–1500 ms think delay.

### 8.2 Voice chat
- **Recommendation: LiveKit (WebRTC SFU)** — self-hostable, has Flutter and JS SDKs, scales independently of game servers; do **not** route audio through Colyseus/Node. Alternative if ops budget is zero: LiveKit Cloud.
- **Stub now:** (a) `voiceRoomName = roomId` convention, (b) an empty `POST /voice/token` endpoint shape (playerId + roomId → LiveKit JWT) returning 501, (c) a `voiceEnabled: false` flag in room metadata. That's the entire integration surface later.

### 8.3 Web client
- Colyseus JS SDK speaks the identical protocol — the web build is either Flutter Web (same Dart SDK; verify its WebSocket transport on web) or a separate TS client that imports `@goat/shared` directly (a hidden payoff of the monorepo). No server changes needed. Keep all client-bound payloads platform-neutral (numbers/strings, no platform-specific blobs) — already true above.

---

## 9. Deployment

**Dev:** `docker-compose.dev.yml` = Postgres + Redis; server via `tsx watch` on the host for fast iteration; `@colyseus/playground` + monitor panel enabled in dev only (auth-gated or disabled in prod). Seed script creates test guests; engine has an offline simulator CLI (`packages/engine`) to fuzz thousands of random deals against invariants (Σpoints = 120, hand counts, phase machine) — cheap and catches rule bugs early.

**Production v1:**
- **Single region, single node** (see §5 for region choice): a 2-vCPU VPS or Colyseus Cloud. Colyseus is single-process-per-CPU; each room is cheap (6 players, patch deltas of bytes) — one node handles **hundreds of concurrent rooms** comfortably.
- **Docker:** multi-stage build (workspace install → `tsc` → slim `node:20-alpine` runtime), non-root user, `NODE_ENV=production`.
- **TLS/WSS:** terminate at Caddy/Nginx/Traefik in front; WebSocket upgrade passthrough; HTTP rate limits here.
- **Health:** `GET /health` (returns process + pg + redis status) wired to Docker healthcheck and uptime monitoring; **graceful shutdown** on SIGTERM — Colyseus's shutdown flow lets rooms notify clients (0.17 adds `CloseCode.SERVER_SHUTDOWN`); clients treat it as a reconnect-after-deploy signal (with reconnection tokens, a deploy mid-game is survivable if you drain: stop accepting new rooms, let games finish — add a `maintenance` flag honored by matchmaking).
- **Scale path (documented, not built):** multiple processes/machines ⇒ enable Redis **presence + driver** (env flag), sticky routing by room (Colyseus seat reservation handles this), LobbyRoom keeps working across processes. Nothing in this design blocks it.
- **Observability:** pino structured logs (never log hands/stock), basic metrics (rooms active, msgs/s, patch bytes/s, p95 command→ack) via Prometheus endpoint.

---

## Appendix: open questions for the human (consolidated)

1. Confirm assumptions **A1–A14** (§0) — especially A2 (trump rotation = last card of each replenishment round), A3/A4 (wrapping beat-chain & short-hand decline), A6 (6-player trump).
2. Audience geography → deployment region (§5.5).
3. Dart SDK protocol version check → pin server to 0.17 or 0.16 (§ preamble).
4. Native-speaker pass on RU achievement titles (§6.4).
5. Spectators deferred to v1.x — approve (§3.5).

Sources: [Colyseus 0.17 is here!](https://colyseus.io/blog/colyseus-017-is-here/), [Migrating to 0.17](https://docs.colyseus.io/migrating/0.17), [State View docs](https://docs.colyseus.io/state/view), [Colyseus 0.16 is here!](https://colyseus.io/blog/colyseus-016-is-here/), [Reconnection docs](https://docs.colyseus.io/room/reconnection), [Rooms docs](https://docs.colyseus.io/room), [reconnectionToken discussion](https://github.com/orgs/colyseus/discussions/595)