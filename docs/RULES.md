# Козёл (Goat) — Normative Game Rules

Canonical rules for this implementation, confirmed by the game's author. The engine in
`packages/engine` implements exactly this document.

## Setup

- 36-card deck: ranks 6, 7, 8, 9, J, Q, K, 10, A in four suits (♠ ♣ ♦ ♥).
- 2, 3, 4, or 6 players; individual play (no teams).
- Rank order, low → high: **6 < 7 < 8 < 9 < J < Q < K < 10 < A** (the ten outranks K/Q/J).
- Card points: A=11, 10=10, K=4, Q=3, J=2, ranks 6–9 = 0. Deck total = 120.
- Each player is dealt 6 cards, one at a time, clockwise starting from the first leader.
  - 2–4 players: the first undealt card is revealed = initial **trump suit**, then placed
    face-up at the **bottom of the stock** (it is drawn last). The remaining undealt cards
    form the face-down stock.
  - 6 players: all 36 cards are dealt; the 36th (last-dealt) card is shown to everyone =
    fixed trump for the whole deal, and its recipient keeps it. No stock.
- The rank of the first revealed trump card (`initialTrumpRank`) is remembered for scoring.
- First deal of a game: the leader is chosen at random (seeded). Every subsequent deal is led
  by the winner of the **last trick of the previous deal**. There is no rotating dealer.

## The trick (full circle)

1. **Lead.** The leader plays 1+ cards, all of the same rank OR all of the same suit
   (k = number of cards led; k ≤ leader's hand size). A 6♣ (шоха) in a lead is an ordinary card.
2. **Respond.** Each following player clockwise, in turn, chooses one of:
   - **Beat** the most recent set: cover each of its k cards with a strictly higher card of the
     same suit, or a trump on a non-trump. The responder chooses which card covers which.
     Beating is all-or-nothing (cover all k or don't beat). The **шоха (6♣)** as a beating card
     beats anything — including the trump ace — and can never itself be beaten.
   - **Discard** k cards of their choice face-down onto the table. This does NOT end the trick.
   Declining is voluntary: a player who could beat may discard instead.
3. **Leader decision.** When the turn returns to the original leader, they either:
   - **End the trick** (no discard required): the owner of the most recent beat set (or the
     leader themselves, if nobody beat) takes ALL table cards — led, beaten, and every
     face-down discard — into their won pile; or
   - **Beat the newest set themselves**, starting another full circle (the end-decision always
     comes back to the leader).
4. Won piles: a player may review their own pile at any time (including face-down cards they
   collected). Piles are never shown to other players; only counts/points are public at deal end.

**Equal-hands invariant:** every player always holds the same number of cards; the engine
asserts this at every decision point.

## Replenishment & trump rotation (2–4 players)

After each trick, players draw back up to 6 cards, one card at a time round-robin, **starting
with the trick winner**. The **last card drawn in each replenishment round is shown to all: its
suit becomes the new trump**. When the stock empties, the trump is frozen (the final trump is
the initial trump card's suit, since it sits at the stock bottom). Trump *rank* re-reveals do
not change the scoring multiplier — only the first revealed trump card of the deal counts.

The trick winner leads the next trick. The deal ends when all hands are empty.

## Deal scoring

Each player counts the card points in their won pile:

| Card points | Penalty added to running score |
|---|---|
| more than 60 | +0 |
| 41–60 | +2 |
| 1–40 | +4 |
| **0 points** (even if the pile has zero-point cards) | +6 |

Multipliers, decided at deal start:
- First revealed trump card of the deal has rank **6** → all additions ×2.
- Additionally, if **any two players had equal running scores** at deal start (0–0 on the first
  deal counts) and the first trump was a 6 → additions ×3 ("triple game"; replaces the ×2,
  never ×6).

## Full game

Deals repeat, penalties accumulate. Endings, checked in this order after each deal:

1. **12-0 instant rule:** if any player's score is ≥ 12 while some opponent is still at 0, the
   game ends immediately — the highest-scoring such player is the goat.
2. **Threshold:** score limit 24 (default) or 36 (room option). If one or more players reach
   it, the single player with the **highest** score is the goat; exact ties at the top share
   the loss.

Everyone who is not a goat wins.
