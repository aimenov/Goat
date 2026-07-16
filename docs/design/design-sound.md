# Sound System Spec — Козёл (tactile + light chimes)

All sounds procedurally synthesized. One deviation from the brief, flagged up front: files are written at **22,050 Hz 16-bit mono PCM** (synthesized at 44,100 Hz, then lowpassed + decimated ×2). At 44.1 kHz the inventory below is ~560 KB; at 22.05 kHz it is **~281 KB**, meeting the <300 KB budget. Highest spectral content in any recipe is 8 kHz, safely under the 11.025 kHz Nyquist. If the owner insists on 44.1 kHz, the fallback is IMA-ADPCM or trimming chime tails ~40%.

---

## 1. Sound inventory (14 SFX)

### Tactile set (shaped noise bursts)

| id | file | trigger | dur | character |
|---|---|---|---|---|
| `card_slide` | card_slide.wav | a card flight launches (lead/beat/my-deal) | 140 ms | airy paper swish, brightens toward end |
| `card_snap` | card_snap.wav | a played/beating card lands on the trick | 60 ms | crisp paper snap with tiny low body; beats play it +2 dB via volume param |
| `card_flip` | card_flip.wav | discard flip mid-flight; trump card flip start | 90 ms | double micro-snap: bend then flip-over |
| `deal_riffle` | deal_riffle.wav | dealing/draw batches (replaces individual slides) | 380 ms | 7 accelerating micro-swishes, like thumbing a deck |
| `stack_thud` | stack_thud.wav | trick vacuum lands on winner | 180 ms | soft deep thud + paper slap, satisfying "pile absorbed" |
| `tap_select` | tap_select.wav | hand-card / target-card tap | 35 ms | tiny felt tick, very quiet |
| `button_press` | button_press.wav | game-action buttons (Ходить/Побить/Скинуть/Закрыть круг) | 45 ms | slightly rounder tick than tap, still subtle |

### Chime set (sine/triangle partials, exponential decay — used sparingly)

| id | file | trigger | dur | character |
|---|---|---|---|---|
| `trump_chime` | trump_chime.wav | trump reveal, at the moment the flip completes | 700 ms | two-note E5→B5 glassy bell motif, shimmery detune |
| `my_turn_ding` | my_turn_ding.wav | turn passes to me | 450 ms | single gentle A5 ding, non-alarming |
| `achievement_bell` | achievement_bell.wav | achievement banner slides in | 900 ms | inharmonic golden bell strike with strike-noise transient |
| `win_fanfare` | win_fanfare.wav | gameEnded and I am NOT a goat | 1.5 s | 3 ascending triangle notes C5-E5-G5 + sparkle grains |
| `goat_moan` | goat_moan.wav | gameEnded and I AM a goat | 850 ms | comic descending two-step "wah" bleat, lowpassed sawtooth with vibrato — tasteful, not a fart |
| `shoha_impact` | shoha_impact.wav | shoha slam frame (synced to heavy haptic) | 950 ms | deep pitch-drop boom + delayed golden shimmer tail |
| `reaction_pop` | reaction_pop.wav | reaction bubble appears | 90 ms | bubbly rising pop |

### Rate-limit / cooldown rules (enforced inside SoundService)

- **Per-sfx min interval** (requests inside the window are dropped): slide 80 ms, snap 60 ms, flip 70 ms, tap 50 ms, button 100 ms, pop 300 ms (global, not per-seat), thud 250 ms, my_turn_ding 1500 ms, riffle 900 ms, each remaining chime 1000 ms.
- **Draw coalescing**: `yourDraw`/`cardDrawn` never play slides. They call `sound.drawBatch()`, which plays one `deal_riffle` and opens a 700 ms rolling window; further calls inside the window only extend it. A full 4-player deal (~24 `cardDrawn` + `yourDraw`) produces 2–3 riffles max, matching the visual stagger (40 ms/card). `dealStarted` resets the window.
- **Multi-card plays**: `card_slide`/`card_snap` are scheduled for at most the **first 3 cards** of a lead/beat set; a set larger than 6 cards plays one `deal_riffle` instead.
- **Voice caps** via `AudioPool(maxPlayers)`: slide 3, snap 3, flip 2, tap 2, button 2, pop 2, riffle 1, thud 1. Chimes: 2 shared `AudioPlayer` slots — a new chime steals the oldest slot (so achievement_bell never stacks on itself).
- **Vacuum**: exactly one `stack_thud` per `trickEnded`, scheduled at last-card landing (see §3), never per flight.

