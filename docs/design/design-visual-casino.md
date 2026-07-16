I have everything I need — all UI files read, fonts verified for Cyrillic coverage with concrete downloadable TTF URLs. Here is the spec.

# CASINO ELEGANCE — Design & Animation Spec (Goat / Козёл)

Grounded in the current code at `C:/Users/altai/Documents/Projects/Goat/app/`. This is a re-skin + refinement: no information-architecture changes, no new routes, no changes to game logic or the anim/ event contract.

---

## 1. Design Tokens

Create `app/lib/shared/theme/tokens.dart` — one `abstract final class Tokens` of `static const`s (zero runtime cost, tree-shakes cleanly).

### 1.1 Color palette

**Felt greens** (table surface — darker and warmer than the current flat `#1B3022`):

| Token | Hex | Use |
|---|---|---|
| `felt900` | `#0A1B10` | Vignette edge, barrier backgrounds |
| `felt800` | `#0F2718` | Scaffold background base |
| `felt700` | `#153522` | Felt mid tone (current `#1B3022` replacement) |
| `felt600` | `#1C452D` | Radial light-pool center on table |
| `felt500` | `#255A3B` | Felt highlight, card-back base accent |
| `feltLine` | `#2F7D4E` | Lattice lines, subtle strokes on felt (exists today) |

**Gold / brass ramp** (anchored on the classic metallic `#D4AF37` already used for шоха):

| Token | Hex | Use |
|---|---|---|
| `gold100` | `#F7E7B4` | Metal highlight, shimmer particles, pressed overlay |
| `gold200` | `#EFD68C` | Gradient top of "gold-filled" buttons |
| `gold300` | `#E6C36A` | Turn glow, active borders, icons |
| `gold400` | `#D4AF37` | PRIMARY. Buttons, frames, trump border |
| `gold500` | `#B8912E` | Gradient bottom of buttons, brass chip body |
| `gold600` | `#8C6D1F` | Metal shadow line, hairline borders on dark |
| `goldGlow` | `#FFD54F` | Emissive glow only (шоха burst — keep as-is) |

**Ivory (cards)**:

| Token | Hex | Use |
|---|---|---|
| `ivory` | `#FAF3E3` | Card face top |
| `ivoryWarm` | `#F1E7CC` | Card face gradient bottom |
| `ivoryEdge` | `#E3D5AF` | Card inner hairline |

**Suit inks, tuned for ivory-on-dark** (current `#C62828` is too neon on ivory; current `#1E1E1E` is cold):

| Token | Hex | Use |
|---|---|---|
| `suitRed` | `#AE3B32` | ♥ ♦ on ivory (deep carmine) |
| `suitBlack` | `#26221A` | ♠ ♣ on ivory (warm ink) |
| `suitRedOnDark` | `#E57368` | ♥ ♦ glyphs on felt/plaques (replaces `#EF5350` in top bar) |
| `suitLightOnDark` | `#F2EEE3` | ♠ ♣ glyphs on felt/plaques |

**Surfaces & text** (raised panels are *not* felt — slightly desaturated so gold reads against them):

| Token | Hex | Use |
|---|---|---|
| `surface` | `#14231B` | Tiles, panels, sheets |
| `surfaceHigh` | `#1C2F24` | Hovered/active tiles, overlay scorecard |
| `textPrimary` | `#F2EEE3` | Warm white |
| `textSecondary` | `#C9C2AD` | Replaces `Colors.white70` |
| `textFaint` | `#8D8A7A` | Hints, captions (replaces white54/white38) |

**Semantic**:

| Token | Hex | Use |
|---|---|---|
| `success` | `#7BC488` | ready/connected (replaces `#66BB6A`) |
| `danger` | `#E25B4E` | urgent timer, penalties (replaces `#EF5350`) |
| `dangerDeep` | `#9C2B22` | error snackbars, ×3 multiplier (replaces `#B71C1C`/`#C62828`) |

### 1.2 Elevation / shadow style

Warm-black soft shadows; gold never used as a drop shadow, only as a *glow* (BoxShadow with spread, alpha ≤ 0.45).

- `shadowCard`: `BoxShadow(color: Color(0x59000000), blurRadius: 4, offset: Offset(0, 2))` (cards at rest)
- `shadowRaised`: `BoxShadow(color: Color(0x73000000), blurRadius: 14, offset: Offset(0, 5))` (overlays, selected cards)
- `glowGold(v)`: `BoxShadow(color: gold300 α 0.18+0.30v, blur 8+8v, spread 0.5+2v)` — exactly the existing `PulseGlow` formula, recolored.

