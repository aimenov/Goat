# Normative corrections to the design documents

The four design documents in this directory were produced before the game's author confirmed
several rules. **Where they conflict, THIS file and `docs/RULES.md` win.**

## 1. Trick flow — full circle (supersedes design-rules.md §1.2–1.3, T5/T6 and "first decline ends trick")

The trick travels **full circle back to the leader**:

- The leader leads k cards (same rank or same suit).
- Each player clockwise, in turn, either **beats the most recent set** (cover all k cards,
  defender chooses pairing) or **discards k cards face-down**. A discard does **not** end the
  trick — the next player still chooses.
- When the turn returns to the original leader, the leader either **ends the trick** (no
  discard required) — the owner of the most recent set takes ALL table cards including every
  face-down discard — or **beats the newest set himself**, starting another circle. The
  end-decision always returns to the leader.
- Declining (discarding) is voluntary — a player who could beat may discard instead.

Engine decision points are therefore: `TRICK_LEAD`, `TRICK_RESPOND` (beat | discard),
`TRICK_LEADER_DECISION` (end | beat), `GAME_OVER`.

## 2. Equal-hands invariant (supersedes A-3/A-7/A-8 short-hand handling)

Every player always holds the same number of cards. Each circle costs every player exactly
k cards; stock size 36−6n is a multiple of the player count n, so round-robin replenishment
preserves equality. There are **no** short-hand special cases (no "discard whole hand", no
"single player left with cards" residue rule). The engine asserts equal hand sizes at every
decision point. Lead size k is legal iff k ≤ leader's own hand size.

## 3. No dealer rotation (supersedes A-9)

The winner of the **last trick of the previous deal leads first** in the next deal. The first
deal of a game has a seeded-random leader. Dealing proceeds clockwise starting from the first
leader; in 6-player mode the 36th (last-dealt) card is revealed as the fixed trump and kept by
its recipient.

## 4. Scoring bands (supersedes A-14)

`0 points → +6` — even if the pile contains cards (all zero-point ranks). Bands:
`>60 → +0`, `41–60 → +2`, `1–40 → +4`, `0 → +6`. Multipliers unchanged: first revealed trump
rank 6 → ×2; any two players with equal running scores at deal start (0–0 counts) + trump 6
→ ×3 (replaces ×2, never ×6).

## 5. Critique rulings (design-critique.md)

- **#1 state sync:** the client doc wins — no `@colyseus/schema` state sync; explicit
  per-client `snapshot` + `seq`-numbered events; `resync` on gap.
- **#2/#3:** targeted messages carry own drawn cards and face-down reveals to the trick taker.
- **#5:** server sends `hasPerfectMatching` (bipartite matching) with beat affordances.
- **#7:** reconnection is a jump-cut snapshot re-render, no fast-forward replay.
- **#9:** goat ties → highest score only; exact top ties share the loss; 12-0 checked first.
- **#10/#24:** timeout autopilot = decline with seeded-random discards; forced lead = lowest-point card.
- **#12:** reconnection window 120 s everywhere.
- **#23:** pile contents are never broadcast at deal end — scores/points only.