---

## 2. Synthesis recipes

Global conventions for `tools/generate_sounds.py` (numpy only):

- `SR = 44100` internal; final write: FFT-lowpass at 9.5 kHz, take every 2nd sample → 22,050 Hz, dither with ±0.5 LSB triangular noise, clip to [-1,1], int16.
- `rng = np.random.default_rng(0xC0A7)` — single generator, functions called in fixed order → deterministic output.
- Primitives:
  - `noise(n)` = `rng.uniform(-1, 1, n)` (white).
  - `bp(x, lo, hi)` = FFT bandpass: unit gain in [lo, hi] Hz, Gaussian skirts with σ = ⅓ octave outside the band (`gain = exp(-0.5*(log2(f/edge)/(1/3))**2)`).
  - `lp(x, fc)` / `hp(x, fc)` = same-style one-sided masks.
  - `expdec(n, tau_ms)` = `exp(-t/tau)`.
  - `adsr(n, a_ms, d_ms, s_level, r_ms)` = linear attack, exponential-ish decay to sustain, linear release filling the remainder.
  - `glide_sine(f_of_t)` = `sin(2π·cumsum(f)/SR)` (phase-integrated, so pitch curves are exact).
- Each sound is peak-normalized to 1.0 then scaled by a baked **mix gain** (given per sound) so relative loudness ships in the files; runtime volume is one global knob.

### Tactile

**card_slide** — 140 ms, mix 0.65
- Layer A: white noise → `bp(1200, 4500)`; envelope: raised-cosine hump peaking at 55 ms (attack 0→peak over 55 ms as `sin²`, decay to 0 at 140 ms).
- Layer B (brightening tail): same noise → `bp(4000, 8000)`, multiplied by `(t/0.14)**2 · expdec(tau=45ms shifted to start at 60 ms)`, gain 0.5 relative to A. Result: swish that opens up as the card accelerates.

**card_snap** — 60 ms, mix 0.85
- Layer A (crack): noise → `bp(2000, 8000)`; env: 1 ms linear attack, `expdec(tau=18ms)`.
- Layer B (body): `glide_sine(const 180 Hz)` · `expdec(tau=25ms)`, gain 0.35.
- Sum, trim at 60 ms with 5 ms fade-out.

**card_flip** — 90 ms, mix 0.7
- Grain 1 at t=0: noise → `bp(1500, 6000)` · `expdec(tau=10ms)`, gain 0.5.
- Grain 2 at t=45 ms: noise → `bp(1500, 6000)` · `expdec(tau=20ms)`, gain 1.0, plus `glide_sine(300 Hz)` · `expdec(tau=15ms)` gain 0.25 under it.

**deal_riffle** — 380 ms, mix 0.6
- 7 grains, each 60 ms: noise → `bp(c/1.8, c·1.8)` where center `c = 3000 · 2**rng.uniform(-0.3, 0.3)` per grain; Hann envelope.
- Onsets: [0, 45, 95, 150, 210, 275, 330] ms + `rng.uniform(-8, 8)` ms jitter each; grain gains alternate 0.7/1.0 with ±10% jitter. Sum, normalize.

**stack_thud** — 180 ms, mix 0.9
- Layer A: `glide_sine(f: 110→70 Hz, exponential glide over first 80 ms, then hold 70)`; env: 2 ms attack, `expdec(tau=60ms)`.
- Layer B: noise → `lp(600)` · `expdec(tau=30ms)`, gain 0.4.
- Layer C (paper slap): noise → `bp(400, 1200)` · `expdec(tau=15ms)`, gain 0.25.

**tap_select** — 35 ms, mix 0.3 (deliberately quiet)
- `glide_sine(1100 Hz)` · `expdec(tau=8ms)` + noise → `bp(3000, 7000)` · `expdec(tau=4ms)` gain 0.3.

**button_press** — 45 ms, mix 0.4
- `sin(2π·700·t) + 0.3·sin(2π·2100·t)` · `expdec(tau=12ms)` + noise → `bp(2000, 5000)` · `expdec(tau=5ms)` gain 0.25.

### Chimes

**trump_chime** — 700 ms, mix 0.55
- Note 1 (E5, 659.25 Hz) at t=0; Note 2 (B5, 987.77 Hz) at t=120 ms, gain 0.9.
- Each note = partials at ratios [1.0, 2.76, 5.40] (bell-like), gains [1.0, 0.35, 0.12], decay taus [280, 140, 80] ms, attack 4 ms.
- Every partial is a **detuned pair**: two sines at f·(1±0.003) mixed equally → slow shimmer beat.

