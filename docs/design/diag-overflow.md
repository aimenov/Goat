Analysis complete. Both bugs traced to exact lines; findings and minimal fixes below.

---

## BUG 1 — RenderFlex overflow at table_screen.dart:1073

**The Row** (`_myArea`, `app/lib/features/game/table_screen.dart:1073-1107`) children, in order:

1. `Text('Вы')` — fixed, bold, ~22px
2. `SizedBox(width: 8)`
3. `AnimatedScoreChip(prefix: 'Очки: ', value: me?.score ?? 0)` (`app/lib/shared/widgets/brass_chip.dart:68`) — **grows**: score is 1 digit at game start, becomes 2 digits after a few deals (score limit 24/36; user's rules add +6 bands). Container padding 8+8 plus `CountUpText`.
4. `SizedBox(width: 8)`
5. `ActionChip` "Взятки: N" (line 1085) — **grows**: `state.myWonPile.length` goes 0 → 10+ within a deal (two digits), plus 16px `Icons.layers` avatar and Material chip padding. Even with `visualDensity: compact` this is the widest child (~95-100px at 2 digits).
6. `Spacer()` — collapses to 0, cannot prevent overflow of fixed children.
7. Conditional `Text(myBubble, fontSize: 22)` — **appears transiently**: reaction emoji bubble (`_bubbles[state.mySeat]`), ~26px when a reaction fires.

**Why 188px:** the Row's only width constraint is the screen. Chain: `Row ← Padding(horizontal: 12×2) ← Column ← SafeArea` (table_screen.dart:392-416). 188 + 24 = **212 logical px viewport width** — the user is running the web app in a very narrow window / mobile-emulation. Nothing in `_myArea` clamps or flexes, so fixed content (~22+8+~76+8+~95 ≈ 209, +26 with bubble) exceeds 188 exactly when score and взятки hit two digits and/or a reaction bubble shows — hence "after a few deals".

**Fix (preserves casino design + column alignment):** none of the children may be hard-truncated (numbers ellipsized look broken), so scale-down is the right tool. Replace the fixed left group with an `Expanded → FittedBox(scaleDown)`:

```dart
Row(children: [
  Expanded(
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Вы', ...),
        SizedBox(width: 8),
        AnimatedScoreChip(...),
        SizedBox(width: 8),
        ActionChip(...),   // keep key: _anchors.wonChip
      ]),
    ),
  ),
  if (myBubble != null) Text(myBubble, style: TextStyle(fontSize: 22)),
])
```

`Spacer` is removed (Expanded provides the gap); chips render pixel-identical until space runs out, then shrink a few percent instead of overflowing. The `_anchors.wonChip` GlobalKey stays on the ActionChip so flight animations still target it. Optional extra headroom: drop the "Взятки: " word to the icon + count (`'×N'`) below ~360px, but FittedBox alone fixes the reported 15px.

---

## BUG 2 — stuck at connection screen after reload

### Dead-end #1 (the reported one): reload on `/table` → permanent "Подключение…"

- go_router restores the URL on web reload → `TableScreen` mounts directly (`app/lib/main.dart:63-67`; `initialLocation: '/login'` only applies to a bare URL).
- `GameUiState` defaults to `roomPhase: RoomPhase.connecting` (`app/lib/core/game/models.dart:172`), and `RoomSession.build() => null` (`app/lib/core/session.dart:76`). **Nothing anywhere calls `reconnect()` on startup** — grep confirms there is no "Вернуться в игру" button; `session.reconnect()`'s only caller is the reconnect-overlay button, which is unreachable in `connecting` phase.
- `_connectingOverlay()` (table_screen.dart:1426-1437) is a full-screen `FeltBackground` with spinner + "Подключение…" and **zero buttons, zero timeout**. `TableScreen.initState` (line 94) never checks for a missing room. → infinite spinner. This is exactly what the user hit.

**Fix (minimal):**
- In `TableScreen.initState` (or a router redirect on `/table`): if `ref.read(roomSessionProvider) == null`, call `roomSessionProvider.notifier.reconnect()`; on failure (`catch`), clear the token and `context.go('/lobby')`.
- Independently, add an escape to `_connectingOverlay`: an outlined "В лобби" button (calls `roomSessionProvider.notifier.leave()` then `context.go('/lobby')`) plus a ~10s timeout that swaps the spinner for "Не удалось подключиться" + the same button.

### Dead-end #2: `RoomPhase.reconnecting` with a dead token

- Server holds the seat 120s; past that (or after room disposal) `matchmake('reconnect', …)` returns 4xx → `GoatTransportException` (`app/lib/core/net/transport.dart:172-175, 197-203`).
- `_reconnectOverlay()` (table_screen.dart:1816-1852) offers **only** "Переподключиться". On failure: snackbar "Не удалось переподключиться", overlay stays, phase stays `reconnecting` forever. **No "В лобби", no timeout, no auto-retry.** The full-screen `Container` blocks the table underneath.
- `RoomSession.reconnect()` (session.dart:107-113) **never clears a dead token** — it's removed only in `leave()` (line 126) — so retries fail identically forever.

**Fixes (minimal):**
- Add "В лобби" `OutlinedButton` to `_reconnectOverlay`: `await roomSession.leave(); if (mounted) context.go('/lobby');` (leave() already removes the token and detaches the controller).
- In `RoomSession.reconnect()`: on `GoatTransportException` from matchmake (dead token / disposed room), `prefs.remove('reconnectionToken')` before rethrowing, and surface a distinct message ("Стол уже закрыт") so the UI can stop offering retry.
- Optionally auto-attempt reconnect once when `roomPhase` flips to `reconnecting`, with the manual button as fallback.

### Secondary bug: stale `onClose` callback

`GameController.attach` (`app/lib/core/game/game_controller.dart:41-44`): `room.onClose.then(...)` never verifies the closing room is still the attached one. A late non-4000 close of a *previous* room flips a healthy new session into `reconnecting`. Guard: `room.onClose.then((code) { if (!identical(_room, room)) return; ... })`.

### `flt_force_cpu` (app/web/flutter_bootstrap.js)

- Once the shader trap trips (line 34), `sessionStorage['flt_force_cpu']='1'` persists for the **tab's lifetime** — every reload in that tab, including manual ones, silently runs `canvasKitForceCpuOnly` (line 25-26: the flag wins even if `webgl2Usable()` is now true). Presentation: not a hard stuck screen, but software-rendered CanvasKit — multi-hundred-ms frames, janky spinner, high CPU; on a weak machine the connection screen can *look* frozen. Only signal is a `console.warn`. It is plausible this compounded the user's stuck impression, but the true freeze is dead-end #1 (state machine, not rendering).
- **Fixes:** (a) distinguish the automatic reload from manual ones: when tripping, also set a one-shot `flt_cpu_reload=1`; on load, if `flt_force_cpu` is set but `flt_cpu_reload` is absent (manual reload) **and** `webgl2Usable()` returns true, clear the flag and retry GPU. (b) When CPU mode is active, inject a small dismissible DOM banner ("Включён режим совместимости — графика может работать медленно. Нажмите, чтобы попробовать снова") whose click clears the flag and reloads.

---

### Culprit summary (file:line)

| # | File:line | Problem | Fix |
|---|---|---|---|
| 1 | `app/lib/features/game/table_screen.dart:1073` | Row: score chip + "Взятки: N" chip + emoji bubble outgrow 188px | Expanded+FittedBox(scaleDown) around left group; bubble outside |
| 2 | `app/lib/features/game/table_screen.dart:1426` | `_connectingOverlay` — no exit/timeout; shown forever after reload on /table | timeout → error + "В лобби" button |
| 3 | `app/lib/features/game/table_screen.dart:94` | no startup reconnect attempt despite stored token | initState: if room==null → reconnect(), on fail clear token + go('/lobby') |
| 4 | `app/lib/features/game/table_screen.dart:1816` | `_reconnectOverlay` — retry-only, no escape | add "В лобби" (leave + go('/lobby')) |
| 5 | `app/lib/core/session.dart:107` | dead reconnectionToken never cleared on failure | remove token on matchmake failure |
| 6 | `app/lib/core/game/game_controller.dart:41` | stale onClose can flip new session to reconnecting | `identical(_room, room)` guard |
| 7 | `app/web/flutter_bootstrap.js:25,34` | flt_force_cpu sticks for tab life, silent slow CPU rendering | re-probe GPU on manual reload; visible banner when CPU mode active |