### 1.3 Radii & spacing

- Radii: `r4` chips/badges · `r10` buttons/inputs · `r14` tiles/panels (matches existing 14) · `r20` overlay cards/sheets · card corner stays `height * 0.09`.
- Spacing scale: `4, 8, 12, 16, 20, 24, 32` (the codebase already uses these values; formalize as `Tokens.s1..s7`).

### 1.4 Typography

**Display serif: Playfair Display** — verified Cyrillic subset on Google Fonts (`subsets: ["cyrillic","latin",...]`, v40). **UI sans: Inter** — verified Cyrillic + cyrillic-ext (v20). Both OFL-licensed, bundle-able.

Download these exact combined **latin+cyrillic static TTFs** (verified live via google-webfonts-helper, `storeID: cyrillic_latin`) into `app/assets/fonts/` and rename:

```
PlayfairDisplay-Bold.ttf (700):
https://fonts.gstatic.com/s/playfairdisplay/v40/nuFvD-vYSZviVYUb_rj3ij__anPXJzDwcbmjWBN2PKeiunDTbtY.ttf
PlayfairDisplay-ExtraBold.ttf (800):
https://fonts.gstatic.com/s/playfairdisplay/v40/nuFvD-vYSZviVYUb_rj3ij__anPXJzDwcbmjWBN2PKfFunDTbtY.ttf
Inter-Regular.ttf (400):
https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfAZthjQ.ttf
Inter-Medium.ttf (500):
https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuI6fAZthjQ.ttf
Inter-SemiBold.ttf (600):
https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYAZthjQ.ttf
Inter-Bold.ttf (700):
https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYAZthjQ.ttf
```

(Alternative if gstatic URLs rot: variable TTFs from the google/fonts repo — `https://github.com/google/fonts/raw/main/ofl/playfairdisplay/PlayfairDisplay[wght].ttf` and `.../ofl/inter/Inter[opsz,wght].ttf` — but then weights must be selected with `FontVariation('wght', …)`; static files are simpler and preferred.)

**pubspec.yaml** additions:

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: PlayfairDisplay
      fonts:
        - asset: assets/fonts/PlayfairDisplay-Bold.ttf
          weight: 700
        - asset: assets/fonts/PlayfairDisplay-ExtraBold.ttf
          weight: 800
    - family: Inter
      fonts:
        - asset: assets/fonts/Inter-Regular.ttf
          weight: 400
        - asset: assets/fonts/Inter-Medium.ttf
          weight: 500
        - asset: assets/fonts/Inter-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Inter-Bold.ttf
          weight: 700
```

**Type scale** (set `fontFamily: 'Inter'` app-wide; Playfair applied per-slot):

| Slot | Font | Size/weight | Where |
|---|---|---|---|
| `displaySerif` | Playfair 800 | 40, ls 0.5 | «Козёл» on login |
| `headlineSerif` | Playfair 700 | 26 | Game-over headline, «Итоги раздачи» |
| `titleSerif` | Playfair 700 | 20 | AppBar titles («Столы», «Достижения», «Ждём игроков») |
| `titleMedium` | Inter 600 | 16 | Tile titles, buttons keep M3 labelLarge |
| `body` | Inter 400 | 14 | default |
| `label` | Inter 500 | 12 | seat names, chips |
| `caption` | Inter 400 | 11, `textFaint` | hints («Карты уйдут втёмную») |
| `numeric` | Inter 600 + `FontFeature.tabularFigures()` | — | all scores/counters (CountUpText must not jitter) |

---

## 2. Per-Screen Redesign

### 2.0 Theme + shared scaffolding (main.dart + new shared files)

**`app/lib/shared/theme/app_theme.dart`** (new) — export `buildCasinoTheme()`; in `main.dart` replace the `ColorScheme.fromSeed` block:

```dart
ColorScheme.dark(
  primary: Tokens.gold400, onPrimary: Color(0xFF221B07),
  secondary: Tokens.feltLine, onSecondary: Tokens.textPrimary,
  surface: Tokens.surface, onSurface: Tokens.textPrimary,
  surfaceContainerHighest: Tokens.surfaceHigh,
  error: Tokens.dangerDeep, onError: Tokens.textPrimary,
  outline: Tokens.gold600, outlineVariant: Color(0x338C6D1F),
)
```

plus component themes:
- `scaffoldBackgroundColor: Tokens.felt800`
- `filledButtonTheme`: min height 48, radius `r10`, `textStyle` Inter 600 15, `backgroundColor` gold400 (disabled: `gold600 α0.35`), `foregroundColor` `#221B07`, `overlayColor` gold100 α0.14. Gold *gradient* fill comes from the `GoldButton` wrapper (§4.6) — the theme alone already reads "gold-filled".
- `outlinedButtonTheme`: side `BorderSide(gold400 α0.65, 1)`, foreground gold200.
- `segmentedButtonTheme`: selected = gold400 bg / dark text; unselected = transparent, gold600 α0.4 border.
- `appBarTheme`: transparent bg, `titleTextStyle` = `titleSerif` in gold200, centerTitle true.
- `cardTheme`: color `surface`, radius `r14`, elevation 0, `shape` with `BorderSide(gold600 α0.28, 0.8)`.
- `inputDecorationTheme`: filled `felt900 α0.5`, radius `r10`, enabled border `gold600 α0.35`, focused border `gold300` width 1.6, label style `textSecondary`.
- `snackBarTheme`: bg `surfaceHigh`, gold hairline shape (errors keep explicit `dangerDeep` — update the three hardcoded `#B71C1C` call sites).
- `progressIndicatorTheme`: color gold300.