**my_turn_ding** — 450 ms, mix 0.5
- Fundamental: detuned pair 880 Hz ±0.4%, `expdec(tau=180ms)`, attack 5 ms.
- Octave: single sine 1760 Hz, gain 0.3, `expdec(tau=90ms)`. Gentle, no strike noise.

**achievement_bell** — 900 ms, mix 0.6
- Strike partials at f0 = 1046.5 Hz (C6) × ratios [0.56, 0.92, 1.0, 1.19, 1.70, 2.00], gains [0.4, 0.6, 1.0, 0.5, 0.35, 0.25], taus [500, 400, 350, 250, 180, 120] ms, attack 3 ms; ratios ≥1.0 as detuned pairs ±0.2%.
- Strike transient: noise → `bp(3000, 8000)` · `expdec(tau=8ms)`, gain 0.2.

**win_fanfare** — 1.5 s, mix 0.65
- Notes C5 (523.25), E5 (659.25), G5 (783.99) at t = 0 / 220 / 440 ms. Timbre per note: triangle-flavored additive — harmonics [1, 3, 5] at gains [1, 1/9, 1/25]; attack 8 ms; notes 1–2 `expdec(tau=260ms)`, note 3 `expdec(tau=600ms)` with an added G6 (1568 Hz) layer at gain 0.35.
- Sparkle: 8 grains between t = 500–1200 ms (onsets and freqs from rng), each a sine at `rng.uniform(2000, 5000)` Hz · `expdec(tau=60ms)`, gain 0.15. Fade all to 0 by 1.5 s.

**goat_moan** — 850 ms, mix 0.6
- Source: additive quasi-saw — harmonics [1, 2, 3, 4] at gains [1, 0.5, 0.33, 0.25] over a glided fundamental.
- Pitch curve (the comic two-step "wah"): 220→180 Hz exponential over 0–250 ms, hold 180 with wobble to 300 ms, 180→130 Hz exponential over 300–700 ms, hold. Add vibrato: f · (1 + 0.03·sin(2π·5.5·t)).
- Amplitude: attack 60 ms, body with 6 Hz tremolo depth 0.25, linear release over final 200 ms.
- Tone: `lp(2200)` for a muted, tasteful bleat.

**shoha_impact** — 950 ms, mix 1.0 (the loudest asset)
- Layer A (boom): `glide_sine(150→45 Hz exponential over 250 ms, hold 45)` plus 0.25 of its 2nd harmonic; env: 3 ms attack, `expdec(tau=220ms)`.
- Layer B (rumble): noise → `lp(300)` · `expdec(tau=80ms)`, gain 0.5.
- Layer C (gold shimmer tail): partials at 1318.5 Hz (E6) × [1, 1.5, 2, 2.5, 3, 4], gains [0.20, 0.14, 0.11, 0.08, 0.06, 0.05], each a ±0.3% detuned pair; onset delayed 120 ms with 150 ms fade-in; taus 450 down to 250 ms; multiply the whole layer by `(1 + 0.3·sin(2π·7·t))` shimmer.

**reaction_pop** — 90 ms, mix 0.45
- `glide_sine(400→900 Hz linear over 60 ms)` · Hann window over 90 ms (attack 3 ms) + noise → `bp(1000, 3000)` · `expdec(tau=10ms)`, gain 0.2.

Size ledger (22,050 Hz × 2 B/sample + 44 B header): slide 6.2 + snap 2.7 + flip 4.0 + riffle 16.8 + thud 8.0 + tap 1.6 + button 2.0 + chime 30.9 + ding 19.9 + bell 39.7 + fanfare 66.2 + moan 37.5 + shoha 41.9 + pop 4.0 ≈ **281 KB**.

---

## 3. Flutter integration

### Package

`audioplayers: ^6.8.1` (verified current on pub.dev, 2026-07). Rationale: it ships `AudioPool` — N pre-created players bound to one preloaded asset, purpose-built for rapid-fire SFX (our slides/snaps at 60–80 ms intervals); `just_audio` (0.10.6) has no pool primitive and is heavier for fire-and-forget one-shots. Supports Android/iOS/web/desktop, per-play volume, and `AudioContext` config for iOS ambient mixing (don't duck the user's music: `AudioContextIOS(category: ambient)`).

### SoundService — `app/lib/core/services/sound.dart`

