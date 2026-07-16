# Goat (Козёл) — Flutter Client Design Document

**Version:** 0.1 (design) · **Date:** 2026-07-16 · **Scope:** Flutter client for Android + iOS (web later), against an authoritative Colyseus (TypeScript) server.

---

## 0. Executive summary of key decisions

| Topic | Decision |
|---|---|
| Colyseus Dart SDK | **Do not use any existing Dart package — none exists in maintained form. Write a thin custom client** that speaks Colyseus matchmaking + WebSocket framing, and **bypass `@colyseus/schema` binary state sync entirely** in favor of explicit server-sent messages (snapshot + events). |
| State management | **Riverpod** (v3, code-gen Notifiers) + **freezed** immutable models. |
| Navigation | `go_router`. |
| Legal moves | **Server sends precomputed legal actions with every turn state**; client keeps only a trivial pure Dart selection validator for multi-select UX. Shared JSON test vectors mitigate duplication. |
| Orientation | **Portrait-only for v1** (landscape architecturally anticipated). |
| Animations | Explicit `AnimationController` flights in an overlay layer, custom curves with seeded randomness; **Rive** for the goat mascot and the shoha effect; no spritesheets. Budget: 60 fps floor, 120 fps target. |
| Card assets | Custom 36-card **vector** set (commissioned, Russian-deck styling), pre-rasterized per device pixel ratio at startup; themeable backs/felt. |
| Optimism | Optimistic **only** for playing own cards (visual lift + flight starts immediately); everything else server-confirmed. Rollback = animated return to hand. |

---

## 1. Colyseus Dart/Flutter client — verification and recommendation

### 1.1 What the research shows (July 2026)