**`app/lib/shared/felt/felt_background.dart`** (new) — the cheap vignette painter used by login, lobby, and table:

```dart
class FeltPainter extends CustomPainter {
  const FeltPainter({this.lightCenter = const Alignment(0, -0.15)});
  // paint():
  // 1. fill felt800
  // 2. radial gradient: felt600 -> felt700 -> felt800, center=lightCenter,
  //    radius = size.longestSide * 0.75 (the "table lamp" pool)
  // 3. vignette: radial gradient transparent -> felt900 α0.85 from r=0.55 to edge
  @override bool shouldRepaint(FeltPainter old) => old.lightCenter != lightCenter;
}
```

Wrap in `class FeltBackground extends StatelessWidget` = `RepaintBoundary(child: CustomPaint(painter: ..., child: child))`. Two full-screen gradients painted once — cheap; the RepaintBoundary caches it as a layer so table animations never re-rasterize it.

**`app/lib/shared/widgets/brass_chip.dart`** (new) — small stadium chip: `felt900 α0.55` fill, 0.8px `gold600 α0.6` border, optional leading icon in gold300, content in `numeric` style. Used for scores, «В колоде», won-pile, `×N` multiplier (×3+ variant switches border/text to `danger`).

**Route transitions** in `main.dart` — see §4.1.

### 2.1 Login (`features/auth/login_screen.dart`)

Structure unchanged (Scaffold → SafeArea → Center → scroll → column). Re-skin:

1. Wrap body in `FeltBackground(lightCenter: Alignment(0, -0.3))`.
2. Replace the 96px 🐐 emoji with a **gold monogram card**: a 120×172 rounded-rect (`r14`) "playing card" — ivory gradient fill, **double gold border** (outer 2px gold400 inset 3, inner 1px gold600 inset 8 — same recipe as trump cards, §3.4), Playfair 800 «К» at 64px in gold500 centered, and small painted ♠♣♦♥ (suit paths from §3.3, 10px, suitBlack/suitRed) in the four inner corners. Implement as `_MonogramCard` widget with one `CustomPainter`; add `StompIn`-style entrance (reuse existing widget from `anim/motion_widgets.dart`, gentler: scale 1.15→1). Keep 🐐 as a 20px accent in the subtitle row if desired.
3. «Козёл» → `displaySerif` in gold200 with `letterSpacing: 1`; subtitle «Карточная игра онлайн» in `textSecondary` with hairline gold rules either side (Row: Expanded(Divider gold600 α0.4) — text — Expanded(Divider)).
4. TextField: inherits new `inputDecorationTheme`; prefix icon gold300.
5. «Играть» button: `GoldButton` wrapper (§4.6) around the existing `FilledButton`; spinner color `#221B07`.

### 2.2 Lobby (`features/lobby/lobby_screen.dart`)

1. `Scaffold(backgroundColor: transparent)` inside `FeltBackground`; AppBar transparent (theme), title «Столы» in Playfair, actions icons gold300.
2. `_roomTile`: keep `Card + ListTile` skeleton; theme gives surface + gold hairline. Changes:
   - `leading`: replace `CircleAvatar(🐐)` with a **brass chip stack** — 36px `CustomPaint` circle: gold500→gold600 radial ring, felt700 inner disc, `${clients}/${playerCount}` in `numeric` 11 gold100; started rooms show a small ♠ instead. Const painter, `shouldRepaint => false`.
   - `title`: Inter 600 15 `textPrimary`.
   - `subtitle`: `textSecondary` 12; append a tiny gold dot separator `·` styling as-is.
   - `trailing`: keep `FilledButton.tonal` for «Сесть» but style tonal = gold400 α0.16 bg, gold200 text; disabled states («Играют»/«Мест нет») get `textFaint`.