```dart
enum Sfx { cardSlide, cardSnap, cardFlip, dealRiffle, stackThud, tapSelect,
           buttonPress, trumpChime, myTurnDing, achievementBell, winFanfare,
           goatMoan, shohaImpact, reactionPop }

class SoundService {
  Future<void> init();                    // load prefs, create pools, preload
  void play(Sfx sfx, {double gain = 1});  // cooldown-checked, fire-and-forget
  void playDelayed(Sfx sfx, Duration d);  // Timer-scheduled, canceled on dispose
  void drawBatch();                       // riffle coalescing window (700 ms)
  double volume; bool muted;              // setters persist to SharedPreferences
  void markUnlocked();                    // web autoplay gate
}
final soundServiceProvider = Provider<SoundService>((ref) => ...); // Riverpod
```

- **Pools** (tactile, `AudioPool.createFromAsset`): slide 3, snap 3, flip 2, tap 2, button 2, pop 2, riffle 1, thud 1.
- **Chimes**: two reusable `AudioPlayer`s with `ReleaseMode.stop`, `setSource` per play; oldest slot stolen on overlap.
- **Preloading**: `init()` awaited fire-and-forget from `main()` (`app/lib/main.dart:10` — before `runApp` kick off, no need to block first frame); pools preload their asset on creation. Total decoded footprint ~ 6.4 s of mono PCM — trivial.
- **Cooldowns**: `Map<Sfx, DateTime> _lastPlayed` checked in `play()` with the table from §1; `drawBatch()` implements the 700 ms window.
- **Persistence**: SharedPreferences keys `sound.volume` (double, default 0.8) and `sound.muted` (bool, default false); applied as `pool.start(volume: gain * volume)`, short-circuit return when muted.
- **Web autoplay**: browsers block audio until a user gesture. Two-layer handling: (1) wrap the router shell in a one-time `Listener(onPointerDown: soundService.markUnlocked)` — first pointer event anywhere resumes/creates the audio context by playing a 1-sample silent buffer from inside the gesture callback; (2) `play()` no-ops (doesn't throw, doesn't queue) until unlocked. Since the very first sounds a user triggers (tap/button) are already inside gesture handlers, unlock is effectively instant.

### Settings entry points

- **Lobby** (`app/lib/features/lobby/lobby_screen.dart` line 235, `AppBar actions:` next to the achievements IconButton): a volume `IconButton` (icon swaps `volume_up`/`volume_off`) — tap toggles mute; long-press/menu opens a small bottom sheet with a volume `Slider`.
- **Table** (`app/lib/features/game/table_screen.dart` line 452 `_topBar`, appended to the trailing widgets around line 530): quick mute-only `IconButton` so a player can silence mid-game without leaving.

### Hook points (line-level anchors)

Pass the service into the choreography once: `_TableScreenState.initState` (`table_screen.dart:85`) → `TableFx(anchors: ..., layerKey: ..., sound: ref.read(soundServiceProvider))`; also hand it to `FlightLayer` (constructor param) for the shoha slam. **Design rule: card sounds live inside the shared choreography helpers, not in `_dispatch`** — the optimistic-play paths (`playMyLead` 116, `playMyBeat` 123, `playMyDiscard` 131) and server events funnel into the same helpers, so the existing suppression map (`table_fx.dart:324–335`) dedups sounds for free.

`app/lib/features/game/anim/table_fx.dart`:

| anchor | sound call |
|---|---|
| `_dispatch` case `dealStarted` (line 55–59, next to `_stagger.reset()`) | `sound.drawBatch()` reset (new window) |
| `_flyMyDraws` (line 140) and `_flyDraw` (line 159) | `sound.drawBatch()` — coalesces to `deal_riffle` (both deal and mid-game replenish draws) |
| `_leadFlights` (line 183, inside the per-card loop, i < 3) | `playDelayed(cardSlide, 70ms·i)`; `playDelayed(cardSnap, 70ms·i + flightDuration)` (duration is the value passed at line 193) |
| `_beatFlights` non-shoha branch (line 218) | same pattern, snap at `gain: 1.25` (slam) with delays from lines 225–226 |
| `_beatFlights` shoha branch (line 215–216) | nothing here — see flight_layer below |
| `_discardFlights` (line 238, loop, i < 2) | `playDelayed(cardFlip, 60ms·i + 125ms)` (flip completes at raw 0.38 of ~330 ms, `flight_layer.dart:256–257`) |
| `_flyVacuum` (line 257) | one `playDelayed(stackThud, 330ms + 40ms·(n-1))` — last vacuum card's landing; pairs with the badge pop at 520 ms (`table_screen.dart:112`) |
| `_dispatch` case `trumpRevealed` (line 68–72) | `play(cardFlip)` now + `playDelayed(trumpChime, 510ms)` — the 3D flip in `_TrumpFx` completes at t=0.34 of 1500 ms (`flight_layer.dart:411`) |
| `_dispatch` case `gameEnded` (line 107–108, beside `HapticFeedback.heavyImpact`) | `asIntList(e.data['goats']).contains(s.mySeat) ? play(goatMoan) : play(winFanfare)` |

