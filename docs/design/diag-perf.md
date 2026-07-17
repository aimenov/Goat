All files read. Here is the audit.

## Root-cause summary

The single biggest structural issue is **misplaced RepaintBoundaries around the per-frame animators**: `IdleLift` and `PulseGlow` put the boundary *outside* the widget that mutates every frame, so the expensive child (full `CardFacePainter` / opponent tile) re-paints at 60fps instead of being cached as a layer and recomposited. Second: **nothing bounds repaints of the static table**, so the 4 Hz `TurnCountdown` tick, score-chip pops, and hover lifts each dirty the *entire screen's* layer. Third: **every server event rebuilds the whole table** (root `ref.watch` + an unconditional `setState` in the state listener), which during a deal means ~24 full-tree rebuilds in ~1 s on top of 24 flights.

Also quantified: `flutter run -d chrome` is a **DDC debug build** — unminified JS, assertions, debug checks in build/layout/paint, no dart2js optimization. Frame times are routinely **5–10× worse than release**; CanvasKit first-use shader compiles also stall more in debug. Nothing below should be judged until measured in profile/release (commands at the end) — but the findings below are real costs in release too.

## Ranked optimization list

**1. Move RepaintBoundary inside IdleLift/PulseGlow (boundary is on the wrong side of the per-frame mutation)**
- `app/lib/features/game/anim/motion_widgets.dart:211-229` (IdleLift) and `:74-111` (PulseGlow).
- IdleLift: `RepaintBoundary → AnimatedBuilder → Transform.translate → CardFace`. The per-frame `Transform` dirties the boundary's whole subtree, so **every enabled hand card runs the full CardFacePainter (gradient `createShader`, rank paint, 4+ glyph paths) plus its AnimatedContainer shadow at 60fps whenever it's your turn** — ~8-10 full card paints per frame. Same for PulseGlow: the whole opponent tile (avatar, texts, 4 `_LatticePainter` card backs, chips) repaints at 60fps for the whole game (someone always has the turn).
- Fix: `AnimatedBuilder(child: RepaintBoundary(child: widget.child), builder: (_, child) => Transform.translate(..., child: child))` — the cached layer is then only re-composited. Same inversion for PulseGlow (`DecoratedBox(child: RepaintBoundary(...))`).
- Impact: **very high** (largest steady-state raster cost). Effort: trivial (~6 lines).

**2. Add RepaintBoundaries around the perpetual animators and the static sections**
- `table_screen.dart:1051` (TurnCountdown usage; its 250 ms `Timer.periodic` + `setState` at `:1908` repaints the **entire screen** 4×/s because there is no boundary between it and the root — FeltBackground and FlightLayer are the only bounded layers), `:784`/`:1083` (`AnimatedScoreChip` → `PunchIn`/flash animate per frame on change, `brass_chip.dart:132-151`), `:1092` (won-pile PunchIn), and the deal overlay (`:1551` — N rows × 3 `CountUpText` repaint the whole stack for ~2 s).
- Fix: wrap `TurnCountdown`, each opponent tile, the hand strip, the trick area, and the deal-overlay card in `RepaintBoundary`. Also wrap the static `CardFace`s in `_chainWidget` (`:989`) and `_handWidget` (`:1151`, when IdleLift disabled) — **static cards are currently not repaint-bounded anywhere**; flights are (`flight_layer.dart:108`), hand cards only transitively via IdleLift when enabled.
- Impact: **high**. Effort: low (~10 wrap sites).

**3. Split the root build with Riverpod `select()` / per-section Consumer widgets**
- `table_screen.dart:376` watches the whole `gameControllerProvider`; every `copyWith` in `game_controller.dart` (each `cardDrawn`, `yourDraw`, `led`, `turnChanged`, `connected` flap…) rebuilds `_topBar`, `_opponentsArea`, `_centerArea`, `_myArea`, `_actionBar`, `_reactionBar` — all plain methods, zero const separation. During the deal: ~24 events → 24 whole-tree rebuilds interleaved with flights.
- Also `table_screen.dart:147`: `_onGameState` calls `setState` **unconditionally** on every state change even when no local field changed — move the `setState` inside the conditionals.
- Fix: promote sections to `ConsumerWidget`s watching `select((s) => …)` slices (opponents: seats+turn; hand: myHand+legal+isMyTurn; top bar: phase/stock/multiplier/trump).
- Impact: high in debug, medium in release (build cost, GC pressure). Effort: medium (mechanical refactor, keep the GlobalKey anchors on the same elements).

**4. Trim CardFace's per-card implicit-animation stack**
- `card_face.dart:66` and `:143`: **two nested `AnimatedContainer`s per card** = 2 AnimationControllers + tickers per card (~25-35 cards on a busy table → 50-70 tickers), plus decoration diffing per rebuild. Answer to the specific question: rebuilds do **not** restart implicit animations (they only animate when target values change), so the 150 ms duration isn't a per-rebuild storm — the cost is the ticker/element overhead and per-rebuild diffing.
- Fix: when `onTap == null && !selected` possible (trick chains, trump plaque, won-pile sheet, flights!) use a plain `Container`; replace the translate-AnimatedContainer (`:143`) with a single `AnimatedSlide` applied only for the selectable hand path. Note flights construct full stateful `CardFace`s (`table_fx.dart:168, 260`) — a `const`-friendly "StaticCardFace" (plain Container + CustomPaint) for flights removes 2 controllers + ClipRRect churn per flight spawn.
- Impact: medium. Effort: low-medium.