3. FABs: «Быстрая игра» = gold-filled (`backgroundColor: gold400`, dark fg); «Создать стол» = `FloatingActionButton.extended` with `surfaceHigh` bg, gold hairline border, gold200 fg.
4. Create-table sheet: theme covers inputs/segments; sheet gets `showModalBottomSheet(backgroundColor: Tokens.surface, shape: r20 top)` and a Playfair «Новый стол».
5. List stagger-in: §4.2.

### 2.3 Game table (`features/game/table_screen.dart`)

**Backdrop.** Insert `const Positioned.fill(child: FeltBackground(lightCenter: Alignment(0, -0.1)))` as the *first* child of the root Stack (before `SafeArea`). Delete nothing else; `Scaffold` bg becomes transparent. Also replace `_connectingOverlay`/`_lobbyOverlay` flat `Color(0xFF1B3022)` containers with `FeltBackground`.

**Top bar → brass rail** (`_topBar`):
- Title: «Раздача N» in Playfair 700 17, gold200.
- **Trump plaque**: wrap the existing stock/trump cluster (keep `key: _anchors.stock` on the same Row so flight anchors don't move) in a plaque container: `felt900 α0.5` fill, `r10`, double hairline (outer 1px gold400 α0.7, inner via `Container` padding 2 + inner border gold600 α0.4). Contents: mini trump `CardFace(height: 36, trumpStyle: true)` (§3.4), suit glyph via `SuitIcon` painter (§3.3) in `suitRedOnDark`/`suitLightOnDark`, and «В колоде: N» as a `BrassChip`.
- Multiplier badge: `BrassChip` variant (gold for ×2, danger for ×3+), keep the `PunchIn` re-key.

**Opponent tiles** (`_opponentTile`): keep layout; `Colors.black26` → `Tokens.surface α0.8`; turn border `Colors.amber` → `gold300`; `PulseGlow(color: Tokens.gold300)`; avatar `CircleAvatar` gets a 1.5px gold ring when `isTurn` (wrap in Container with shape border); «Очки: N» becomes a mini `BrassChip` with `CountUpText` (§4.7); connected dot → `success`; count badge in `_miniHandFan` `Colors.amber` → gold400 with dark text; `_wonChip` gets gold600 hairline.

**Center area**: felt light pool already comes from `FeltPainter` (its `lightCenter` sits behind the trick zone). «Ходит …» placeholder text → `textFaint`, italic Inter. Beat-target glow `Colors.amber α0.55` → `gold300 α0.55`.

**Timer strip** (`TurnCountdown`): progress color amber → gold300 (urgent → `danger`); label/seconds `textSecondary`; increase bar radius to 3 (already) and add a faint gold600 α0.25 1px top border on the strip for a "rail" line.

**My area & hand**: «Вы» / «Очки» → tokens; the won-pile `ActionChip` → styled with gold hairline (keep `key: _anchors.wonChip`). Hand cards unchanged structurally — new `CardFace` visuals (§3) and `HoverLift` (§4.5) do the work. Selection border in CardFace: `Colors.amber` → gold300.

**Action bar**: primary actions («Ходить», «Побить», «Скинуть», «Закрыть круг») wrapped in `GoldButton`; «Авто» stays outlined (gold hairline via theme); hint texts → `caption` token style. SegmentedButton Побить/Скинуть picks up gold theme.

**Reaction bar**: unchanged; `InkWell` overlay picks up gold ripple from theme.

**Deal-results overlay → elegant scorecard** (`_dealOverlay`): keep Card + timings/CountUps exactly; re-skin:
- Card: `surfaceHigh`, `r20`, double gold frame via `GoldFramePainter` (§2.5) or simple `foregroundDecoration` double border.
- «Итоги раздачи» in `headlineSerif` gold200, under it a **serif rule**: 1px gold600 divider with a centered 6px painted ♦ (reuse diamond path) — a small `CustomPaint(size: Size(160, 8))`.
- Rows: names Inter 600; all numbers in `numeric` (tabular) so CountUpText doesn't jiggle; penalty colors → `danger`/`success`.
- «Нажмите, чтобы закрыть» → `caption`.

**Game-over overlay** (`_gameOverOverlay`): keep confetti/StompIn/Shake choreography; changes:
- Barrier `Colors.black α0.88` → `felt900 α0.92`.
- Wrap the central column in a **gold-framed panel**: `surface α0.85`, `r20`, `GoldFramePainter` (outer 1.5px gold400, inner 1px gold600 inset 6, tiny quarter-arc corner flourishes — one static painter, `shouldRepaint => false`).
- Headline («… — козёл!») → `headlineSerif`, gold200 (goat names), keep 🐐 StompIn.
- Final score rows: numbers `numeric`; my row highlighted with gold100 α0.06 fill.
- Confetti retint: §4.8.
- «Реванш» → GoldButton; «Выйти» outlined.

**Achievement banner** (`_achievementBanner`): keep slide logic; gradient `FFD54F→FFB300` → `gold200→gold500`, add 1px gold600 border, title stays dark Inter 700.

### 2.4 Achievements (`features/achievements/achievements_screen.dart`) — trophy wall

1. `FeltBackground` behind the list; AppBar transparent, Playfair title.
2. `_statsHeader` → **brass plaque**: `surfaceHigh` fill, double gold hairline, values in `numeric` 20 gold100, labels `textFaint`; keep emoji.
3. `_AchievementTile`:
   - Unlocked: `surfaceHigh` fill, 1.5px gold400 border, and a soft gold radial behind the emoji — reuse `RadialGlowPainter(color: gold300, opacity: 0.22)` from `flight_layer.dart` (export it or move to shared) sized 56×56 behind the emoji; title in gold200 Inter 700.
   - Locked: unchanged structure; colors → `textFaint`, border `gold600 α0.2`.
   - Entrance: grid tiles get `SlideFadeIn(delay: 30ms * index)` (reuse existing widget) on first build.

### 2.5 Shared framing painter

`app/lib/shared/widgets/gold_frame.dart` (new): `GoldFramePainter{strokeOuter=1.5 gold400, strokeInner=1 gold600 α0.7, insetInner=6, radius}` drawing two RRects + optional 10px corner arcs; `shouldRepaint => false`. Used by: game-over panel, deal scorecard, login monogram (its own painter may inline it).

---

## 3. Card Design Upgrade (`shared/cards/card_face.dart`)

Keep the public API (`CardFace(card, height, selected, dimmed, onTap)`, `CardBack`, `FaceDownCard`, `cardAspect`) — all call sites in table_screen/table_fx/flight_layer continue to compile. Internally, replace the emoji-text face with **one `CustomPaint` per card face** (`_CardFacePainter`), keeping the outer `AnimatedContainer` for selection lift/border/shadow.

### 3.1 Face background

In the painter: `Rect → RRect(radius = h*0.09)`:
1. Fill with vertical `LinearGradient(ivory → ivoryWarm)` (create shader per paint — painter paints once per card thanks to `shouldRepaint` on identical params + existing RepaintBoundaries in flights).
2. Inner hairline: stroke `ivoryEdge` width `max(0.7, h*0.01)` at inset 1.5.
3. Outer border stays on the widget's `BoxDecoration` (selection = gold300 2.5px, shoha = gold400 2px, default = `suitBlack α0.2` 0.8px) — unchanged behavior.

### 3.2 Serif indices

Corner indices painted with `TextPainter`, `TextStyle(fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w700, fontSize: h*0.18, color: suitInk, height: 1.0)`, rank above a **painted** suit glyph (h*0.13) — mirrored bottom-right via `canvas.save(); translate(w,h); rotate(pi)`. Playfair's «10», J/Q/K/A and lining numerals give the classic look. Note: TextPainter layout happens in `paint()`; acceptable because each face paints once and is layer-cached — but add a static `Map<(int rank, int colorValue, int sizeBucket), TextPainter>` LRU (≤ 72 entries) since flights re-instantiate faces frequently.

### 3.3 Suit glyphs as Paths (crisp, no emoji font)

New file `app/lib/shared/cards/suit_paths.dart`: four functions returning `Path` in a **100×100 unit box**; callers `canvas.scale(size/100)` then `drawPath(path, fill)`. Also export a tiny `SuitIcon` `CustomPaint` widget (used by trump plaque, monogram, scorecard divider). Recipes:

```dart
Path heartPath() => Path()
  ..moveTo(50, 30)
  ..cubicTo(50, 19, 41, 11, 30, 11)
  ..cubicTo(15, 11, 7, 23, 7, 34)
  ..cubicTo(7, 52, 24, 65, 50, 90)
  ..cubicTo(76, 65, 93, 52, 93, 34)
  ..cubicTo(93, 23, 85, 11, 70, 11)
  ..cubicTo(59, 11, 50, 19, 50, 30)
  ..close();

Path diamondPath() => Path()               // gently cushioned diamond
  ..moveTo(50, 5)
  ..quadraticBezierTo(62, 32, 89, 50)
  ..quadraticBezierTo(62, 68, 50, 95)
  ..quadraticBezierTo(38, 68, 11, 50)
  ..quadraticBezierTo(38, 32, 50, 5)
  ..close();

Path spadePath() {                          // inverted heart + flared stem
  final p = Path()
    ..moveTo(50, 6)
    ..cubicTo(38, 24, 10, 38, 10, 56)
    ..cubicTo(10, 68, 19, 76, 29, 76)
    ..cubicTo(37, 76, 44, 72, 47, 65)      // left lobe into notch
    ..cubicTo(46, 74, 43, 84, 36, 92)      // stem left flare
    ..lineTo(64, 92)
    ..cubicTo(57, 84, 54, 74, 53, 65)      // stem right flare
    ..cubicTo(56, 72, 63, 76, 71, 76)
    ..cubicTo(81, 76, 90, 68, 90, 56)
    ..cubicTo(90, 38, 62, 24, 50, 6)
    ..close();
  return p;
}

Path clubPath() {                           // three discs + spade stem
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(50, 27), radius: 19))
    ..addOval(Rect.fromCircle(center: const Offset(29, 56), radius: 19))
    ..addOval(Rect.fromCircle(center: const Offset(71, 56), radius: 19))
    ..moveTo(47, 62)
    ..cubicTo(46, 74, 43, 84, 36, 92)
    ..lineTo(64, 92)
    ..cubicTo(57, 84, 54, 74, 53, 62)
    ..close();
  return p;
}
```

Cache the four paths as `static final` (they're stateless). Center pip: one large glyph at `h*0.42` (same as today's 0.40 emoji). Fill with `suitRed`/`suitBlack`; add depth with a second draw offset (0, 1.2) in `α0.15` black *under* the fill for red suits only (subtle letterpress).

### 3.4 Trump display option — double gold border

Add `final bool trumpStyle;` (default false) to `CardFace`. When true, the painter draws inside the face: outer 1.6px gold400 stroke RRect at inset 2, inner 0.8px gold600 stroke at inset 5 (both scale with h). Used by the top-bar trump plaque mini card and by `_TrumpFx` in `flight_layer.dart` (pass `trumpStyle: true` to the face it builds after the flip).

### 3.5 Upgraded card back — deep green + gold lattice & rosette

Rewrite `_LatticePainter`:
1. Base: vertical gradient `felt500 → felt800`.
2. Lattice: existing diagonal cross-hatch loop, recolored `gold600 α0.32`, stroke `max(0.6, h*0.012)`; keep step `w/4`.
3. **Rosette**: centered circle `r = w*0.30`: gold400 α0.5 ring (1.2px), inside it 8 petals — `for (i in 0..7) canvas.rotate(pi/4)` drawing one petal `Path` (two mirrored quadratics from center to `(0, -r*0.85)`), stroked gold300 α0.45; tiny filled gold400 circle (r*0.12) at center.
4. Frame: replace `Colors.white24` inner RRect with double hairline: gold400 α0.6 at inset 2.5 + gold600 α0.4 at inset 5.
Painter stays `const`, `shouldRepaint => false` — static as today. `FaceDownCard` unchanged.

### 3.6 Shoha ribbon

Keep the golden ribbon overlay but: gradient `gold200 → gold500` (LinearGradient on the Container decoration), text `suitBlack`, and add notched chevron ends — two small `ClipPath` triangles or simply extend the ribbon full-bleed as today (acceptable v1); label stays «ШОХА» Inter 800 with `letterSpacing: 1`.

---

## 4. Animation Upgrades (on top of existing anim/ system)

All new effects follow the established discipline: one controller or `TweenAnimationBuilder` per effect, `RepaintBoundary` + `IgnorePointer` around per-frame painters, precomputed particles, cached shaders (pattern from `RadialGlowPainter._shaderCache`), no per-frame allocation in `paint()`.

1. **`FadeThroughPage` — screen transitions** (hook: `main.dart` router). Replace each `GoRoute.builder` with `pageBuilder` returning `CustomTransitionPage` (helper `buildFadeThrough(state, child)`): outgoing fades to 0 over first 35%, incoming fades in + scales 0.98→1.0 with `Curves.easeOutCubic`, 280ms, felt800 barrier — the M3 fade-through pattern without adding the `animations` package.

2. **`LobbyStaggerIn` — list entrance** (hook: `lobby_screen.dart _roomTile`). Wrap each tile in existing `SlideFadeIn(delay: 40ms * index, offset: 18)`. Guard: only animate when the tile's roomId wasn't in the previous `_rooms` snapshot (keep a `Set<String> _seenRooms`) so the 5s silent refresh never replays. Also applies to achievements grid (§2.4).

3. **`FeltSweep` — light sweep on deal start** (hooks: `TableFx._dispatch case 'dealStarted'` → new callback `onDealStarted`, wired in `table_screen.initState` next to `onTrickTaken`). New one-shot widget in `anim/felt_sweep.dart`: re-keyed into the table Stack (directly above `FeltBackground`, below SafeArea) as `FeltSweep(key: ValueKey(_sweepGen))`. Implementation: single 700ms controller; `CustomPainter` draws one rotated (−18°) linear-gradient band (`transparent → gold100 α0.10 → transparent`, width 0.35·w) translated from x=−0.5·w to 1.5·w with `easeInOut`; shader created once in the painter constructor per run; `RepaintBoundary` + `IgnorePointer`; removes itself on complete (same pattern as `ConfettiBurst._done`).

4. **`GoldShimmer` — trump-reveal particle shimmer** (hook: `FlightLayerState.playTrumpReveal` pushes a second `_Fx`). Extend `confetti.dart`: add to `ConfettiPainter` optional fields `origin` (Offset?, fraction coords) and `radial` (bool) — when radial, particle position = `origin + direction(p.phase) * p.speed * easeOut(t) * size.shortestSide * 0.35`, falling slightly with `t²` gravity; add `static const goldPalette = [gold100, gold200, gold400, goldGlow, ivory]` and `ConfettiParticle.generate(count, rng, palette: …)`. New `_ShimmerFx` in `flight_layer.dart` (1100ms, ~36 particles, origin = reveal center) started at `t≈0.30` of the trump flip via `_after(const Duration(milliseconds: 450), …)`. Particles precomputed; zero per-frame allocs (reuse the faded-palette map trick).

5. **`HoverLift` — card hover for web/mouse** (hook: inside `card_face.dart`, wrapping the tappable result). Stateful wrapper active only when `onTap != null && (kIsWeb || desktop platform)`: `MouseRegion(onEnter/onExit, cursor: SystemMouseCursors.click)` driving an `AnimatedSlide(offset: hovered ? Offset(0,-0.06) : zero, 120ms)` + slightly deepened shadow (feed `hovered` into the existing `AnimatedContainer` decoration: blur 8, offset (0,4)). No ticker at rest; composes with `IdleLift` (idle breathing pauses visually under the lift — fine).

6. **`GoldButton` — button micro-interactions** (new `shared/widgets/gold_button.dart`; hooks: login «Играть», lobby FAB, action bar primaries, «Реванш»). Wrapper owning no ticker: `Listener(onPointerDown/Up)` → `AnimatedScale(pressed ? 0.965 : 1.0, 90ms, easeOut)` around the child button, plus a `Ink` gradient decoration (`gold200 → gold500`, top-lit) with 1px gold600 bottom border for the metallic read. Theme-level pressed overlay (gold100 α0.14) covers all other buttons for free.

7. **`AnimatedScoreChip` — gold count-up chips** (hooks: `_opponentTile` score, `_myArea` score, deal scorecard already uses CountUpText). `BrassChip.countUp(value)` keeps `_lastValue` in state; on change rebuilds `CountUpText(from: old, value: new, duration: 450ms)` (existing widget) re-keyed by value, plus a one-shot `PunchIn` on the chip and a brief gold border flash (`AnimatedContainer` border gold300→gold600 α0.6 over 400ms). Requires `numeric` tabular figures (§1.4) to avoid width wobble.

8. **Confetti retint** (hook: `ConfettiParticle.palette` via the new `palette:` param at the `ConfettiBurst` call in `_gameOverOverlay`): casino palette `[gold100, gold300, gold400, ivory, suitRedOnDark, feltLine]` — keeps the mechanics, matches the room.

Existing effects to recolor only (no behavior change): `PulseGlow` default `Colors.amber` → gold300; `_ShohaFx._gold` stays `goldGlow`; `_TrumpFx` suit colors → `suitRedOnDark`/`suitLightOnDark`, banner text Playfair 700.

---

## 5. Ordered Implementation Checklist

Each step compiles and ships independently; run `flutter analyze` + a smoke run per step.

1. **Fonts + tokens (foundation)**
   - Download the 6 TTFs (§1.4) → `app/assets/fonts/`; edit `app/pubspec.yaml` (fonts block); `flutter pub get`.
   - New `app/lib/shared/theme/tokens.dart` (all §1 constants + text-style consts).
2. **Theme + transitions — `app/lib/main.dart`**
   - New `app/lib/shared/theme/app_theme.dart` (`buildCasinoTheme()`, §2.0); use in `MaterialApp.router`.
   - Add `buildFadeThrough` helper; convert 4 routes to `pageBuilder` (§4.1).
3. **Felt + shared widgets**
   - New `app/lib/shared/felt/felt_background.dart` (§2.0), `app/lib/shared/widgets/brass_chip.dart`, `app/lib/shared/widgets/gold_button.dart` (§4.6), `app/lib/shared/widgets/gold_frame.dart` (§2.5).
4. **Cards — `app/lib/shared/cards/card_face.dart`**
   - New `app/lib/shared/cards/suit_paths.dart` (§3.3 + `SuitIcon`).
   - Rewrite face as `_CardFacePainter` (§3.1–3.4, `trumpStyle` param), rewrite `_LatticePainter` (§3.5), ribbon polish (§3.6), `HoverLift` (§4.5). Public API unchanged.
5. **Login — `app/lib/features/auth/login_screen.dart`** (§2.1: FeltBackground, `_MonogramCard`, serif title, GoldButton).
6. **Lobby — `app/lib/features/lobby/lobby_screen.dart`** (§2.2: felt, tile re-skin with brass chip leading, FABs, sheet, stagger-in §4.2 with `_seenRooms` guard).
7. **Table re-skin — `app/lib/features/game/table_screen.dart`** (§2.3, largest diff)
   - FeltBackground layer; top bar → trump plaque + brass chips (keep all `_anchors.*` keys on the same widgets); opponent tiles; timer; action bar GoldButtons; deal scorecard; game-over gold frame; achievement banner recolor; replace every hardcoded amber/white70/`#EF5350`/`#C62828`/`#B71C1C`/`#66BB6A` with tokens.
8. **Anim system — `app/lib/features/game/anim/`**
   - `confetti.dart`: `palette:` param, `origin`/`radial` mode (§4.4, §4.8).
   - `flight_layer.dart`: `_ShimmerFx` in `playTrumpReveal`; trump face `trumpStyle: true`; `_TrumpFx` colors/banner font.
   - New `anim/felt_sweep.dart`; `table_fx.dart`: `onDealStarted` callback; `table_screen.dart`: wire `_sweepGen` re-key (§4.3).
   - `motion_widgets.dart`: `PulseGlow` default color → gold300; add score-chip flash if not folded into BrassChip.
9. **Achievements — `app/lib/features/achievements/achievements_screen.dart`** (§2.4: felt, plaque header, trophy tiles with `RadialGlowPainter` — move it to `shared/` or export from flight_layer, tile stagger).
10. **Polish + perf verification**
    - Sweep for leftover raw `Colors.amber`/hex literals (grep `0xFFC62828|0xFFEF5350|Colors.amber|white70`).
    - Verify Cyrillic renders in Playfair on-device (login title, «Итоги раздачи», «Козырь — ♥» banner).
    - Perf pass: DevTools repaint rainbow — felt layer must not repaint during flights/idle-lift; confirm no new tickers at rest (HoverLift/GoldButton tickerless), shimmer/sweep self-remove.

Key file paths: `C:/Users/altai/Documents/Projects/Goat/app/pubspec.yaml`, `app/lib/main.dart`, `app/lib/shared/theme/{tokens,app_theme}.dart` (new), `app/lib/shared/felt/felt_background.dart` (new), `app/lib/shared/widgets/{brass_chip,gold_button,gold_frame}.dart` (new), `app/lib/shared/cards/{card_face.dart,suit_paths.dart}`, `app/lib/features/auth/login_screen.dart`, `app/lib/features/lobby/lobby_screen.dart`, `app/lib/features/game/table_screen.dart`, `app/lib/features/game/anim/{confetti,flight_layer,table_fx,motion_widgets,felt_sweep}.dart`, `app/lib/features/achievements/achievements_screen.dart`.