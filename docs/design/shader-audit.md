All files read; no plan-file needed — this is a read-only audit and the findings below are the deliverable.

## Shader-variant pressure audit — table screen (Chrome/CanvasKit)

Global negatives first: **no** explicit `MaskFilter.blur`, `BackdropFilter`, `ImageFilter`, `saveLayer`, `SweepGradient`, `drawShadow`, dither flags, or non-srcOver blend modes anywhere in `app/lib` (grep-verified). All blur comes *implicitly* from `BoxShadow.blurRadius`, and all saveLayers come *implicitly* from `Opacity`/`FadeTransition`.

### Feature table

| file:line | feature | unique to table? | frame frequency | web risk |
|---|---|---|---|---|
| shared/felt/felt_background.dart:28-31 | `RadialGradient` 3-stop light pool | no (login/lobby render it) | once (RepaintBoundary) | low — proven working |
| shared/felt/felt_background.dart:38-49 | `RadialGradient` alpha vignette | no | once | low — proven |
| shared/widgets/gold_button.dart:69-81 | LinearGradient fill + blur-4 shadow | no (login) | on press only | low — proven |
| shared/cards/card_face.dart:81-87 | `BoxShadow` blur (implicit MaskFilter), **animated** 4↔8 sigma via AnimatedContainer, per card | effectively yes (login has 1 static card; table has 10-25 at once) | every frame during 150 ms select/hover lerps; re-rastered whenever card moves | **high** |
| shared/cards/card_face.dart:136 | `Opacity(0.45)` dimmed card → saveLayer | yes | static per state | medium |
| shared/cards/card_face.dart:219-223 | ivory LinearGradient per face paint | yes in volume | once per card instance | medium at burst |
| shared/cards/card_face.dart:108-110 | shoha banner LinearGradient | yes | rare | low |
| shared/cards/card_face.dart:299-306 | letterpress = second solid fill (no blur) | yes | once per paint | low |
| shared/cards/card_face.dart:182-207 | Playfair rank TextPainters, sizes = 0.18×{36,64,72,84,92,100} × 2 inks | yes | cached (LRU) but all first-painted at deal | medium (glyph atlas) |
| shared/cards/card_face.dart:375-440 | CardBack LinearGradient + lattice strokes | yes | once, static | low |
| features/game/anim/felt_sweep.dart:72-78, 93 | full-screen LinearGradient band drawRect | **yes — deal start** | **every frame × 700 ms** | medium-high |
| features/game/anim/flight_layer.dart:284 | `Opacity(_opacity(t))` around EVERY flight card → saveLayer, 24-36 concurrent at deal | **yes — deal start** | every frame per flight | **high** |
| features/game/anim/flight_layer.dart:288-292 | scale/rotate Matrix4 on flights | yes | every frame | low |
| features/game/anim/flight_layer.dart:378 | shoha full-screen black barrier fade | yes | every frame × 900 ms | low-medium |
| shared/fx/radial_glow.dart:21-23, 33-40 | `RadialGradient` shader (cached per color) + per-frame alpha-modulated paint | yes | every frame while glow active | medium (one new variant: gradient×paint-alpha) |
| features/game/anim/flight_layer.dart:458-460 | **perspective** Matrix4 (`setEntry(3,2)`) + rotateY flip of CardFace/Back | **yes — trump reveal at deal start** | every frame × 1500 ms | medium-high |
| features/game/anim/flight_layer.dart:392, 516 | Opacity on shoha/trump card → saveLayer | yes | every frame | medium |
| features/game/anim/flight_layer.dart:541-568 + confetti.dart:152-165 | shimmer/confetti: solid rotated rects, palette-alpha fade, no saveLayer | yes | every frame while running | low |
| features/game/anim/motion_widgets.dart:79-88 (PulseGlow) | `BoxShadow` with **per-frame changing blur sigma + spread** (8→16, 1.2 s loop) | yes | **every frame, continuous whole game** (someone always has the turn) | **high** |
| features/game/anim/motion_widgets.dart:194-212 (IdleLift) | per-frame translate that re-records the blurred-shadow CardFace picture, per breathing hand card | yes | every frame while my turn | medium |
| features/game/anim/motion_widgets.dart:248-252 (CountUpText) | new text string per frame → shaping + glyph-atlas churn | yes | every frame × duration; 3 per row in deal overlay | medium |
| features/game/anim/motion_widgets.dart:281-288 (SlideFadeIn) | Opacity per frame → saveLayer, staggered ×N rows | yes | every frame × ~320 ms each | medium |
| features/game/anim/motion_widgets.dart:317-320 (PunchIn) | Opacity + scale per frame → saveLayer | yes | every frame × 550 ms per pop | medium |
| shared/widgets/brass_chip.dart:132-148 | border Color.lerp flash (solid) + nested PunchIn/CountUpText | yes | every frame × 400 ms per score change | low-medium |
| features/game/table_screen.dart:454-465 | achievement banner LinearGradient + blur-10 shadow | yes | event-driven | low-medium |
| features/game/table_screen.dart:962-968 | gold glow `BoxShadow` blur-8/spread-1 on targetable trick card | yes | per state change | medium |
| features/game/table_screen.dart:985 | `Opacity(0.85)` assigned card | yes | static | low |
| features/game/table_screen.dart:1538, 1645, 1796 | full-screen translucent overlay fills | yes | static | low |
| features/game/table_screen.dart:1545 | shadowRaised blur-14 on deal-overlay panel | yes | once per show | low-medium |
| features/game/table_screen.dart:1939-1947 | LinearProgressIndicator, 4 rebuilds/s | yes | 250 ms tick | low |
| main.dart:38-42 | route fade-through: **two nested full-screen FadeTransitions + ScaleTransition** wrapping the table's very first frames | timing-unique (all routes have it, but only /table paints 30+ novel pipelines under it) | every frame × 280 ms at entry | medium-high |
| shared/widgets/gold_frame.dart:30-82, 102-122 | stroked RRects/arcs, static | no-ish (overlays only) | once | low |