- **There is no official Colyseus SDK for Dart/Flutter.** The official SDK list covers TypeScript/JS, React, Unity, MonoGame, Godot, Defold, Construct 3, GameMaker, Cocos Creator, Haxe, a native C SDK, Discord Activities and WeChat — Dart is absent.
- The long-standing feature request, [colyseus/colyseus issue #248 "Flutter (Dart) Client Support"](https://github.com/colyseus/colyseus/issues/248) (opened 2019), is **closed as Stale** with no linked implementation and no activity in 2023–2026.
- **pub.dev has no Colyseus package at all.** A search for "colyseus" on pub.dev returns a single false positive (`polyseed`, a Monero seed library). Historical community experiments (`colyseus_dart` and similar hobby ports) are not published, not maintained, and targeted very old protocol versions.
- Critically, the **schema wire protocol keeps evolving**: Colyseus 0.16 moved to `@colyseus/schema` v3 (a breaking re-encode) and 0.17 moved to v4.0.x. Every official client decoder (C#, Haxe, Lua…) had to be rewritten in lockstep. Any abandoned Dart port therefore cannot decode a modern server's state stream — it is not "slightly stale", it is *incompatible*.

Sources: [Colyseus Client SDKs](https://docs.colyseus.io/sdk) · [colyseus/colyseus#248](https://github.com/colyseus/colyseus/issues/248) · [colyseus/schema](https://github.com/colyseus/schema) · [Colyseus 0.17 announcement](https://colyseus.io/blog/colyseus-017-is-here/) · [Migrating to 0.17](https://docs.colyseus.io/migrating/0.17) · [Colyseus 0.16 announcement](https://colyseus.io/blog/colyseus-016-is-here/) · [Colyseus framework page](https://colyseus.io/framework/) · [pub.dev search](https://pub.dev/packages?q=colyseus) · [Colyseus forum: Dart client](https://discuss.colyseus.io/topic/392/is-colyseus-support-dart-lang-client)

### 1.2 Firm recommendation

**Write our own thin Dart client, and do not use `@colyseus/schema` state sync at all.** Concretely:

1. **Reimplement the Colyseus matchmaking handshake** (small, stable HTTP surface): `POST /matchmake/joinOrCreate/{roomName}`, `/join`, `/create`, `/reconnect` → seat reservation `{room, sessionId, reconnectionToken}` → WebSocket connect with the reservation. ~150 LOC.
2. **Speak the Colyseus WS envelope** (protocol byte + MessagePack body): `JOIN_ROOM`, `ERROR`, `LEAVE_ROOM`, `ROOM_DATA`, `PING`/`PONG`. We deliberately **ignore `ROOM_STATE` / `ROOM_STATE_PATCH`** — the server keeps its Colyseus schema state minimal/empty and communicates via `room.send()` / `client.send()` typed messages. MessagePack via `msgpack_dart`. ~300–400 LOC total for the transport.
3. **Application protocol = snapshot + semantic events** (Section 2.4), designed by us, versioned by us.

Why this is the right call, firmly:

- **Porting the schema v4 decoder to Dart is weeks of work plus a permanent maintenance treadmill** tracking upstream protocol changes we don't control. A thin transport client tracks a surface that has been stable for years.
- **A card game is a hidden-information game.** Opponents' hands must never reach the client. Schema sync would force us into `StateView`/filtering machinery; explicit per-client messages give us hidden information *by construction* and are trivially auditable.
- We **keep everything Colyseus is actually good at**: room lifecycle, matchmaking, seat reservations, reconnection tokens, presence, scaling — all server-side, unaffected.
- Bonus: the same message protocol works verbatim for the future **web build** (the JS client can also ignore schema) and for **bots** (server-side, no client needed).

Risk accepted: we lose automatic delta-sync and must design resync ourselves (sequence numbers + snapshot-on-gap, Section 2.4). For a game whose entire state is a few hundred bytes, this is a non-problem.

---

## 2. App architecture

### 2.1 State management: Riverpod (chosen over Bloc)

- **Fine-grained reactive selectors.** A game table has ~15 independently-updating regions (each seat, trick area, timer, stock, score strip). `ref.watch(provider.select(...))` gives per-widget rebuild granularity without writing 15 Blocs or `buildWhen` boilerplate — directly serves the 60/120 fps goal.
- **No context needed** — the connection layer and reducers live outside the widget tree; providers compose (e.g. `legalActionsProvider` derives from `gameStateProvider` + `selectedCardsProvider`).
- Compile-safe DI makes **fake connections trivial to inject in tests** (Section 9).
- Bloc's event/state ceremony duplicates what our server protocol already is (events in → state out). We put the reducer in plain Dart and let Riverpod expose it.

Models are **freezed** immutable data classes; game state updates are `state = reducer(state, event)`.

### 2.2 Project structure (feature-first)

```
lib/
  core/
    net/            # ColyseusTransport: matchmake HTTP, WS envelope, ping, reconnect
    protocol/       # generated message types (see 2.4), ServerEvent, ClientIntent
    game/           # pure Dart: ClientGameState, reducer, selection validator, card model
    services/       # audio, haptics, prefs, analytics
  features/
    auth/           # nickname/guest
    lobby/          # room list, create, quick join
    game/           # table screen, seats, hand, trick area, animations layer
    scoreboard/     # deal-end + game-end (goat)
    achievements/
    settings/
  shared/
    cards/          # CardFace/CardBack widgets, asset cache
    widgets/        # buttons, sheets, avatars, timer ring
    theme/
```

`core/game` and `core/protocol` are **pure Dart packages** (no Flutter imports) → unit-testable at high speed and reusable for a future desktop/web shell.

### 2.3 Navigation

`go_router`: `/splash → /login → /lobby → /room/:id (table) → overlays (deal-end, game-end) → /achievements, /settings`. Deal-end and game-end are **route-less overlays on the table screen** (state-driven), so reconnection into any phase lands on `/room/:id` and renders the correct overlay. Deep link `goat://room/:id` reserved for invite links (post-v1).

### 2.4 Server → client state mapping

**Protocol shape** (all messages carry `seq`, a per-room monotonic counter, and `protoVersion`):

- `Snapshot` — full personal view: phase, seats (nickname, cardCount, score, wonPileCount, connected), own hand, table trick (attack/beat pairs, face-down markers), trump card + suit, stock count, turn owner + deadline, legal actions, deal multiplier (x1/x2/x3). Sent on join, reconnect, and on any `seq` gap (client requests `resync`).
- `Event` — semantic deltas: `dealStarted`, `cardsDealt`, `trumpRevealed`, `cardPlayed`, `cardsBeaten`, `declined`, `trickTaken`, `drawn`, `newTrump`, `dealEnded(scoring)`, `gameEnded(goatSeat)`, `reaction`, `playerConnected/Disconnected`, `achievementUnlocked`.
- `Client → server`: `Intent` messages (`lead(cards[], actionId)`, `beat(pairs[], actionId)`, `decline(discards[], actionId)`, `react(emojiId)`, `peekAck`), answered by `IntentAccepted(actionId)` or `IntentRejected(actionId, reason)`.

**Client pipeline:** `ColyseusTransport` → decoded `ServerEvent` stream → `GameController (Notifier)` applies the **pure reducer** → `ClientGameState` → widgets watch slices. Events also fan out to an `AnimationDirector` (Section 5.1) *before* the state commit, so flights can play against the pre-event layout and settle into the post-event layout.

**Contract source of truth:** message types defined once as TypeScript types + JSON Schema in the server repo; Dart classes generated (quicktype or a small custom generator) in CI. A contract test (Section 9.4) round-trips golden payloads through both codecs.

### 2.5 Legal-move affordances: server-sent (recommended)

**Decision: the server precomputes and sends legal actions with every turn state.** The engine is TypeScript; re-implementing beat legality (trump, ten-above-king, shoha's dual behavior, multi-card pairing) in Dart doubles the rule surface and guarantees drift exactly where bugs are most embarrassing.

Payload is compact and arrives *with* the turn notification, so there is **zero added latency**:

- On your **lead**: `leadable: { byRank: {rank → cardIds[]}, bySuit: {suit → cardIds[]} }` (every singleton is always legal).
- On your **beat**: `beatMap: { attackCardId → beatingHandCardIds[] }` plus `canDecline: true`. The client can derive everything: which hand cards light up, whether a full cover exists, valid pairings during drag.
- On **decline**: any N hand cards are legal discards — no data needed.

**The only rule logic kept client-side** is the multi-select *shape* validator ("selection is same-rank OR same-suit") for instant selection feedback — five lines of stable, rulebook-level Dart.

**Duplication mitigation:** shared JSON test vectors (`state → expected legal actions`) generated from the TS engine's test suite, replayed against the Dart selection validator and against recorded `beatMap`s in CI. If rules evolve, vectors fail loudly on whichever side lags.

---

## 3. Screens & flows

### 3.1 Splash
Dark felt-green backdrop, goat mascot mark (Rive idle blink), app name in a slab-serif. Preloads: card raster cache, Rive files, audio, prefs, silent session restore. Max 1.5 s; progress shown only if slower (thin bar).

### 3.2 Login (nickname / guest)
Single card-panel: avatar picker (12 flat goat/farm-animal avatars), nickname field (3–16 chars, profanity filter server-side), primary button "Играть" (Play as guest). Guest identity = device-generated ID + nickname, stored locally; the panel reserves a slot for "Sign in" buttons later (architecture: `AuthRepository` interface with `GuestAuth` impl). On success → lobby.

### 3.3 Lobby
- **Top bar:** avatar+nickname (tap → profile/achievements), settings gear, connection/latency chip.
- **Hero action:** big "Быстрая игра" (Quick join) button — joins any open room matching default filters, creates one if none.
- **Room list** (live via a lobby room subscription): each row = room name/host, seats as filled/empty pips ("3/4"), target score badge (24 or 36), status ("waiting" / "in deal 2"), join button. Pull-to-refresh; filters row (players count, score).
- **Create room** — bottom sheet: players (2/3/4/6 segmented control), target score (24/36), turn timer (15/30/45 s), open/friends-only toggle (v1: open only, toggle disabled with "soon" tag). → creates and enters a **waiting room** view: seat circle with joined avatars, ready checkmarks, host "Start" button, room code for sharing.

### 3.4 Game table
Section 4 in full.

### 3.5 Deal-end scoreboard (overlay)
Slides up over the frozen table. Per-player rows: avatar, card-points collected this deal (animated tally, Section 5.6), penalty added (+0/+2/+4/+6) with the bracket label ("под 60" etc.), multiplier stamp if x2/x3 ("Шестёрка! x2" slams onto the panel), running total with progress bar toward 24/36 and a danger zone (last 4 points glow red). Countdown "Next deal in 5…" with "Ready" button to skip collectively.

### 3.6 Game-end: goat reveal
Full-screen moment (Section 5.7): the loser's avatar gets goat horns, Rive goat struts across, "КОЗЁЛ — {nickname}" headline; everyone else gets confetti. Final table of running scores and per-deal history (expandable). Buttons: "Rematch" (votes shown as avatar checkmarks), "Back to lobby". Achievement toasts queue here if earned.

### 3.7 Achievements
Section 7.2.

---

## 4. Game table UX (the heart)

### 4.1 Orientation: portrait, firmly

Card games are held one-handed; the hand fan wants the bottom edge and the thumb arc. Portrait gives a tall table: opponents on the upper arc, trick center-stage, fan at the bottom — matching how people physically hold cards. Landscape would shrink the fan and fight the thumb. **V1 locks portrait**; layout is built from a `SeatLayout` computed by a single `TableGeometry` class so a landscape variant later is a geometry swap, not a rewrite.

### 4.2 Overall vertical composition (portrait)

```
┌──────────────────────────────┐
│ top bar: room · scores strip │  ~6%
│      opponent seats arc      │  ~18%
│                              │
│    TRICK AREA (felt oval)    │  ~34%
│  trump chip     stock stack  │
│                              │
│  status line / turn banner   │  ~5%
│ won-pile · reactions · menu  │  ~7%
│        OWN HAND FAN          │  ~24%
│     action button zone       │  ~6%
└──────────────────────────────┘
```

### 4.3 Seat layouts per player count

Own seat is always bottom-center. Opponents distributed on an arc/edges, always in **true turn order clockwise**, so "who beats next" is spatially obvious:

- **2 players:** opponent top-center, large seat widget. The most spacious layout; trick area grows.
- **3 players:** opponents at top-left and top-right (10 and 2 o'clock).
- **4 players:** left edge (9 o'clock), top-center (12), right edge (3). Side seats rendered vertically compact.
- **6 players:** five opponents on the top arc at 8:30, 10, 12, 2, 3:30 o'clock; seat widgets shrink to compact mode (avatar 40 dp, count badge, name truncated). A directional chevron animates seat-to-seat along the arc showing turn flow.

### 4.4 Opponent seat widget (card counts are a hard requirement)

Each seat: circular avatar with **turn timer ring** (Section 4.9), nickname, running game score chip, and the **hand-count display**: a mini fan of face-down card backs, one per card (max 6, so always exact), plus a numeral badge overlapping the fan ("4"). The fan physically loses/gains cards with animation, so counts are readable at a glance *and* glanceable peripherally. Disconnected players: seat desaturates, plug icon, reconnect countdown. A small **won-pile stack** sits beside each seat with a card-count tick (pile *sizes* are public information; contents are not).

### 4.5 Own hand fan: tap and drag both supported

- Fan of up to 6 cards, arc-rotated, overlapping ~45%; cards are large (min width ~64 dp) — readability beats realism.
- **Tap** a card → it rises 16 dp and highlights (selection). Tap again → deselect. With a valid selection, the **action button** appears ("Зайти" / "Побить" / context-named) — tap-tap-confirm is the precise, error-proof path.
- **Drag** a selected (or single) card toward the trick area → ghost follows finger; the trick area shows a glowing drop zone when the move is legal; release = play. Drag below threshold or onto no-zone → spring back. Fast flick up also plays (velocity threshold) — the "dynamic" path for confident players.
- **Illegal cards are affordance-dimmed** (85% desaturation + slightly sunk) per the server's `beatMap`/`leadable`, never removed. Tapping a dimmed card wiggles it with a subtle "no" haptic and a one-line reason toast ("Nothing on the table this can beat").

### 4.6 Multi-card selection for leads

When leading: first tap selects freely; after the first selection the client's shape validator live-dims cards that would break the "all same rank OR all same suit" invariant *given current selection* (union while both interpretations are alive: e.g., after selecting 9 of spades, other 9s AND other spades stay lit; after adding 9 of hearts, only 9s stay lit). A selection pill above the fan reads "Lead 3 cards: nines". **Long-press a card = select all legal same-rank partners** (power shortcut). Confirm via action button or drag-the-group (selected cards move as a stacked cluster under the finger).

### 4.7 Trick area: attack/beat pairing visualization

- Attack cards land in a **row of slots** across the felt oval, slightly rotated (±4°), in throw order.
- A beating card lands **on top of its attack card**, offset down-right 30% and rotated opposite — the classic "covered" look; an emphatic beat gets the slam effect (Section 5.4). Covered pairs subtly compress and desaturate 10% so the *uncovered* cards visually pop as "still to beat".
- **Defender pairing (flagged assumption A3):** when the defender must cover multiple cards, they drag each chosen card onto a specific uncovered attack card; legal targets glow per `beatMap` while dragging. Tap-mode alternative: tap hand card, then tap target attack card. An "auto-arrange" button appears when only one legal pairing assignment exists.
- The **chain of beats** (player B beat, player C re-beats in 3+ player games — assumption A2) restacks: the newest set is always the uncovered layer; a small stack-depth pip shows how many layers lie beneath.
- **Face-down declines** land as card backs in the trick area (Section 5.5) before the whole pile flies to the taker's won pile.

### 4.8 Trump indicator + stock counter

Top-right of the trick area: the **revealed trump card itself**, half-tucked crosswise under the **stock stack** (assumption A1: drawn last). Stock is a 3D-ish stack whose visual thickness maps to remaining count, with a numeral. When the trump *changes* (last stock card drawn), the flourish plays (Section 5.5) and a persistent **trump suit chip** (suit glyph on colored disc) updates in the top bar — the chip is the always-visible source of truth; also echoed as a subtle suit watermark tint on the felt. When stock is empty: stack disappears, chip remains with a lock icon ("trump fixed").

### 4.9 Turn indicator + timer

- Active player's avatar gets a bright **ring that depletes clockwise** (turn timer). Last 5 s: ring turns amber→red, pulses, gentle tick haptic each second (own turn only).
- Own turn additionally: fan lifts 8 dp, felt edge glows on your side, status banner "Ваш ход — побейте 2 карты".
- Timeout behavior (server rule): auto-decline with random discards; client pre-warns at T-3 s ("Auto-pass in 3…").

### 4.10 Won piles + peek gesture

Own won pile: bottom-left stack. **Long-press to peek** → bottom sheet with a scrollable grid of your won cards grouped by trick, plus live card-points subtotal ("Collected: 38"). Peeking is client-side only (client already knows own pile contents from events); opponents see a small "reviewing pile" eye icon on your seat — flavor, keeps table honest. Opponents' piles show count only; tapping one shows just "Trick count: 3 · cards: 14".

---

## 5. Animation system

### 5.1 Architecture: an AnimationDirector over a card overlay

All card motion happens in a dedicated **overlay layer** above the table (an `OverlayPortal`/`Stack` with a `CardFlightController`). Widgets in layout (seats, fan, trick slots) expose their global rects via a `TableGeometry` registry. The `AnimationDirector` consumes server events *before* state commit, schedules flights from source rect → destination rect, and commits state (making the static widget appear) exactly when the flight lands. This gives frame-perfect handoffs and keeps the layout tree animation-free.

- **Explicit animations** (`AnimationController` + `Tween` + custom curves) for everything airborne: deals, plays, beats, takes, draws.
- **Implicit animations** (`AnimatedPositioned/Scale/Opacity`, `TweenAnimationBuilder`) for in-place layout: fan reflow, selection rise, seat dimming, ring colors.
- **Rive** for two characters only: the goat mascot (splash idle, goat reveal strut, occasional table cameo) and the shoha sigil. **Lottie** optionally for confetti (or a custom `CustomPainter` particle system — cheaper; decide by profiling). **No spritesheets.**

### 5.2 Card flight curves with slight randomness

Every flight is a **quadratic Bezier** whose control point is offset perpendicular to the path by `0.12 × distance × r`, where `r ∈ [−1, 1]` from a per-deal seeded PRNG (seed = dealId + cardId → deterministic, replayable, testable in goldens). Rotation tweens from source angle to slot angle with a ±3° random settle. Timing: 260–340 ms randomized, curve `Curves.easeOutBack` clamped to 1.02 overshoot. Result: no two throws look identical, but motion stays calm.

### 5.3 Dealing

Cards stream from the stock stack to each seat **one at a time in true deal order** (matching the rules' replenish order), 55 ms stagger, each with the Bezier variance; own cards flip face-up mid-flight (3D `Transform` rotateY with a scale dip). Full 6×N deal completes in < 2.5 s; a "skip" tap accelerates stagger to 15 ms (never blocks input on server side). Draw-to-replenish after each trick reuses the same system at 1-per-flight visible speed so players *see* who draws and when the last card comes.

### 5.4 Beat slam

Beating card scales to 1.15 at flight apex, then slams onto the target in 90 ms with: 2 px table shake (whole trick-area transform, 60 ms), a radial dust-ring `CustomPainter` burst (8 particles, 200 ms), `HapticFeedback.mediumImpact`, and a crisp snap sound. Beating with a **trump** adds a brief suit-colored rim flash on the pair. Chained re-beats in 3+ player games escalate: slightly bigger shake per layer (capped).

### 5.5 Special moments

- **Shoha (6 of clubs) — the legend.** When played *as a beat*: time dilates (all other animation speed 0.5x for 400 ms), vignette darkens 15%, the card flies with a green-black particle trail, lands with a heavy slam, a Rive **club-sigil shockwave** ripples across the felt, `HapticFeedback.heavyImpact` ×2, and a unique bass sound stinger. A one-time "ШОХА!" calligraphic stamp fades over the pair. When *led* onto an empty table (ordinary-six mode): deliberately **no** effect — the absence itself teaches the rule.
- **Face-down decline:** discarded cards flip to their backs at the *start* of flight (identity provably hidden — the client is never even sent their faces; server sends only counts) and land in a loose face-down clump with a soft "shhh" sound; then the whole trick vacuums into the taker's won pile with a sweep.
- **Trump reveal / rotation:** revealed card rises from the stack, does a slow 540° flip at 1.4x scale center-table, suit glyph rings pulse outward twice, then it tucks under the stock (initial deal) or into the drawer's hand (rotation — see assumption A1). Felt tint crossfades to the new suit watermark. If the revealed trump is a **6** (multiplier!): the x2/x3 stamp slams down with a warning drum hit — players must feel the stakes change.
- **Deal-end tally (Section 3.5):** card-points count up odometer-style (individually animated digit columns), each player's collected point-cards briefly fan out and fly into their tally, penalty badge lands with a thud; multiplier stamps come last.
- **Goat reveal:** loser's avatar zooms center, Rive goat trots in, horns pop onto the avatar with a spring scale, sad-trombone-adjacent sting (kind-hearted, not humiliating — 1.5 s max), confetti burst for the others, `heavyImpact`. A "share card" (image of the final table) is generated locally.

### 5.6 Haptics map

`selectionClick` on card select · `lightImpact` on play landing · `mediumImpact` on beat slam · `heavyImpact` on shoha/goat/multiplier · timer ticks last 5 s (own turn) · nothing on opponents' routine moves (avoid buzz fatigue). Global toggle in settings.

### 5.7 Performance budget

- **Target:** 120 fps on ProMotion/high-refresh devices, hard floor 60 fps on a 2019 mid-ranger (e.g. Redmi Note 8). Frame budget 8.3 ms target / 16.6 ms floor.
- **Precache:** all 36 card faces + backs rasterized at exact display sizes (fan size, trick size, mini size) during splash; Rive artboards warmed; audio pool preloaded.
- `RepaintBoundary` around: each seat widget, the fan, each in-flight card, the trick area, the particle layer.
- **Caps:** ≤ 12 simultaneously animated cards (deal batches respect this), ≤ 40 live particles, no `saveLayer`, no blur/shadows on animating widgets (pre-baked shadow in the card raster), no `Opacity` widget on moving cards (use `FadeTransition`/alpha in painter).
- CI perf check: `flutter drive --profile` scripted deal + 3 tricks, assert 99th-percentile frame < 16 ms via `FrameTiming`.

---

## 6. Card asset strategy

- **Commission a custom 36-card vector set** (SVG sources) in a modernized Russian-deck aesthetic: slightly stylized court cards (J/Q/K) with flat shading and 2-color-plus-accent palette, oversized corner indices (rank + suit) tuned for a 45%-overlapped fan on a 6" phone — corner legibility is the acceptance criterion. Budget fallback: start from the public-domain **SVG-Cards** set (or Chris Aguilar's vector playing cards), strip to 36, restyle courts and indices; ship v1, swap art later without code changes (assets are keyed `c6…sA`).
- **Ten and Ace get a subtle gold index accent** (they're the point bombs and Ten's rank position surprises newcomers); **6 of clubs gets a unique face** — the shoha bears a small horned-goat watermark, making the legendary card recognizable at a glance.
- **Rendering:** do *not* animate `flutter_svg` widgets (per-frame parse/paint cost). At startup, compile/rasterize each SVG to `ui.Image` at the 3 needed logical sizes × device pixel ratio (via `vector_graphics` precompiled binaries or direct offscreen raster), then all card widgets are cheap `RawImage`/`Canvas.drawImage` draws. Memory: 36 × 3 sizes × ~4 bpp ≈ well under 40 MB; evict mini-size on memory pressure.
- **Theming:** card **backs** (default goat-pattern, plus unlockable variants via achievements) and **felt** (green, navy, dark walnut; dark-mode-first palette) are theme tokens. Face set itself is themeable later (a `CardTheme` maps key → asset bundle) — anticipated for a "classic Atlas deck" nostalgia theme.

---

## 7. Emoji reactions and achievements

### 7.1 Emoji quick-reactions

- Round button bottom-right of the table opens a **horizontal quick bar** of 8 fixed reactions (v1): laughing, crying, angry, mind-blown, clapping, thinking, goat, the shoha club glyph. One tap sends (`react(emojiId)` — IDs, not free text; safe and tiny on the wire).
- Incoming reaction: a **bubble pops above the sender's avatar**, scales in with a spring, floats up 24 dp and fades over 2.5 s; stacked reactions fan slightly. Own bubble echoes locally instantly (fire-and-forget optimism — harmless).
- **Rate limit** client + server: 1 per 2 s, bar shows a cooldown sweep. Per-player **mute** via long-press on their seat ("mute reactions"). No chat in v1 — reactions are the whole social channel, keep them snappy (< 150 ms perceived).

### 7.2 Achievements

- Screen: grid of achievement cards — icon, humorous title, one-line description, progress bar for tiered ones; locked = embossed silhouette + "???" for secret ones. Header shows completion ("14/40") and rarest-owned badge. Sort: unlocked-recent / rarity.
- Examples of tone (final list is content work): "Не подмажешь — не поедешь" (first decline), "Шохой по трампу" (beat a trump ace with the shoha), "Сухой козёл" (win a deal where an opponent took zero), "Живучий" (survive at 22–23 points and win), "Коллекционер десяток" (take all four 10s in one deal), "Молниеносный" (average move < 2 s for a full game).
- **In-game unlock toast:** compact banner drops from the top bar (icon + title), auto-dismiss 3 s, never interrupts input; full celebratory reveal (shine sweep + haptic) deferred to the game-end screen queue. Server is the authority on unlocks (`achievementUnlocked` event); client caches the catalog with versioning.

---

## 8. Offline / error UX

- **Connection banner:** slim strip under the top bar with three states — reconnecting (amber, animated ellipsis, attempt counter), restored (green, auto-hide 2 s), lost (red, after token expiry: "Return to lobby" CTA). During reconnecting, the **table stays visible but input-locked** (fan dims, dashed border); on `Snapshot` after reconnect, the client diffs and *fast-forwards* missed moves as accelerated 2x animations (max 4 s of catch-up, then jump-cut) so the player re-enters with context, not a teleport.
- **Reconnection flow:** Colyseus `reconnectionToken` persisted to disk → app cold-start can rejoin an in-progress game (splash detects a live token → "Return to game?" prompt). Server holds the seat for the room's grace period (e.g. 60 s); other players see the seat countdown (Section 4.4).
- **Optimistic actions, narrow and safe:** only *own card plays* are optimistic — on tap-confirm the flight starts immediately with the card in a "pending" state (tiny spinner dot on the landed card until `IntentAccepted`, typically imperceptible). On `IntentRejected` (rare: race with timeout, stale legal set): the card **flies back to the fan** with a shake + error haptic + reason toast, state re-synced from the authoritative event stream. Every intent carries a client `actionId` for idempotent retry on transient WS drops. Declines, multi-card pairings and everything else are server-confirmed (the animations mask the RTT anyway).
- **Latency display:** RTT measured via transport ping/pong every 5 s; lobby and table show a quality chip (three dots: <80 ms green / <200 ms amber / worse red), tap → exact ms + region. Turn timer deadlines come as **server timestamps**; client renders against a smoothed clock offset so the ring never jumps.
- **Error taxonomy:** transient (auto-retry, silent) / rejected intent (rollback UX) / room fatal (kicked, room disposed → dialog to lobby) / version mismatch (`protoVersion` — force-update dialog).

---

## 9. Testing

### 9.1 Pure Dart unit tests (fastest, biggest layer)
`core/game` reducer: event-stream in → state out, including reconnect fast-forward, seq-gap → resync request, selection validator truth table (same-rank/same-suit unions), scoring display math. Transport codec: WS envelope encode/decode against **golden byte fixtures recorded from a real Colyseus server** (guards against Colyseus upgrades).

### 9.2 Widget tests
Inject a `FakeGameConnection` (scripted `ServerEvent` streams) via Riverpod overrides. Cover: fan selection states and dimming per `beatMap`, multi-select pill logic, drag-to-pair hit targets, timer ring states, reconnect banner transitions, deal-end tally numbers, reaction rate-limit UI. Animations run with `tester.pump` under a test flag `AnimationDirector.instant = true` where motion isn't the subject.

### 9.3 Golden tests
- All 36 card faces + backs at the 3 raster sizes (catches asset regressions pixel-exactly).
- Table layouts: 2/3/4/6 seats × {small phone 320×640, standard 390×844, tall 412×915} × light/dark felt — with the **seeded PRNG fixed**, mid-trick scenes are deterministic and goldenable.
- Deal-end and goat screens.
Run on a pinned Flutter version in CI (goldens are toolchain-sensitive).

### 9.4 Integration tests against a local Colyseus server
- Server repo ships `docker compose up test-server` (Colyseus + game rooms + deterministic RNG seed flag + accelerated timers).
- `integration_test` suite boots the app against `ws://localhost:2567`; a **Node driver script** (using the official JS client) plays the other seats, enabling full scripted games: quick-join → deal → lead/beat/decline → trump rotation → deal-end → goat. Assert on rendered state via widget keys, not pixels.
- **Contract tests:** the shared JSON vectors (Section 2.5) plus snapshot fixtures run in both repos' CI; a protocol change that isn't mirrored fails the build on the lagging side.
- Chaos pass: driver kills the socket mid-trick / mid-deal and asserts reconnect + fast-forward correctness.
- Nightly device-lab profile run enforces the Section 5.7 frame budget.

---

## 10. Flagged rule assumptions affecting this design (need confirmation)

- **A1 — Revealed trump card fate:** assumed it lies face-up crosswise **under** the stock, is part of the stock, and is drawn **last**; whoever draws it takes it into hand and it stays the current trump until/unless the "last card shows new trump" rule re-reveals it (it *is* the last card, so it is its own reveal). UI (Section 4.8) is built on this.
- **A2 — Turn flow with 3/4/6 players:** assumed strictly sequential single-defender chain: attacker leads → next player clockwise beats or declines → if beaten, the *following* player may beat the newest layer, etc.; only the two ends of the current exchange act at any moment, others watch. Seat arc + chevron UX assumes this.
- **A3 — Multi-card beat pairing:** assumed the **defender chooses** which of their cards covers which attack card (drag-to-pair UI). If pairing is instead automatic/canonical, the drag targets collapse to a single drop zone — minor change.
- **A4 — 6 players (36 cards, no stock):** assumed the **last card dealt to the dealer is shown as trump** and returns to their hand; no stock, no trump rotation, stock UI hidden. (Multiplier rule then keys off this shown card's rank.)
- **A5 — Stock exhausted:** trump stays fixed at its last value; no replenishment; hands play down below 6. Trump chip shows the lock state.
- **A6 — Equal-scores triple rule:** assumed "any two players equal at deal start" (not necessarily involving the eventual loser) is sufficient for x3 when first trump is a 6; the deal-start banner shows the potential multiplier up front.
- **A7 — Timeout default:** assumed timeout = auto-decline (with random discards) when defending, and auto-lead lowest legal single when leading.

The reducer, protocol, and `TableGeometry` isolate all seven assumptions; each flips with a localized change once the human confirms the house rules.