**5. Rasterize card faces once per (card, size-bucket) — `Picture → toImageSync` cache**
- Feasible and complementary to the LRU TextPainter cache (`card_face.dart:188-219`): record `CardFacePainter` into a `ui.PictureRecorder` at bucketed heights (36/46/64/72/84/92/100 already enumerate the real sizes), `Picture.toImageSync()` (GPU-resident on CanvasKit, synchronous), LRU ≤ ~64 images, `drawImage` in flights and static cards. Kills the first-paint spike of the deal burst (24 cold card paints + shader compiles within ~1 s) and makes option 8 possible. DPR-scale the raster (`height * devicePixelRatio`) to stay crisp.
- After fixes 1-2, per-frame repaints already stop, so this mainly buys **deal-burst smoothness and first-use shader-compile avoidance on web**. Impact: medium-high on web/low-end mobile. Effort: medium (one cache class + two call sites).

**6. Web deal-burst tuning**
- `table_fx.dart:40` `_dealGap = 40ms` with ~300 ms flights ⇒ effective concurrency is already only ~8 simultaneous deal flights (the `_maxConcurrent = 40` cap at `flight_layer.dart:59` rarely binds during a deal — it protects pathological cases). The burst pain is #3 (24 rebuilds) + #5 (24 cold paints), not raw flight count.
- Still cheap wins on web: `kIsWeb ? 60-70ms : 40ms` gap, shorten deal flights to ~240 ms, and skip the `FeltSweep` or keep it (already a solid fill on web, `felt_sweep.dart:75` — fine). Impact: low-medium. Effort: trivial.

**7. Skip IdleLift (and optionally hover-lift) on web performance mode**
- Even after fix 1, ~10 breathing cards recomposite the scene every frame indefinitely. `enabled: !kIsWeb && state.isMyTurn && …` at `table_screen.dart:1149`. PulseGlow already has a cheap web branch; keep it after fix 1. Impact: medium on weak GPUs. Effort: trivial.

**8. FlightLayer: per-frame Stack relayout**
- `flight_layer.dart:219-224` + `:299`: each flight rebuilds a `Positioned` per frame → Stack re-layout with N children per frame. Fine at ≤10; at 24+ it's measurable. With the image cache (#5), all `_CardFlightFx` could collapse into **one CustomPainter** drawing `ui.Image`s (zero layout, zero per-flight widgets). Impact: medium at high concurrency. Effort: medium-high. The opacity quantization (`:295`) and per-card `RepaintBoundary` (`:108`) are already good.

**9. Dimmed/assigned-card `Opacity` → saveLayer**
- `card_face.dart:148` (`Opacity(0.45)` per dimmed card — during beat mode that's most of the hand) and `table_screen.dart:1003` (`Opacity(0.85)`). Each is a saveLayer per repaint. After #2 the repaint frequency drops so this is minor; if desired, dim by blending the ink/background colors in the painter instead. Impact: low. Effort: low.

**10. Misc per-frame allocations (nothing severe found)**
- `ConfettiPainter` is well-behaved (shared fade map, one Paint). `_SweepPainter` caches shader+paint. `_chains()` (`table_screen.dart:265`) reallocates lists per rebuild — falls out of #3. `_ShohaFx`/`_TrumpFx` allocate a few Offsets/Matrix4 per frame — negligible. TurnCountdown allocates a couple of `withValues` colors per 250 ms tick — negligible.

## Recommended bundles

**Web performance mode (cheap, high impact):** #1 + #2 + the `setState` conditional from #3 + #7 + #6 (gap 60-70 ms). ~1-2 hours of work, removes essentially all steady-state 60fps repainting of card faces/tiles and confines the timer/chip animations. Expect the biggest visible jump in Chrome even in debug.

**Mobile-safe subset (keeps all animation richness):** #1 + #2 + full #3 (select() split) + #4. No visual change on any platform; #5 optional insurance for low-end Android first-deal jank.

## Fair performance test

```powershell
# 1. Profile mode in Chrome (JIT-free dart2js, DevTools works):
flutter run -d chrome --profile

# 2. True release, served statically (what users get):
flutter build web --release
cd build\web
python -m http.server 8080     # then open http://localhost:8080

# 3. Worth one experiment — skwasm renderer (multithreaded raster):
flutter build web --wasm --release

# 4. Mobile ground truth (Chrome tells you little about phones):
flutter run --profile -d <android-device-id>
```

What to look at:
- **Flutter DevTools → Performance**: frame bar chart; per-frame *Build / Layout / Paint* (UI) vs *Raster* split. Target ≤ 8 ms UI + ≤ 8 ms raster for 60fps. Use "Frame Analysis" on red frames; enable "Track widget builds" to confirm the whole-table-rebuild finding (#3) — you should see `_TableScreenState.build` on every server event, and after the fix only sub-sections.
- **Chrome DevTools → Performance tab**: record a deal; look for long tasks and clumped GPU work at deal start (shader-compile stalls appear as first-occurrence long raster frames — they disappear on the second deal; don't mistake them for steady-state jank).
- The Flutter performance overlay (`showPerformanceOverlay`) is **not supported on web**; on the Android profile run it is, and the raster (top) bar is the one that predicts phone lag.
- Cheap in-app metric that works everywhere: `SchedulerBinding.instance.addTimingsCallback` logging `FrameTiming.totalSpan` p95 during a deal — compare debug vs profile to see the 5-10× directly.

Key files: `app/lib/features/game/anim/motion_widgets.dart`, `app/lib/features/game/table_screen.dart`, `app/lib/shared/cards/card_face.dart`, `app/lib/features/game/anim/flight_layer.dart`, `app/lib/features/game/anim/table_fx.dart`, `app/lib/core/game/game_controller.dart`.