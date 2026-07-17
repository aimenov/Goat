I've completed a full static trace. Here is the finding: the empty-state first build of `TableScreen` is fully guarded — every path the caller flagged is already safe — and the real throw candidates live in the create-sheet teardown on the lobby side, which is why the flash accompanies "Создать стол" specifically.

## Part 1 — Audit of the flagged empty-state paths (all guarded, verified line-by-line)

First build after `context.go('/table')` runs with `GameUiState(roomPhase: lobby, mySeat: -1, playerCount: 0, seats: [], lobbySeats: [], myHand: [], trick: null, legal: null, deadline: 0)` (set in `attach()` at `app/lib/core/game/game_controller.dart:39` *before* navigation — `session.dart:115-118` runs `_adopt` before `_guarded` calls `go`, `lobby_screen.dart:83`).

- `app/lib/features/game/table_screen.dart:675-677` `_opponentsArea` — returns `SizedBox.shrink()` when `playerCount <= 1 || mySeat < 0 || seats.isEmpty`; the `% state.playerCount` at :680 is unreachable with playerCount 0. Guarded.
- `table_screen.dart:1446-1448` `_lobbyOverlay` — `lobbySeats.first` only behind `state.lobbySeats.isNotEmpty`. Guarded.
- `table_screen.dart:235-243` `_nick` — loops with fallback `'Игрок ${seat+1}'`, no indexing; :246 `_initial` guards empty string. Guarded.
- `table_screen.dart:902-916` `_centerArea` — lobby phase short-circuits to `'Ждём…'` (`turn = trick?.turn ?? -1`); `_chains` (:266-268) checks `trick.sets.isEmpty` before `.first`. Guarded.
- `table_screen.dart:1050` `_timerStrip`, :1219-1222 `_actionBar`, :1401 `_reactionBar`, :1114-1116 `_handWidget` — all early-return on empty/lobby state. `state.seats[mySeat]` is never indexed anywhere; `_myArea` (:1062-1066) loops and tolerates `me == null`.
- `game_controller.dart:296` `firstWhere` — has `orElse`. Guarded.
- `_dealOverlay`'s `lastDealResults!` (:1552) is behind the null check at :432-434.
- `TableFx`/`FlightLayer` pre-attach: inert. `TableFx.handleEvent` wraps everything in post-frame + try/catch (`anim/table_fx.dart:46-54`); `FlightLayer` builds `SizedBox.expand` with zero effects (`anim/flight_layer.dart:204-207`); `TableAnchors` resolution is null-safe (`anim/table_anchors.dart:24-30`).
- Snapshot cannot flip the lobby to `playing` prematurely: server `sendSnapshot` early-returns when `!this.game` (`packages/server/src/rooms/GoatRoom.ts:388-390`), so `resync` in lobby is a no-op.
- The fade-through builds both screens concurrently, but there are no shared GlobalKeys/hero tags between LobbyScreen and TableScreen (`main.dart:19-48`; the FAB heroTags `quickJoin`/`createRoom` have no counterpart on `/table`).

Note also: `app/test/table_stability_test.dart:29-37` mounts the lobby with `mySeat: 0` and 3 seats — it never covers the true `-1`/empty first frame, but per the audit above that frame is safe anyway.

**Conclusion: the red screen cannot originate from the empty-state first build of TableScreen.** The exception is thrown by the *outgoing* machinery that coexists with it during the 280 ms fade-through.

## Part 2 — Ranked throw candidates (the real ones)

**1. `app/lib/features/lobby/lobby_screen.dart:182` — `nameController.dispose()` while the bottom sheet is still mounted and animating out.**
`Navigator.pop(sheetContext, true)` (:171) completes the `showModalBottomSheet` future immediately; the sheet's ~200 ms exit animation continues with the `TextField` (:161-167) still holding the controller. `createRoom` on localhost resolves in tens of ms, so `dispose()` lands mid-exit. The sheet content also *rebuilds* during exit whenever `MediaQuery.of(context).viewInsets.bottom` (:116) animates (keyboard dismissing after typing a name), and blur-time controller access (`clearComposing`→`notifyListeners` on a disposed ChangeNotifier) throws `A TextEditingController was used after being disposed` — rendering ErrorWidget over the sheet subtree, which then vanishes exactly when the sheet finishes unmounting. Matches "flashes briefly, then everything works."
Minimal fix: don't dispose there. Either hoist `nameController` into `_LobbyScreenState` and dispose in `dispose()`, or replace :182 with a deferred `Future.delayed(const Duration(seconds: 1), nameController.dispose);` after the route is fully gone.

**2. `app/lib/features/lobby/lobby_screen.dart:83` — `context.go('/table')` while the sheet's pageless route is still mid-pop on the same Navigator.**
GoRouter swaps the page list (LobbyPage → TablePage) while a popping pageless route associated with the removed page is still in transition; `Navigator.updatePages` assertions in this window throw at Navigator level (whole-screen red) and self-heal on the next Navigator rebuild when the route entry finishes disposing. Minimal fix: complete the sheet teardown before navigating — perform `createRoom` *inside* the sheet's button callback and pop only on success, or await one transition beat (`await Future<void>.delayed(const Duration(milliseconds: 250));`) before `context.go('/table')` in `_guarded` when coming from the sheet.

**3. Latent, non-crashing race worth fixing while there:** `app/lib/core/net/transport.dart:54` — `_messages` is a broadcast controller, so any `lobby` event framed before `attach()` subscribes (`game_controller.dart:40`) is silently dropped, and the client's `resync` returns nothing in lobby (`GoatRoom.ts:390`). Today microtask ordering makes the subscribe win, but if it ever loses, the table lobby shows an empty seat list until the next ready toggle. Guard: have the server answer `resync` pre-start with a per-client lobby message (add an `else this.broadcastLobby()`-to-client branch at `GoatRoom.ts:166-168`).

## Answers to the specific questions

- No code indexes `state.seats[mySeat]`, divides by `playerCount`, uses `firstWhere` without `orElse`, or reads `lobbySeats.first` unguarded — exact guard lines above.
- **joinRoom/quickJoin: the flash should NOT occur there.** Both candidates #1 and #2 are create-sheet-specific (no bottom sheet, no TextEditingController, no pageless route in those flows). This is the cheapest diagnostic: if "Быстрая игра" never flashes, the sheet-teardown diagnosis is confirmed; if it *does* flash, capture the console text — the exception remains in the debug console after the red screen clears, and its first "The relevant error-causing widget was" line will name the widget precisely.