# «Goat» (Козёл) — Authoritative Rules Engine Design Document

**Target:** pure, deterministic, framework-free TypeScript package `@goat/engine`, consumed by a Colyseus room on the server and (identically) by the Flutter client via generated bindings / shared derivation results.
**Version:** 1.0-draft (all `ASSUMPTION` items pending human confirmation).

---

## 0. Design Principles

1. **Pure reducer core.** The entire engine is `reduce(state, action) → { state, events } | EngineError`. No I/O, no `Date.now()`, no `Math.random()`, no exceptions for expected rule violations (typed error results instead). Exceptions only for programmer errors (corrupted state).
2. **Deterministic randomness.** All randomness (shuffle, dealer selection) comes from a 64-bit seed passed into `initGame`. Same seed + same action sequence ⇒ byte-identical state. This gives free replay, deterministic reconnection catch-up, and property-test reproducibility.
3. **Single source of legality.** `legalActions(state, playerId)` is the *only* definition of what is allowed. `reduce` internally validates via the exact same predicate. Server sends its output to clients for UI affordances; client never re-implements rules.
4. **Auto-advance.** Player actions may trigger deterministic follow-up phases (trick resolution, replenishment, trump rotation, scoring). `reduce` runs these to completion until the next *decision point* (a state where some player has ≥1 legal action) or terminal state. Every intermediate step is emitted as an `EngineEvent` so the client can animate the sequence (dynamic gameplay requirement) without the engine knowing about animation.
5. **Perfect-information core + redaction layer.** `GameState` contains full information. `redact(state, viewerSeat)` produces a `PlayerView` that hides other hands (exposing **counts** — a hard product requirement), face-down discards, and stock contents. Colyseus schema is generated from `PlayerView`, never from `GameState`.
6. **Structural immutability.** State objects are treated as immutable; `reduce` returns fresh objects (persistent-update helpers). Enables cheap snapshots for reconnection and undo-free debugging.
7. **Ports anticipated.** No TS-exotic runtime features; cards are integers; state is JSON-serializable (`serialize`/`deserialize` round-trip guaranteed). This keeps a future Dart/WASM port mechanical, and lets bots (post-v1) consume `PlayerView` + `legalActions` directly.

---

## 1. Rules Formalization — Finite State Machine

### 1.1 Phase enumeration

```
GamePhase (top level)
├── LOBBY_INIT            (engine created, players fixed, before first deal)
├── DEAL_IN_PROGRESS
│   ├── TRICK_LEAD        decision point: leader must LEAD
│   ├── TRICK_BEAT        decision point: current defender must BEAT or DECLINE
│   ├── [TRICK_RESOLVE]   auto: assign table cards to winner
│   ├── [REPLENISH]       auto: draw to 6, rotate trump
│   └── [DEAL_END_CHECK]  auto: all hands empty? → DEAL_SCORING
├── [DEAL_SCORING]        auto: count points, apply multipliers, update running scores
├── [GAME_END_CHECK]      auto: 12-0 rule, threshold rule
├── DEAL_SETUP            auto→: shuffle, deal, reveal trump (entered from LOBBY_INIT or GAME_END_CHECK)
└── GAME_OVER             terminal: goat(s) determined
```

Bracketed phases are **auto phases**: `reduce` passes through them without external input; they exist only as event-emission boundaries. The persisted `state.phase` is always one of the decision points or terminals: `TRICK_LEAD`, `TRICK_BEAT`, `GAME_OVER`.

### 1.2 State transition table

