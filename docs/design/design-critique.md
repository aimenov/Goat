## 1. Defects & Contradictions

**CRITICAL**

1. **State-sync architectures are mutually exclusive.** Server doc §2 builds the entire private-state design on `@colyseus/schema` StateView (`@view()` hands/wonPile, delta patches, "reconnection automatically re-sends the filtered snapshot"). Client doc §1.2 explicitly **bypasses schema sync entirely** ("server keeps its Colyseus schema state minimal/empty"), relying on a custom `Snapshot` + `seq`'d events + `resync` protocol that the server doc **never defines** (no `seq`, no `Snapshot` message, no `resync` handler). One of the two designs must be rewritten before any coding starts. Everything in server §2.2–2.3 and §5.3–5.4 is moot under the client's plan.

2. **Owner-drawn card identity never reaches the client.** Server `card_drawn`: "the drawn card reaches the owner via hand patch" — but the client doesn't decode patches. Under the client's protocol there is no targeted message carrying the drawn card. Every replenishment breaks. (Direct casualty of #1, but worth its own line because it's silent data loss, not a crash.)

3. **Taker can never review face-down discards in their won pile — but the rules say won piles are owner-reviewable and include the face-down discards.** Server: discards "never enter the schema at all"; `trick_taken` carries `faceUpCards` + `faceDownCount` only; client §4.10 claims "client already knows own pile contents from events" — false for face-downs. The taker's peek sheet and live point subtotal will be wrong. Engine's `myWonPile` handles this correctly but nothing transports it. Needs a targeted reveal-to-taker message (and a human ruling on whether the taker may see them mid-deal at all).

**HIGH**

4. **Legal-actions payload: three incompatible shapes, and the server doc forgets to send it at all.** Engine: `LegalActions {lead:{maxCount,rankGroups,suitGroups}, beat:{beatMatrix,hasPerfectMatching}, decline:{requiredDiscardCount}}` embedded in `PlayerView`. Client requires `leadable:{byRank,bySuit}` + `beatMap` + `canDecline` "with every turn state". Server doc's `turn_started` payload is `{seat, deadline, mustCover}` — no legal actions anywhere in §4.2.

5. **Client's `beatMap` is insufficient to know whether BEAT is possible.** Per-target candidate lists do not imply a perfect matching exists (engine doc §4.3 gives the exact counterexample and computes `hasPerfectMatching` via Hopcroft–Karp for this reason). Client §2.5 says it can derive "whether a full cover exists" from `beatMap` — it can't, unless it implements bipartite matching in Dart (which it swore off). The flag must be server-sent.

6. **Reconnection cannot rebuild the mid-trick table.** Server schema `ThrowSet` has only `{bySeat, cards}` — no `kind` (lead vs beat), no `pairing`. The pairing exists only in the transient `beaten` broadcast. A reconnecting client cannot render covered pairs, cannot tell which set is "most recent", and cannot apply shoha-led-as-ordinary semantics. Engine's `redact` requirement (§4.10, P8) explicitly demands mid-trick pairing reconstruction; the server schema violates it.

7. **Reconnect "fast-forward" is unimplementable as specced.** Client §8 promises replaying missed moves as accelerated animations, but both server designs resend only a state snapshot. You cannot reconstruct an action sequence from a state diff. Needs a server-side per-room event journal keyed by `seq` (engine's `actionLog` exists but is not exposed by any protocol) — or drop the feature and jump-cut.

8. **Engine doc contradicts itself on empty-handed defenders: T6 vs §4.6.** T6 says an empty-handed defender is "auto-forced DECLINE{[]}" → TRICK_RESOLVE (ends the trick!). §4.6 says empty seats are **skipped silently** ("else they'd end every trick") and T3/T4's "next *active* seat" makes T6 unreachable. Pick one; they produce different games.

**MEDIUM**

9. **Threshold tie-break conflict.** Engine A-12: *all* players ≥ threshold are goats. Server A11: "the highest score is the goat; if still tied, all tied". Different results whenever two players cross with different scores in one deal.

10. **Timeout auto-action: three different policies.** Engine A-13: lead lowest-point card; decline k lowest-point cards (deterministic). Server A14: lead lowest **non-trump** card (undefined if hand is all trumps). Client A7/§4.9: decline with **random** discards (breaks engine determinism/replay). Must converge on one — and note the leak in item 24.

11. **RNG contradiction.** Engine: seeded xoshiro, serialized `rngState`, replay/determinism guarantees. Server §5: "Shuffle uses server-side CSPRNG (`crypto.randomInt` Fisher–Yates)". Resolvable (CSPRNG generates the *seed*), but as written the server bypasses the engine's shuffle and destroys replay.

12. **Reconnection window: server 120 s, client "e.g. 60 s".** Opponents' seat countdowns will be wrong.

13. **Lead cap missing downstream.** Engine A-3a caps lead size at defender's hand size; server §4.1 `lead` validation ("1+ cards, same rank OR suit, in hand") omits it; client's `leadable {byRank, bySuit}` payload carries no `maxCount`, so the UI will offer illegal oversized leads in the endgame.

14. **Ack protocol mismatch.** Server: `cmd_result {reqId, ok, error}` with error codes `NOT_YOUR_TURN…`. Client: `IntentAccepted/IntentRejected(actionId, reason)`. Also `emote` vs `react`. Also engine error codes (`E_*`) are a third vocabulary. One protocol file, one naming.

15. **Missing protocol messages the client UX depends on:** rematch votes (§3.6), deal-end collective "Ready"/skip (§3.5), achievement catalog + progress fetch (§7.2 — server only pushes unlocks), turn-timer room option (client offers 15/30/45 s at creation; server `update_options` has no timer field and A14 says "configurable later"), `swapSeat` (promised in server §3.2, absent from its own message table), peek "eye icon" notification (client §4.10 shows opponents an icon but also says peeking is client-side only — internally contradictory).

16. **Server phase enum vs engine phases.** Schema: `lobby|trick|replenish|dealEnd|gameEnd`; engine persists only `TRICK_LEAD|TRICK_BEAT|GAME_OVER` (replenish is an auto-phase that never persists). `trick` also loses the lead/beat distinction the client needs for affordances.

17. **Triple/parallel authoritative hand state.** Server room keeps `secret.hands` Map **and** schema `hand` ArraySchemas **and** the engine's `GameState.players[].hand`. Engine doc says the room holds `GameState` privately and derives everything; server doc's `GoatRoom.secret` looks like a second rules-adjacent implementation (`GoatEngine.applyAction` vs engine's `reduce` — even the API name differs). Drift is guaranteed.

18. **"Client never re-implements rules" vs shared predicates vs client refusal.** Engine principle 3 + exported `isLegalLead/isLegalBeat` "shared with client" (TS — Dart can't consume them); server §5.1 assumes "client can pre-validate with the mirrored rules"; client mirrors only the 5-line selection-shape validator. The optimistic-UI rejection rate assumptions in server §5.1 rest on validation the client won't have.

19. **Custom Dart transport vs 0.17 protocol drift.** Client hand-rolls the WS envelope claiming it's "stable for years", while the server doc targets brand-new 0.17 (whose own caveat admits protocol churn: schema v3→v4, new lifecycle). The golden-byte-fixture test (client §9.1) helps but pin the server version *now*; this decision gates both repos.

**LOW**

20. **Emoji sets and rate limits differ** (server: ~12 ids, burst 3 / refill 1 per 2 s / 30 per min cap; client: 8 ids, flat 1 per 2 s).
21. **`card_drawn` payload written as `{seat}` / `{seat, card}`** without saying which variant goes where; if the `card` variant is ever broadcast (e.g., trump-reveal draw is public, others aren't) fine, but as written it reads like an accidental leak. Specify.
22. **Client shows "Trick count: 3" for opponents' piles** — per-trick grouping isn't in any state/protocol and is lost on reconnect even for one's own pile.
23. **`deal_ended.wonPileReveal` broadcasts full pile contents of everyone** — a design addition beyond the rules (which only require owner review). Probably fine; confirm.
24. **Deterministic auto-decline leaks face-down discard identities**: everyone knows autopilot discards the k lowest-point cards, so a timeout decline's "face-down" cards are inferable by all. Tension between engine determinism (A-13) and secrecy; consider seeded-random-from-rngState discards instead.
25. **Turn timer vs animation choreography**: server arms the 30 s (or 15 s!) deadline at `turn_started`, but the client plays multi-second sequences (per-card draws, trump flourish, trick vacuum) before the player can act. On 15 s timers this materially eats decision time. Client pads only for RTT.
26. **Engine §7 typo:** `isLegalBeat(view, pairs: Action & {type:'BEAT'}['pairs'])` is malformed TS.

## 2. Unhandled game situations

1. **Every hand empty after a successful beat mid-chain** (e.g., 2p endgame: leader leads last k cards, defender beats with their last k): no active seat remains to decline. Engine defines no auto-resolve; `defender = next active seat` is undefined. Must specify: trick auto-resolves to the last set owner.
2. **Chain wraps to the owner of the most-recent set** (all other seats empty-handed after skips): may a player beat their own set? Presumably no → auto-resolve; nothing says so.
3. **Auto-lead when the hand is all trumps** under server A14's "lowest non-trump" rule — undefined.
4. **Initial trump reveal is the shoha itself** (6♣ turned up): clubs trump, ×2/×3 fires, shoha publicly located at stock bottom. Mechanically covered but no test listed; confirm no special house rule.
5. **6-player mode, dealer's 36th card is the shoha**: trump = clubs and the dealer publicly holds the unbeatable card all deal. Confirm acceptable.
6. **Lead cap when the first active defender changes** between legality-check and action (a decline/skip resolution reordering seats) — cap is defined against "nextActiveDefender"; specify it's evaluated at lead time only.
7. **2-player 12-0 wording**: "an opponent still at 0" — with 2 players the +0 winner stays at 0 for many deals; a ×3 deal can put the other player from 0 to ≥12 in two deals. Confirm the instant-goat rule really is wanted for 2p (it will end a lot of 2p games abruptly).
8. **Both end conditions in one deal for the *same* player set** — engine §4.9 pins A+B both goats via TWELVE_ZERO; server A11 would answer differently (defect #9). Unresolved until the human rules.
9. **Room dies mid-game (deploy/crash) with no Redis presence in v1**: reconnection tokens are process-local; the drain strategy is described but the client's "room fatal" taxonomy needs a distinct "server restarted, game lost" path (no stats? voided? unspecified — only all-abandoned voiding is).
10. **Late-rejoin after the 120 s window**: server calls it a nice-to-have to skip; client splash promises "Return to game?" from a persisted token — dead token after window expiry, but the room may still be alive with the seat on autopilot. Define: is the seat recoverable via `joinById` in v1 or not?
11. **Kick/seat race**: `kick` is lobby-only; a player who disconnects in lobby vs mid-countdown (auto-start 5 s) — is the countdown cancelled? Unspecified.
12. **Replenish when the trick winner's hand is already <6 but stock has fewer cards than total deficit** — covered by A-7 draws, but the *reveal* rule "last card drawn this phase becomes trump" when only ONE card is drawn total (stock had 1): that lone card is both a private draw and the public trump reveal → its identity is public in one specific hand. Intended? (Same class as A-6 generally, but the 1-card case is the sharpest.)

## 3. Questions for the human designer (must answer before coding)

1. **Trump card fate (A-1):** face-up under the stock, drawn last, taken into hand — confirm. (All three docs agree; UI is built on it.)
2. **Chain flow (A-2/A-3):** clockwise, wraps past the leader, first decline ends the trick, no takeover by later players — confirm. Also: **may the chain reach the owner of the most-recent set, and who takes the trick if everyone runs out of cards mid-chain?** (§2 items 1–2.)
3. **Lead size cap:** may a lead exceed the next defender's hand size? If yes, what does a short defender do — current assumption: decline dumps their entire hand.
4. **Pairing (A-5):** does the defender choose which card covers which, and is the beat strictly all-or-nothing?
5. **6-player trump (A-4):** dealer's last card revealed as fixed trump — confirm (and the shoha-as-that-card case).
6. **Trump rotation (A-6):** is the trump re-revealed after *every* trick's replenishment (last card drawn that round), or only when the actual final stock card is drawn?
7. **Triple game (A-10):** does 0–0 count as "equal scores" (making every first-deal trump-6 a triple)? 
8. **Multiplier stacking (A-11):** ×3 replaces ×2 — never ×6 — confirm.
9. **Non-empty pile worth 0 points (A-14):** +4 or +6?
10. **Game-end tie-breaks:** if several players cross 24 in one deal, are all of them goats, or only the highest score (engine and server docs disagree)? And in a simultaneous 12-0 + threshold deal, which rule wins, and is *every* player ≥12 a goat?
11. **Residue rule (A-8):** last player holding cards — own pile, or last trick winner's pile?
12. **May the trick taker review the face-down discards inside their won pile mid-deal** (rules literally say piles are owner-reviewable), and may all piles be publicly revealed at deal end?
13. **Timeout policy:** what should autopilot do (lowest-point vs random discards — note deterministic discards are inferable by opponents), and is turn length room-configurable in v1 (client UI says 15/30/45 s)?
14. **Reconnection grace period:** 60 or 120 seconds?
15. **Audience geography** → deployment region; and approve pinning Colyseus to whichever protocol version the (custom) Dart transport is written against.
16. Decide the state-sync architecture (defect #1) — this is a locked-decision-level conflict between the server and client docs, not a rules question, but it needs an owner ruling now.