`app/lib/features/game/anim/flight_layer.dart`:

| anchor | sound call |
|---|---|
| `playShoha` controller listener, `value >= 0.58` branch (lines 124–128, beside `HapticFeedback.heavyImpact`) | `sound.play(Sfx.shohaImpact)` — frame-exact with the slam + haptic (~522 ms in) |

`app/lib/features/game/table_screen.dart`:

| anchor | sound call |
|---|---|
| `_onHandTap` (line 293, beside `HapticFeedback.selectionClick` line 296) | `play(tapSelect)` |
| `_onTargetTap` (line 279, after the validity guards at 281–282) | `play(tapSelect)` |
| lead confirm `FilledButton` (line 1096, beside `_fx.playMyLead`) | `play(buttonPress)` |
| discard confirm (line 1147, beside `_fx.playMyDiscard`) | `play(buttonPress)` |
| `_sendBeat` (line 331–333, beside `_fx.playMyBeat`) | `play(buttonPress)` |
| `endTrick` button (line 1217) | `play(buttonPress)` |
| `_onTableEvent` reaction branch (line 167, where the bubble is set) | `play(reactionPop)` — 300 ms global cooldown absorbs reaction spam |
| `_showNextAchievement` (line 178, beside `HapticFeedback.mediumImpact`) | `play(achievementBell)` |
| `_onGameState` (line 119, new check inside setState): `if (next.isMyTurn && previous?.isMyTurn != true && next.roomPhase == RoomPhase.playing)` | `play(myTurnDing)` — 1500 ms cooldown guards resync flapping |

Deliberately silent: `dealEnded` overlay (`table_screen.dart:132–140`, the count-up animation carries it), opponent card taps (no event exists), lobby ready/rematch buttons (keep chimes scarce).

---

## 4. Generator script — `tools/generate_sounds.py`

- **Deps**: numpy + stdlib (`wave`, `struct`, `pathlib`, `math`). No scipy — filters are FFT-mask based (§2 primitives).
- **Structure**:
  ```
  SR = 44100; OUT_SR = 22050
  OUT_DIR = Path(__file__).resolve().parents[1] / "app" / "assets" / "sounds"
  rng = np.random.default_rng(0xC0A7)                  # fixed seed, deterministic
  # -- primitives: noise, bp, lp, hp, expdec, adsr, glide_sine, detuned_pair, place(buf, grain, at_ms)
  # -- one function per sound, returning float64 array at SR:
  def gen_card_slide() -> np.ndarray: ...
  ... (14 functions, called in a fixed order so rng draws are reproducible)
  # -- write path: peak-normalize -> * MIX_GAIN[name] -> lowpass 9.5 kHz -> x[::2]
  #                -> TPDF dither 0.5 LSB -> int16 -> wave.open(..., nchannels=1,
  #                sampwidth=2, framerate=22050)
  SOUNDS = {"card_slide": (gen_card_slide, 0.65), ...}  # (generator, mix gain)
  main(): generate all, print per-file size table, assert sum < 300_000
  ```
- **Output**: `app/assets/sounds/{card_slide,card_snap,card_flip,deal_riffle,stack_thud,tap_select,button_press,trump_chime,my_turn_ding,achievement_bell,win_fanfare,goat_moan,shoha_impact,reaction_pop}.wav`
- **pubspec.yaml changes** (`app/pubspec.yaml`):
  ```yaml
  dependencies:
    audioplayers: ^6.8.1        # after http: ^1.2.0, line 17
  flutter:
    uses-material-design: true
    assets:
      - assets/sounds/          # whole-directory include, new files auto-picked-up
  ```
- Re-running the script is idempotent (same seed → byte-identical WAVs), so assets can be regenerated in CI and diffed.

Implementation order: (1) generator script + assets, (2) `SoundService` + pubspec, (3) `table_fx.dart`/`flight_layer.dart` hooks, (4) `table_screen.dart` UI hooks + settings entries, (5) tune mix gains on-device (the per-sound `MIX_GAIN` table is the single balancing knob).