| # | From | Action / trigger | Guard | To | Effects |
|---|------|------------------|-------|-----|---------|
| T1 | LOBBY_INIT | (auto on init) | 2–6 players | DEAL_SETUP | pick dealer from seed |
| T2 | DEAL_SETUP | (auto) | — | TRICK_LEAD | shuffle (seeded), deal 6 each, reveal first undealt card = initial trump (A-1), place it at stock bottom; record `initialTrumpRank`; 6p: no stock, dealer's last card revealed (A-4); leader = seat left of dealer |
| T3 | TRICK_LEAD | `LEAD {cards}` | lead-legality (§1.3.1) | TRICK_BEAT | table ← lead set (set #0); defender = next active seat |
| T4 | TRICK_BEAT | `BEAT {pairs}` | beat-legality (§1.3.2) | TRICK_BEAT | table ← beat set (set #n+1); "most recent set" owner = beater; defender = next active seat (wraps, may reach original leader — A-2) |
| T5 | TRICK_BEAT | `DECLINE {discards}` | decline-legality (§1.3.3) | TRICK_RESOLVE | discards go face-down onto table |
| T6 | TRICK_BEAT | (auto-forced) | defender hand empty | TRICK_RESOLVE | treated as `DECLINE {discards:[]}` — skip (§4.6) |
| T7 | TRICK_RESOLVE | (auto) | — | REPLENISH | owner of most recent set takes ALL table cards (incl. face-down discards) into won pile |
| T8 | REPLENISH | (auto) | stock > 0 | DEAL_END_CHECK | round-robin draw starting at trick winner until all ≤6-hands filled or stock empty; **last card drawn this phase is revealed to all; its suit becomes new trump** (A-6); if stock emptied, `stockExhausted=true` and trump frozen |
| T9 | REPLENISH | (auto) | stock == 0 | DEAL_END_CHECK | no-op |
| T10 | DEAL_END_CHECK | (auto) | some hand non-empty | TRICK_LEAD | leader = trick winner; if winner's hand empty → next active seat clockwise (§4.7); if only ONE player has cards → their cards go to their own won pile (A-8), then DEAL_SCORING |
| T11 | DEAL_END_CHECK | (auto) | all hands empty | DEAL_SCORING | — |
| T12 | DEAL_SCORING | (auto) | — | GAME_END_CHECK | per-player penalties ×multiplier (§5), add to running scores; emit `DealScored` |
| T13 | GAME_END_CHECK | (auto) | 12-0 rule or threshold hit (§5.4) | GAME_OVER | compute goat set |
| T14 | GAME_END_CHECK | (auto) | otherwise | DEAL_SETUP | dealer rotates clockwise; `dealIndex++` |

There is deliberately **no PASS action and no "take" action**: unlike Durak, every trick ends with exactly one DECLINE, the decliner never takes cards (the last thrower does), and beats are all-or-nothing.

### 1.3 Legal-action derivation (normative)

`legalActions(state, seat)` returns `[]` for every seat except the one to move.

#### 1.3.1 Phase TRICK_LEAD (mover = `state.trick.leader`)

A set `S ⊆ hand(leader)` is a legal `LEAD {cards: S}` iff:
- `|S| ≥ 1`, and
- all cards in `S` share one rank **or** all share one suit (singletons trivially satisfy both), and
- `|S| ≤ handSize(nextActiveDefender)` (A-3: lead-size cap).

A shoha (6♣) inside a lead set is ordinary (it is being *led*).
Enumeration is cheap: same-rank subsets ≤ 2⁴, same-suit subsets ≤ 2⁹ per suit; enumerated result is returned as `LeadOptions { singles: CardId[], maxCount: number, rankGroups, suitGroups }` — the client builds selections from this and validates locally with the shared `isLegalLead` predicate rather than receiving all subsets.

#### 1.3.2 Phase TRICK_BEAT (mover = `state.trick.defender`)

Let `T` = the **most recent set** on the table (size `k`). Single-card beat predicate `beats(b, t, trump)`:

```
beats(b, t) :=
     isShoha(b)                                          // 6♣ as a BEAT card beats anything
  || ( !isShoha(t)                                       // nothing beats a shoha that was played as a beat…
       && (  (suit(b) == suit(t) && rankOrd(b) > rankOrd(t))   // same suit, strictly higher (covers trump-on-trump)
          || (suit(b) == trump   && suit(t) != trump) ) )      // trump beats any non-trump
```

Special case: a shoha that is part of a **lead** set is flagged `ledAsOrdinary` and *is* beatable by the same-suit/trump rules (`isShoha(t)` treated as false for it).

`BEAT {pairs: [{target: CardId, card: CardId}] × k}` is legal iff:
- pairs form a bijection `T → B`, `B ⊆ hand(defender)`, `|B| = k` (all-or-nothing, A-5), and
- `beats(pair.card, pair.target)` holds for every pair (defender chooses the pairing, A-5).

Derivation for UI: `beatMatrix: Map<targetCardId, CardId[]>` (per-target candidate beaters from the defender's hand) + `hasPerfectMatching: boolean` (Hopcroft–Karp on the ≤6×6 bipartite graph — trivial cost). `BEAT` is offered iff a perfect matching exists.

#### 1.3.3 DECLINE (same phase)

`DECLINE {discards}` is legal iff:
- `discards ⊆ hand(defender)` and `|discards| = min(k, handSize(defender))` (A-3: short hands dump everything).

**DECLINE is always legal when it is your turn to beat** — beating is never compulsory ("can't/won't"). Exception-free consequence: if the most recent set contains a shoha played as a beat, `hasPerfectMatching` is automatically false and DECLINE is the *only* legal action.

### 1.4 Determinism note on auto phases

Auto phases consume no player input but *do* consume RNG only in DEAL_SETUP (shuffle). Replenish order, trump rotation, scoring are pure functions of state. Hence: `stateHash = f(seed, actionLog)` — asserted in tests.

---

## 2. Data Model (field-level)

Cards are integers `0..35`: `cardId = suit * 9 + rankIndex`. Suits `0=♣,1=♦,2=♥,3=♠`. Rank index encodes the **game order**: `0=6,1=7,2=8,3=9,4=J,5=Q,6=K,7=10,8=A` (so `rankOrd` comparison is just integer comparison; the 10-above-K quirk is baked into the encoding, not into logic). `SHOHA_ID = 0` (6♣).

```ts
type CardId = number;                // 0..35
type Suit = 0 | 1 | 2 | 3;
type Seat = number;                  // 0..playerCount-1, clockwise

interface CardMeta {                 // derived, not stored
  suit: Suit;
  rankIndex: number;                 // 0..8 in game order
  points: 0 | 2 | 3 | 4 | 10 | 11;  // J=2 Q=3 K=4 10=10 A=11
  label: string;                     // "10♥"
}

interface PlayerState {
  seat: Seat;
  hand: CardId[];                    // sorted canonical order (suit,rankIndex) for determinism
  wonPile: CardId[];                 // face-up-to-owner; reviewable by owner only
  wonPoints: number;                 // cached sum, invariant-checked
  connected: boolean;                // mirrored from room; engine only reads it for auto-action derivation
}

interface ThrownSet {
  owner: Seat;
  cards: CardId[];
  kind: 'lead' | 'beat';
  pairing?: { target: CardId; card: CardId }[]; // for beats: which card covered which (needed for animation + shoha semantics)
}

interface TrickState {
  index: number;                     // trick # within deal
  leader: Seat;
  defender: Seat;                    // whose turn to beat/decline
  sets: ThrownSet[];                 // sets[0] = lead; last element = "most recent set"
  declineDiscards: CardId[];         // face-down; filled at decline; identity hidden by redaction
}

interface DealState {
  index: number;                     // deal # within game
  dealer: Seat;
  stock: CardId[];                   // stock[0] drawn first; initial trump card sits at stock[stock.length-1] (A-1)
  trumpSuit: Suit;                   // CURRENT trump (rotates)
  trumpCard: CardId;                 // currently face-up-known trump-defining card (public)
  initialTrumpRank: number;          // rankIndex of the FIRST revealed trump — drives ×2 (§5)
  tripleGame: boolean;               // computed at deal start (§5.3), frozen
  stockExhausted: boolean;
  trick: TrickState | null;
  scoresAtDealStart: number[];       // running scores snapshot (for triple-game audit)
}

interface GameConfig {
  playerCount: 2 | 3 | 4 | 6;
  loseThreshold: 24 | 36;            // room-configurable, default 24
  seed: string;                      // hex 64-bit, feeds splitmix64→xoshiro128**
}

interface GameState {
  config: GameConfig;
  phase: 'TRICK_LEAD' | 'TRICK_BEAT' | 'GAME_OVER';
  players: PlayerState[];            // length = playerCount, index = seat
  deal: DealState | null;            // null only in GAME_OVER edge
  scores: number[];                  // running penalty scores
  goats: Seat[];                     // empty until GAME_OVER
  gameOverReason: 'THRESHOLD' | 'TWELVE_ZERO' | null;
  rngState: [number, number, number, number]; // xoshiro internal state — serialized!
  actionCount: number;               // monotone; used as optimistic-concurrency tag by the room
}
```

**Redacted view** (what Colyseus syncs; also the bot/UI contract):

```ts
interface PlayerView {
  viewerSeat: Seat;
  phase: GameState['phase'];
  myHand: CardId[];
  handCounts: number[];              // ALWAYS present — product requirement
  wonPileCounts: number[];           // counts only; own pile contents via myWonPile
  myWonPile: CardId[];               // owner may review
  stockCount: number;
  trumpSuit: Suit;
  trumpCard: CardId;                 // public by rule (revealed)
  initialTrumpWasSix: boolean;
  tripleGame: boolean;
  trick: {                           // sets are public; declineDiscards → count only
    leader: Seat; defender: Seat;
    sets: ThrownSet[];
    declineDiscardCount: number;
  } | null;
  scores: number[];
  dealer: Seat; dealIndex: number; trickIndex: number;
  goats: Seat[]; gameOverReason: GameState['gameOverReason'];
  legal: LegalActions;               // §7 — derived for viewer, [] off-turn
}
```

---

## 3. Ambiguity Resolutions

Each item is an **ASSUMPTION** — implemented behind a single named constant/branch, unit-tested in isolation, and trivially flippable after human confirmation. All live in `src/rules/assumptions.ts` with doc comments.

**A-1 — Fate of the initially revealed trump card.**
**ASSUMPTION:** the revealed card is placed face-up at the **bottom of the stock and is drawn last**. It counts as part of the stock; whoever draws it takes it into hand.
*Rationale:* standard convention in Russian 36-card games (Durak family); keeps the card's identity public information all deal (nice UX — it's visible under the stock); and it composes elegantly with trump rotation: the final replenishment's last-drawn card is this very card, so the *endgame trump equals the initial trump*, which players of the physical game will find familiar.

**A-2 — Turn flow with 3/4/6 players.**
**ASSUMPTION:** strict clockwise chain, every player participates. Leader throws; the next active (non-empty-handed) seat clockwise is the sole defender of the *most recent set*; on a successful beat, defense passes to the next active seat, wrapping around the table — **including back to the original leader**, potentially for multiple laps (hand sizes bound it). The first DECLINE ends the trick immediately; players after the decliner do not get a chance to take over the beating.
*Rationale:* it is the only reading consistent with "the following player in turn order may try to beat the most recent set, and so on" plus "when someone declines, the last player who threw/beat takes everything"; allowing later players to rescue a declined trick contradicts "the previous thrower takes ALL table cards" being triggered by the decline itself.

**A-3 — Lead size cap and short hands.**
**ASSUMPTION:** (a) a lead may not exceed the current (first) defender's hand size; (b) any *later* player in the chain holding fewer cards than the set size may still be reached — for them BEAT is impossible and DECLINE discards their **entire remaining hand** (`min(k, handSize)` face-down cards).
*Rationale:* (a) prevents degenerate unanswerable leads and mirrors Durak's attack cap; (b) keeps the "discard the same NUMBER" rule total in the endgame without inventing card debt.

**A-4 — 6-player mode: no stock, trump determination.**
**ASSUMPTION:** with 6×6=36 all cards are dealt. The **dealer's final dealt card** is dealt face-up to the dealer's hand; its suit is trump for the whole deal (no rotation, `stockExhausted=true` from the start). The ×2/×3 rank-6 rule keys off this card.
*Rationale:* preserves the "a random card revealed at deal time defines trump" mechanic and the rank-6 multiplier without changing deal size; revealing the dealer's card (mild information penalty for the dealer) matches common no-stock conventions in Russian games. Alternative considered and rejected: playing trumpless — kills the multiplier rule and flattens gameplay.

**A-5 — Multi-card beat pairing.**
**ASSUMPTION:** the defender submits an explicit **bijective pairing** (each of their `k` beat cards assigned to a distinct thrown card), validated card-by-card; the beat is **all-or-nothing** (no partial beats). The pairing is stored and shown (cards animate onto their targets).
*Rationale:* "must beat EACH thrown card" implies per-card validation; letting the defender choose the pairing matches physical play (you place your card on the one it beats) and is strictly more permissive — the engine additionally exposes `hasPerfectMatching` so the client can grey out BEAT correctly even when a naive greedy pairing would fail.

**A-6 — Trump rotation trigger.**
**ASSUMPTION:** "whoever draws the LAST stock card shows it" means: **after every trick's replenishment phase, the last card drawn in that phase** is publicly revealed (then kept in hand) and its suit becomes the new trump. When the stock empties, the truly-last card sets the final trump, which is then **frozen for the rest of the deal**.
*Rationale:* this is the only interpretation compatible with the given clause "trump can change after each trick while stock lasts". Combined with A-1, the final trump = initial trump suit.

**A-7 — Stock exhaustion mid-replenishment.**
**ASSUMPTION:** replenishment draws one card at a time round-robin starting from the trick winner, skipping players already at 6; when the stock runs out mid-round, remaining players simply stay short. Unequal hand sizes are legal thereafter; the lead cap (A-3a) and short-hand decline (A-3b) handle the consequences. No redistribution, no reshuffling of won piles.

**A-8 — Endgame residue: one player left with cards.**
**ASSUMPTION:** if at trick start only one player holds cards (everyone else empty), their remaining cards go **into their own won pile** as an unopposed trick, and the deal ends.
*Rationale:* keeps the 120-point conservation invariant (every card must land in exactly one won pile) and avoids a meaningless solo lead loop. This is favorable to that player; flagged for confirmation (alternative: cards go to the last trick's winner).

**A-9 — First leader & dealer rotation.**
**ASSUMPTION:** dealer for deal 1 is seeded-random; the player left of (clockwise after) the dealer leads the first trick; dealer rotates clockwise each deal.
*Rationale:* universal convention; nothing in the spec contradicts it.

**A-10 — Triple-game "two players equal" scope.**
**ASSUMPTION:** the triple condition is: first revealed trump has rank 6 **AND** at deal start there exists *any* pair of players with equal running scores — **including 0–0**, hence including the very first deal and any pair of untouched players.
*Rationale:* literal reading; 0=0 is an equality. Flagged loudly because it makes every first-deal trump-6 a triple game — the human may want to exclude 0–0.

**A-11 — Multiplier stacking.**
**ASSUMPTION:** ×3 **replaces** ×2 (multiplier = 3 if triple condition, else 2 if trump-6, else 1). Never ×6.
*Rationale:* "the additions are TRIPLED" names the total effect, and the triple condition already subsumes the trump-6 condition; ×6 would be stated explicitly if intended.

**A-12 — Threshold ties / multiple goats.**
**ASSUMPTION:** after a deal, all players with `score ≥ loseThreshold` are goats simultaneously (the game supports a multi-goat result). Priority of end conditions: the 12-0 rule is checked **first**; if it fires, its offender(s) are the goats and threshold is not evaluated. Multiple 12-0 offenders in the same deal are all goats.
*Rationale:* simplest total rule; UX can present multi-goat humorously (fits the achievements tone).

**A-13 — Disconnect mid-trick (engine's share of the problem).**
**ASSUMPTION:** the engine stays pure and knows nothing about timers. It exports `deriveAutoAction(state, seat)` — a deterministic "least-commitment" action: when leading, lead the single lowest-point (then lowest-rank, then lowest-suit) card; when defending, DECLINE discarding the `k` lowest-point cards. The Colyseus room owns the disconnect grace timer (reconnection is a v1 feature) and, on expiry, feeds the auto-action through the normal `reduce` path — so replays remain valid.

---

## 4. Edge-Case Catalogue

Each item maps to at least one scenario test (§6.2).

**4.1 Shoha (6♣) interactions**
- Shoha **as beat**: beats trump A, beats trump 6 of another... beats *everything*, including any trump; the set containing it cannot be beaten → next defender's `legal` = `{DECLINE}` only.
- Shoha **as lead** (alone, or inside a clubs-suit lead, or inside a rank-6 lead): flagged `ledAsOrdinary`; beatable by 7♣–A♣ or any trump (if clubs are not trump), or by 7♣–A♣ when clubs *are* trump.
- Shoha when **clubs are trump**: as a beat card it needs no trump logic (absolute); as a target led card it is simply the lowest trump.
- Shoha in **decline discards**: legal — it's face-down garbage like any card; goes to the taker's pile (worth 0 points anyway).
- Pairing with shoha: defender may assign shoha to *any* target, including a trump target, even though their other cards must still individually beat theirs.

**4.2 Trump-on-trump**
- Trump target ⇒ only strictly-higher same-suit (trump) card or shoha beats it. The `suit(b)==trump && suit(t)!=trump` clause must NOT fire when `t` is trump — covered because it requires `suit(t)!=trump`. Test: trump 6 does not beat trump 7; trump 10 beats trump K.

**4.3 Multi-card leads & pairing**
- Rank-lead of 3×9 beaten with mixed answer: 10♦ on 9♦, trump 7 on 9♥, shoha on 9♠ — valid bijection.
- Perfect-matching subtlety: defender holds Q♦, trump 8; table = J♦, 10♦. Greedy Q♦→J♦ then trump8→10♦(non-trump? no—10♦ same suit as Q♦…) — engine must find matchings a greedy might miss; test a case where only one of two pairings is valid.
- No partial beats: defender who can beat 2 of 3 cards sees BEAT disabled (`hasPerfectMatching=false`).
- Duplicate-target or duplicate-card in pairs ⇒ typed error `E_PAIRING_NOT_BIJECTIVE`.

**4.4 Last tricks with <6 cards**
- Lead cap = defender's hand size (A-3a); leader with 4 cards vs defender with 2 → max lead 2.
- Chain player with 1 card facing a 3-card set → forced `DECLINE` discarding their 1 card; taker gets 3+3+1 cards.
- Decline with exactly-equal hand (k = handSize) empties the decliner's hand.

**4.5 Stock exhaustion & trump rotation end**
- Stock hits 0 exactly on a replenishment boundary vs mid-round (A-7): both tested; `stockExhausted` set; trump frozen; `trumpCard` = last drawn (the initial trump card, by A-1).
- 2-player game: stock 24 → many rotations; property test asserts trump always equals suit of last revealed card.
- 4-player game: stock 12 → exhausted after ~2nd trick replenishment.
- Rotation reveals a rank-6 card: does **not** change the deal multiplier (only the *initial* reveal counts) — explicit test.

**4.6 Empty-hand players mid-deal (post-exhaustion)**
- Defender chain **skips** empty-handed seats (T6 is about a seat becoming defender with 0 cards — they are skipped silently, not treated as declining, else they'd end every trick; skip is the correct reading and is what "active seat" means throughout).
- Trick where all non-leader seats are empty → A-8 residue rule.

**4.7 Trick winner cannot lead (empty hand)**
- Winner replenishes first, so this only happens post-exhaustion: lead passes clockwise to the next seat with cards.

**4.8 6-player no-stock mode**
- No REPLENISH phase at all; trump fixed (A-4); exactly 6 tricks worth of cards minus chain-consumption — deal ends when hands empty; `handCounts` become asymmetric quickly (chains consume beats unevenly) — invariant: Σ(hands+piles+table)=36 at all times.

**4.9 Scoring simultaneity**
- Deal ends leaving A at 26, B at 12, C at 0 → 12-0 fires (A-12): is B the goat, or A via threshold? Per A-12, 12-0 checked first ⇒ **B** is goat... and A? A also satisfies "≥12 while C at 0" ⇒ both A and B goats via TWELVE_ZERO. Test pins this.
- Exactly 24 (threshold inclusive), and 23→+6-multiplied jumps crossing both 12-0 and 24 in one deal.
- 60/60 two-player split: both get +2. >60 for one implies ≤60 for others but *not* conversely (3+ players can all be ≤60) — test that ranges are per-player independent.
- Zero-cards-won (+6) vs 1–40 (+4) boundary: a pile with only zero-point cards (e.g. three 8s) is **1–40? It has >0 cards but 0 points** → spec says "zero cards won → +6"; a pile with cards but 0 points scores **+4** (1–40 band is card-*points* 1–40; 0 points with non-empty pile falls in no band!). **Resolution baked into scoring spec §5.1:** bands are defined on points with the +6 band requiring an *empty pile*; non-empty pile with 0 points → +4 band (treated as "≤40, took something"). Flagged inside §5 as **ASSUMPTION A-14**.
- Double/triple stacking (A-11): trump-6 + equal scores ⇒ ×3 not ×6; trump-6 alone ⇒ ×2; equal scores alone (trump not 6) ⇒ ×1.

**4.10 Disconnect mid-trick**
- Auto-action determinism: same state ⇒ same auto-action (A-13).
- Auto-decline with `k > handSize` (short hand) discards whole hand.
- Reconnection: `redact(state, seat)` after N further actions must fully reconstruct the UI including mid-trick table sets and pairing info.

**4.11 Degenerate configs**
- 2-player: chain is strictly alternating; leader can be re-attacked by own momentum (lap-around means leader beats defender's beat).
- All-trump lead (suit lead of trumps) and trump-suit lead containing shoha when clubs are trump.

---

## 5. Scoring Module Spec

Pure module `src/scoring.ts`, no state mutation — takes inputs, returns results.

### 5.1 Per-deal penalty

```ts
function dealPenalty(pilePoints: number, pileCount: number): 0 | 2 | 4 | 6 {
  if (pileCount === 0) return 6;        // took nothing at all
  if (pilePoints > 60) return 0;
  if (pilePoints >= 41) return 2;
  return 4;                              // 0..40 points but took ≥1 card  ← ASSUMPTION A-14
}
```

**A-14 (flagged):** non-empty pile with 0–40 points → +4; the +6 band requires an *empty* pile. (The literal bands "1–40" and "zero cards" leave a 0-points-nonempty gap; we close it downward, the lenient reading.)

### 5.2 Multiplier

```ts
function dealMultiplier(initialTrumpRankIndex: number, scoresAtDealStart: number[]): 1 | 2 | 3 {
  const trumpSix = initialTrumpRankIndex === 0;           // rank 6
  if (!trumpSix) return 1;
  const anyEqualPair = hasDuplicate(scoresAtDealStart);   // includes 0–0 (A-10)
  return anyEqualPair ? 3 : 2;                            // 3 replaces 2 (A-11)
}
```

Computed and frozen at DEAL_SETUP (`deal.tripleGame`), displayed to players immediately (UX: "×2/×3 game!" banner — supports the "dynamic" product goal). Trump rotations never alter it.

### 5.3 Application

`score[p] += dealPenalty(pointsOf(wonPile[p]), wonPile[p].length) * multiplier`. Invariant: Σ pilePoints over players = 120 every deal.

### 5.4 Game-end evaluation (GAME_END_CHECK)

```ts
function evaluateGameEnd(scores: number[], threshold: number):
  { over: false } | { over: true; reason: 'TWELVE_ZERO' | 'THRESHOLD'; goats: Seat[] } {
  const zeroExists = scores.some(s => s === 0);
  const twelvers = seatsWhere(scores, s => s >= 12);
  if (zeroExists && twelvers.length > 0)                        // A-12: checked FIRST
    return { over: true, reason: 'TWELVE_ZERO', goats: twelvers };
  const overThreshold = seatsWhere(scores, s => s >= threshold);
  if (overThreshold.length > 0)
    return { over: true, reason: 'THRESHOLD', goats: overThreshold };
  return { over: false };
}
```

Threshold is **inclusive** (`≥ 24/36`). Multiple goats possible (A-12).

---

## 6. Test Plan

Stack: `vitest` + `fast-check`. Target: 100% branch coverage on `rules/`, `scoring/`; mutation testing (Stryker) on the `beats` predicate and scoring bands.

### 6.1 Property-based tests

| # | Property | Generator |
|---|----------|-----------|
| P1 | **Card conservation:** at every state, hands ∪ piles ∪ stock ∪ table sets ∪ decline discards is exactly `{0..35}`, disjoint | random full playouts (random seed, uniformly random legal action each step) |
| P2 | **Termination:** every random playout reaches GAME_OVER in bounded steps (deals bounded because min per-deal gain when multiplied... not guaranteed >0 for all! A deal can add 0 to everyone only if someone >60 and rest… with 2 players one is always ≤60 ⇒ +≥2; with 3+ players, all-but-one can be 0-added? one player takes >60, others 41–60 impossible for all… others get ≥2 unless… others with 41–60 get +2>0. Someone always gains ≥2 ⇒ max deals ≤ N·threshold/2). Assert both per-deal step bound and deal-count bound | as P1 |
| P3 | **Points total 120** per deal at DEAL_SCORING | as P1 |
| P4 | **Legal-action soundness:** every action sampled from `legalActions` is accepted by `reduce` | as P1 |
| P5 | **Legal-action completeness:** every random *illegal* mutation of a legal action (wrong card, wrong count, non-bijective pairing, off-turn seat) is rejected with a typed error and state unchanged | fuzzed perturbations |
| P6 | **Determinism/replay:** `replay(seed, actionLog)` from scratch equals the incrementally built state (deep-equal incl. `rngState`) | as P1 |
| P7 | **Serialization round-trip:** `deserialize(serialize(s)) ≡ s` at every step | as P1 |
| P8 | **Redaction safety:** `redact(s, seat)` never contains any CardId from another hand, the stock interior, or decline discards; `handCounts`/`stockCount` always correct | as P1 |
| P9 | **Beat predicate partial order:** `beats` is irreflexive; no card beats shoha-as-beat; shoha-as-beat beats all 35 others; within a suit `beats` is a strict total order matching `6<7<8<9<J<Q<K<10<A` | exhaustive 36×36×4-trump enumeration (not even sampled) |
| P10 | **Matching correctness:** `hasPerfectMatching` ⇔ ∃ pairing accepted by `reduce` (cross-check with brute-force ≤6! permutations) | random table/hand pairs |
| P11 | **Auto-action validity:** `deriveAutoAction` output ∈ `legalActions` in every decision state | as P1 |
| P12 | **View-derivation parity:** `legalActions(state, seat)` computed from full state equals the `legal` field computed from `redact(state, seat)` (guarantees the client can trust affordances) | as P1 |

### 6.2 Scenario unit tests (fixed fixtures, hand-built states)

Grouped by edge-case §4; each bullet = at least one test:

- **Shoha:** S1 shoha beats trump A; S2 set containing shoha-as-beat ⇒ only DECLINE legal; S3 shoha led alone beaten by 7♣; S4 shoha led, clubs trump, beaten by 8♣; S5 shoha inside rank-6 lead is ordinary; S6 shoha in decline discards reaches taker's pile.
- **Beating:** B1 trump6 vs trump7 illegal; B2 10 beats K same suit; B3 trump on non-trump any rank; B4 non-trump higher rank different suit illegal; B5 pairing where only one bijection works; B6 partial beat rejected; B7 duplicate target rejected.
- **Lead:** L1 mixed rank+suit set rejected; L2 lead > defender hand size rejected; L3 5-card suit lead accepted.
- **Trick flow:** F1 4-player double-lap chain ending on leader's second decline; F2 decline routes all cards (incl. face-down) to most-recent-set owner; F3 empty-hand seat skipped in chain; F4 2-player alternation.
- **Replenish/trump:** R1 winner draws first; R2 skip players at 6; R3 last drawn card rotates trump; R4 stock empties mid-round (A-7); R5 final trump = initial trump suit (A-1+A-6); R6 rotated rank-6 doesn't change multiplier.
- **6-player:** X1 no stock, dealer's last card trump (A-4); X2 trump-6 via dealer card ⇒ ×2/×3.
- **Endgame:** E1 lead passes when winner empty; E2 solo-cards residue → own pile (A-8); E3 short-hand forced full-hand discard.
- **Scoring:** C1–C4 the four bands incl. boundaries 60/61, 40/41; C5 empty pile +6 vs 0-point non-empty pile +4 (A-14); C6 ×2; C7 ×3 replaces ×2 (A-11); C8 0–0 first-deal triple (A-10); C9 60-60 two-player.
- **Game end:** G1 threshold 24 inclusive; G2 36-config; G3 12-0 immediate end; G4 12-0 priority over threshold, both-goat case (§4.9); G5 multiple simultaneous goats; G6 11→(+4×3)=23 near-miss.
- **Misc:** M1 golden-master full-game replay fixture (frozen JSON of seed+actions+final state, guards refactors); M2 auto-action fixtures for lead and short decline.

---

## 7. Public API (TypeScript signatures)

```ts
// ─── types (all exported) ───────────────────────────────────────────
export type CardId = number; export type Seat = number; export type Suit = 0|1|2|3;
export const SHOHA: CardId; export const ALL_CARDS: readonly CardId[];
export function cardMeta(id: CardId): CardMeta;
export function cardPoints(id: CardId): number;

export type Action =
  | { type: 'LEAD';    seat: Seat; cards: CardId[] }
  | { type: 'BEAT';    seat: Seat; pairs: { target: CardId; card: CardId }[] }
  | { type: 'DECLINE'; seat: Seat; discards: CardId[] };

export type EngineEvent =
  | { type: 'DEAL_STARTED'; dealIndex: number; dealer: Seat; trumpCard: CardId; multiplier: 1|2|3 }
  | { type: 'CARDS_DEALT'; counts: number[] }
  | { type: 'LED' | 'BEATEN'; seat: Seat; set: ThrownSet }
  | { type: 'DECLINED'; seat: Seat; discardCount: number }
  | { type: 'TRICK_TAKEN'; seat: Seat; cardCount: number; points: number }
  | { type: 'CARD_DRAWN'; seat: Seat }                       // identity redacted downstream
  | { type: 'TRUMP_ROTATED'; card: CardId; suit: Suit }
  | { type: 'STOCK_EXHAUSTED' }
  | { type: 'RESIDUE_CLAIMED'; seat: Seat; cardCount: number }        // A-8
  | { type: 'DEAL_SCORED'; pilePoints: number[]; penalties: number[]; multiplier: 1|2|3; scores: number[] }
  | { type: 'GAME_OVER'; reason: 'THRESHOLD'|'TWELVE_ZERO'; goats: Seat[] };

export type EngineError = { code:
    'E_NOT_YOUR_TURN' | 'E_WRONG_PHASE' | 'E_CARD_NOT_IN_HAND'
  | 'E_LEAD_NOT_UNIFORM' | 'E_LEAD_TOO_LARGE'
  | 'E_PAIRING_NOT_BIJECTIVE' | 'E_CARD_DOES_NOT_BEAT' | 'E_BEAT_WRONG_COUNT'
  | 'E_DISCARD_WRONG_COUNT';
  detail?: string };

export interface LegalActions {
  lead?:    { maxCount: number; rankGroups: CardId[][]; suitGroups: CardId[][] };
  beat?:    { targetSet: CardId[]; beatMatrix: Record<CardId, CardId[]>; hasPerfectMatching: boolean };
  decline?: { requiredDiscardCount: number };   // present iff it's your beat turn
}

// ─── core (pure) ────────────────────────────────────────────────────
export function initGame(config: GameConfig): { state: GameState; events: EngineEvent[] };
export function reduce(state: GameState, action: Action):
  { ok: true; state: GameState; events: EngineEvent[] } | { ok: false; error: EngineError };
export function legalActions(state: GameState, seat: Seat): LegalActions;      // {} when not to move
export function deriveAutoAction(state: GameState, seat: Seat): Action | null; // A-13
export function redact(state: GameState, viewerSeat: Seat): PlayerView;
export function legalActionsFromView(view: PlayerView): LegalActions;          // identical result (P12)

// ─── validation predicates (shared with client) ────────────────────
export function beats(beater: CardId, target: CardId, trump: Suit, targetLedAsOrdinary: boolean): boolean;
export function isLegalLead(view: PlayerView, cards: CardId[]): true | EngineError;
export function isLegalBeat(view: PlayerView, pairs: Action & {type:'BEAT'}['pairs']): true | EngineError;

// ─── scoring (pure, independently importable) ──────────────────────
export function dealPenalty(pilePoints: number, pileCount: number): 0|2|4|6;
export function dealMultiplier(initialTrumpRankIndex: number, scoresAtDealStart: number[]): 1|2|3;
export function evaluateGameEnd(scores: number[], threshold: number):
  { over: false } | { over: true; reason: 'THRESHOLD'|'TWELVE_ZERO'; goats: Seat[] };

// ─── persistence / replay ──────────────────────────────────────────
export function serialize(state: GameState): string;
export function deserialize(json: string): GameState;
export function replay(config: GameConfig, actions: Action[]): GameState;  // asserts P6
```

**Colyseus integration contract (informative):** the room holds `GameState` privately, applies client messages as `Action`s via `reduce`, broadcasts per-client `redact` diffs through Colyseus schema, forwards `events` as the animation stream, and runs turn/disconnect timers that inject `deriveAutoAction` results. Bots (post-v1) plug in as `(view: PlayerView) → Action` consumers with zero engine changes.

---

## 8. Assumption Summary (for human sign-off)

| ID | One-liner | Risk if wrong |
|----|-----------|---------------|
| A-1 | Initial trump card = stock bottom, drawn last | draw order/endgame trump |
| A-2 | Clockwise chain, multi-lap, first decline ends trick, no takeover | whole trick flow |
| A-3 | Lead ≤ defender hand; short hands discard entire hand on decline | endgame legality |
| A-4 | 6p: dealer's last card revealed = fixed trump | 6p mode |
| A-5 | Defender chooses pairing; beat is all-or-nothing | beat UX/rules |
| A-6 | Trump rotates on last card of each replenishment; frozen after exhaustion | trump timeline |
| A-7 | Short stock: winner-first round-robin, players stay short | endgame hands |
| A-8 | Solo residue cards → own won pile | ≤ a few points/deal |
| A-9 | Random first dealer; left-of-dealer leads; dealer rotates | ordering only |
| A-10 | Triple-game equality includes 0–0 pairs | scoring frequency |
| A-11 | ×3 replaces ×2 (never ×6) | scoring magnitude |
| A-12 | 12-0 checked before threshold; multiple goats allowed | game end semantics |
| A-13 | Engine ships deterministic auto-action; timers live in room | disconnect behavior |
| A-14 | Non-empty 0-point pile scores +4, not +6 | rare scoring band |

All assumptions are isolated behind named branches in `src/rules/assumptions.ts`; flipping any of them is a localized change plus flipping its dedicated test group.