### Glyph-atlas load (distinct font/size/weight combos live on the table)
Playfair w700 at 17, 18, 20, 26 px + rank glyphs at ~6.5/11.5/13/15/16.5/18 px × 2 ink colors; Inter at 10/11/12/14/15/16 px across w400/w500/w600/w700/w800 (incl. tabular-figures variants used by every CountUpText); emoji at 20/22/24/84 px. ≈ **25-30 distinct combos vs ~6 on login** — and CountUpText re-shapes numerals every frame during count-ups, so much of this atlas fills during the deal-results burst.

### Top 5 most likely shader-compile triggers at the deal-start moment
1. **flight_layer.dart:284 — Opacity-saveLayer around 24-36 staggered deal flights**, each flight a `CardFace`/`CardBack` whose paint includes an animated blurred BoxShadow (card_face.dart:81) and two linear gradients. First deal = first-ever compile of the saveLayer × blur-mask × gradient pipeline combinations, dozens of layers landing within a few frames.
2. **card_face.dart:81-87 — blurred RRect shadows appearing en masse** (10-card hand fan + opponent mini-fans + every flight), each first-time blur sigma/geometry a fresh rasterization; on WebGL the blur pipeline family compiles here.
3. **Trump-reveal composite (flight_layer.dart:411-536)** — a perspective-transform textured draw (l.458-460), the first `RadialGradient`-with-modulated-alpha variant (radial_glow.dart:21-40), a shimmer ConfettiPainter, and a serif banner — three-plus novel fragment-shader variants inside the same ~1.5 s that the flights are flying.
4. **felt_sweep.dart:72-93 — full-viewport gradient band redrawn every frame for 700 ms**, running concurrently with (1)-(3); adds the rotated-clip × linear-gradient variant and keeps the whole screen dirty during peak compile pressure.
5. **motion_widgets.dart:79-88 (PulseGlow) + the count-up/punch-in cluster** (CountUpText l.248, PunchIn l.317, AnimatedScoreChip brass_chip.dart:114-151): a continuously animating blur-sigma shadow starts looping the moment play begins, while count-ups churn the glyph atlas — the sustained load that keeps the compile queue from ever draining. (Compounded at entry by main.dart:38-42's double full-screen fade over the table's first frames.)

### Trivial kIsWeb guards (no visible design loss)
- **card_face.dart:81-87** — on web use a single *constant* BoxShadow (no selected/hover sigma animation), or a solid translucent offset border. One blur variant instead of an animated family. Biggest single win.
- **flight_layer.dart:284, 309-314** — on web skip the `Opacity` wrapper (or apply it only when `_opacity < 1` **and** quantize to 0/1): flights pop in/out 10 px shorter; nobody notices at 320 ms.
- **felt_sweep.dart** — `if (kIsWeb) return const SizedBox.shrink();` in `FeltSweep.build`, or draw a solid `gold100 @ 5%` band without the gradient.
- **motion_widgets.dart:79-88 (PulseGlow)** — on web replace the animated blurred shadow with an animated *border color* (solid stroke pulse). Reads nearly identically at 2 px.
- **flight_layer.dart:458-460** — drop `setEntry(3, 2, 0.0014)` on web; a plain `scaleX` flip (like the discard flip already does) avoids the perspective-sampling variant.
- Lower priority: main.dart:38-42 fade-through → simple `FadeTransition`-free page for `/table` on web; card_face.dart:136 dimming via `ColorFiltered`-free solid tint color instead of Opacity.

Root-cause shape: nothing here is individually exotic — the table white-screens because ~15 first-use pipeline variants (blur shadows, saveLayer combos, radial/linear gradients, perspective transform) all compile in the same 1-2 s deal-start window under a full-screen route fade, on a screen with 10× the paint-feature diversity of login/lobby.