All research complete. Here is the full report.

---

# Root-cause analysis: CanvasKit "Shader compilation error" + white screen on Windows/Chrome, Flutter 3.44.6

## Context established from sources

The quoted shader (`texture(uTextureSampler_0_S1, vTransformedCoords_4_S0, -0.475).x`) is Skia/Ganesh's **glyph-atlas text draw** — single-channel (`.x`) atlas sampled with Skia's hard-coded −0.475 LOD bias used to sharpen bilerp'd glyphs. That shader is trivial and valid GLSL ES 3.00; when *it* fails to compile, the problem is essentially never the shader itself — it is the WebGL context / ANGLE / driver underneath it. That framing drives the ranking below.

## 1. Root causes, ranked by likelihood for THIS signature

**#1 — WebGL context loss cascade (GPU process reset / Windows TDR), most likely.**
The game-table screen is exactly the workload (blur mask filters = large Gaussian offscreen passes, saveLayer fades = offscreen surfaces, radial gradients, many first-time shader compiles at once) that trips a Windows TDR (2-second GPU hang timeout) or Chrome GPU-process reset on Intel/AMD iGPUs. Once the context is lost, **every subsequent `glCompileShader` fails**, so the console fills with "Shader compilation error" for *all* variants — including the innocuous glyph-atlas shader — and CanvasKit can no longer create a surface → solid white screen. This is the documented failure shape: reports pair the shader spam with `WebGL: CONTEXT_LOST_WEBGL: loseContext: context lost` ([#140504 logs](https://github.com/flutter/flutter/issues/140504), [#186947](https://github.com/flutter/flutter/issues/186947)); CanvasKit's context-restore path exists but historically flaky ([#75914](https://github.com/flutter/flutter/issues/75914), [#67949](https://github.com/flutter/flutter/issues/67949)). *Diagnostic:* scroll the console to the **first** error — if `CONTEXT_LOST_WEBGL` precedes the spam, this is it; also check `chrome://gpu` → "Device/context lost" counts.

**#2 — ANGLE/driver HLSL compiler bug on the specific Windows GPU driver.**
The canonical precedent is [flutter/flutter#140504](https://github.com/flutter/flutter/issues/140504) (P1, closed "r: fixed"): identical console signature + white screen, root-caused by yjbanov/kenrussell to a shader-compiler bug **below Flutter — in ANGLE's backend inside Chromium** (there: ANGLE-on-Metal on Intel Macs, Chrome 121–122; fixed Chrome-side by disabling the ANGLE-Metal experiment, [crbug 328302269](https://issues.chromium.org/issues/328302269)). Flutter's conclusion there: *"The bug is somewhere between ANGLE and Metal deep inside Chromium… It doesn't look like we can do much on the Flutter side."* The Windows analog is ANGLE-D3D11 with buggy Intel/AMD iGPU drivers, or Chrome silently using **D3D9on12/WARP** on GPUs without proper D3D11 drivers — heavier screens compile more exotic variants (blur, dither, bias sampling) and hit the broken path while login/lobby screens survive. *Diagnostic:* `chrome://gpu` → "GL_RENDERER" (look for `D3D9on12`, `WARP`, `SwiftShader`) and driver date; test Firefox (different GL stack) on the same machine.

**#3 — Flutter 3.41→3.44 CanvasKit/Skia roll regression on ANGLE-backed WebGL (open, real, current).**
[flutter/flutter#188164](https://github.com/flutter/flutter/issues/188164) (open, P2, `c: regression`, `e: webgl`, June–July 2026): CanvasKit **and** skwasm rendering broken specifically on ANGLE-backed WebGL (Samsung Xclipse ANGLE-on-Vulkan; also Mali-G72 WebView), regression window **3.38.5 (works) → 3.41/3.44.2 (broken)**; text/glyph rendering is precisely what breaks; multiple production teams **rolled back to 3.38.5** as the fix. Your 3.44.6 + ANGLE-D3D11 + glyph-atlas-shader failure plausibly shares this engine roll. *Diagnostic:* rebuild the same app with Flutter 3.38.5 and load the game-table screen on the failing machine — if it renders, you've confirmed the regression (then comment on #188164 with your Windows data; the team asked for bisect help).

**#4 — SwiftShader software fallback / blocklisted GPU.** If Chrome blocklisted the GPU, WebGL runs on SwiftShader; heavy screens can then hit limits or be unusably slow rather than white, so this is least likely — but it's a 10-second check in `chrome://gpu` ("WebGL: Software only, hardware acceleration unavailable").

Notably: [#186947](https://github.com/flutter/flutter/issues/186947) (May 2026, Flutter 3.41.5) is the same console signature where **the only working workaround was `canvasKitForceCpuOnly: true`**, and — critically — **`--wasm`/skwasm failed with identical shader errors**, proving skwasm does *not* avoid this pipeline (see below). It was closed stale, not fixed, so there is no engine-side fix to wait for on this signature class.

## 2. Fix ladder (most reliable first), exact Flutter 3.44 syntax

Flutter 3.44 bootstrap model ([docs: Customize app initialization](https://docs.flutter.dev/platform-integration/web/initialization)): put a custom `flutter_bootstrap.js` in your project's `web/` directory (it replaces the generated one); it must contain `{{flutter_js}}`, `{{flutter_build_config}}`, and a `_flutter.loader.load()` call. Config keys relevant here: `renderer` (`"canvaskit"` | `"skwasm"`), `canvasKitVariant` (`"auto"` (default) | `"full"` | `"chromium"`), `canvasKitForceCpuOnly` (bool — "forces CPU-only rendering in CanvasKit (the engine won't use WebGL)"), `canvasKitMaximumSurfaces`, `forceSingleThreadedSkwasm`. The renderer/config **cannot change after `load()`** — decide before calling it.

### Rung 1 — Deployable safety net: auto-fallback to CPU rendering (reliable; confirmed working in #186947)

`web/flutter_bootstrap.js`:

```js
{{flutter_js}}
{{flutter_build_config}}

// --- GPU health probe + persisted fallback ---
function webgl2Usable() {
  try {
    const c = document.createElement('canvas');
    // failIfMajorPerformanceCaveat filters out SwiftShader/software GL
    const gl = c.getContext('webgl2', { failIfMajorPerformanceCaveat: true });
    if (!gl) return false;
    const ok = gl.getParameter(gl.MAX_TEXTURE_SIZE) >= 4096;
    gl.getExtension('WEBGL_lose_context')?.loseContext();
    return ok;
  } catch (_) { return false; }
}

const forceCpu =
  sessionStorage.getItem('flt_force_cpu') === '1' || !webgl2Usable();

// Detect the failure at runtime and reload into CPU mode once.
(function installShaderErrorTrap() {
  let tripped = false;
  function trip(reason) {
    if (tripped || forceCpu) return;
    tripped = true;
    console.warn('Flutter GPU pipeline failed (' + reason + '); reloading in CPU mode');
    sessionStorage.setItem('flt_force_cpu', '1');
    location.reload();
  }
  const origErr = console.error.bind(console);
  console.error = function (...args) {
    if (String(args[0]).includes('Shader compilation error')) trip('shader-compile');
    origErr(...args);
  };
  // CanvasKit's canvases live inside the flutter view; capture phase catches them all.
  window.addEventListener('webglcontextlost', (e) => trip('context-lost'), true);
})();

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpu,   // software Skia: correct pixels, no WebGL
    // canvasKitVariant: 'full',       // see rung 2
  },
});
```

This turns "white screen forever" into "one automatic reload, then a slow-but-correct app" for affected users, with zero effect on healthy machines. (CPU rendering is slow — #186947 measured it as "extremely slow" — which is why it's a fallback, not the default.)

### Rung 2 — One-line experiment: `canvasKitVariant: 'full'`

On Chrome, `"auto"` serves the **`chromium` variant** — a trimmed CanvasKit build (smaller; assumes Chromium's codecs/APIs; docs warn not to hard-select it "unless you plan on only using Chromium-based browsers"; see also [#123048](https://github.com/flutter/flutter/issues/123048), [#178133](https://github.com/flutter/flutter/issues/178133)). `"full"` is the complete Skia build. Both use the same Ganesh-on-WebGL2 backend, so this is *not* expected to fix a driver/ANGLE bug — but it's a different Skia binary/build config and a 1-line, zero-risk A/B test:

```js
_flutter.loader.load({ config: { canvasKitVariant: 'full' } });
```

### Rung 3 — Confirm/deny the 3.41→3.44 regression; downgrade if confirmed

Build once with **Flutter 3.38.5** and test the game-table screen on a failing machine. If it renders, you've hit [#188164](https://github.com/flutter/flutter/issues/188164)'s regression window; production teams there shipped 3.38.5 until it's fixed. (Also subscribe to that issue — it's open and actively triaged as of July 2026.)

### Rung 4 — `--wasm` / skwasm: NOT a fix for this signature

`flutter build web --wasm` makes skwasm available (with automatic canvaskit fallback on non-WasmGC browsers) ([docs: Web renderers](https://docs.flutter.dev/platform-integration/web/renderers)). But **skwasm is the same Skia compiled to wasm, rendering through the same WebGL2/ANGLE pipeline** — [#186947](https://github.com/flutter/flutter/issues/186947) verified `window._flutter_skwasmInstance === true` and got *identical* "Shader compilation error" spam from `skwasm.js`. Requirements if you go this way anyway (it is faster): multithreading needs SharedArrayBuffer headers (`Cross-Origin-Opener-Policy: same-origin` + `Cross-Origin-Embedder-Policy: require-corp` or `credentialless`); without them it silently runs single-threaded; `forceSingleThreadedSkwasm: true` exists for broken multithreaded environments (and note [#184843](https://github.com/flutter/flutter/issues/184843), a blank-screen report specifically when `crossOriginIsolated=true`). Verdict: useful for perf, useless as a shader-error fix.

### Rung 5 — Reduce shader-variant/GPU pressure on the game-table screen (attacks root cause #1)

Ops that force the expensive/fragile Ganesh variants and offscreen passes:
- **`MaskFilter.blur` / `ImageFilter.blur` / `BackdropFilter`** — Gaussian blur shaders + full offscreen render targets; the single biggest TDR trigger. Replace with pre-blurred PNG assets, `box_shadow`-style gradients, or cached images.
- **`saveLayer`** (including `Opacity`/fade over complex subtrees, `ShaderMask`, `ColorFiltered`) — each creates an offscreen surface. Prefer `FadeTransition` on already-cached content, `AnimatedOpacity` on leaf widgets, `RepaintBoundary` around static table art.
- **Dithered gradients** — modern Flutter no longer dithers by default (`Paint.enableDithering` removed, [#131450](https://github.com/flutter/flutter/issues/131450)); just don't re-enable.
- Text itself (any size/transform) is one cheap atlas shader — it's the *victim* in your log, not the culprit.

Cutting blur + saveLayer count on that screen frequently makes the whole problem vanish because the GPU never resets.

### Rung 6 — Chrome/machine-side (diagnostics & support-desk advice, not deployable)

- `chrome://gpu`: confirm active backend (`D3D11` good; `D3D9on12`/`WARP`/`SwiftShader` = driver problem), driver version/date, context-lost counts.
- **Update the Intel/AMD graphics driver** — the #1 real-world fix for ANGLE-D3D11 HLSL compile failures.
- `chrome://flags` → "Choose ANGLE graphics backend" → try `D3D9` or `OpenGL` (this is how #140504 users isolated ANGLE; Chrome ultimately fixed it by switching backend defaults).
- "Out-of-process 2D canvas rasterization" flag fixed it for some in #140504 — worth one test.
- `--disable-gpu-driver-bug-workarounds` is a *diagnostic only* — it usually makes driver bugs worse, never ship advice around it.

## 3. Runtime detection → helpful fallback instead of white screen

Three layers (the JS trap in Rung 1 is the core; these complete it):

**a) Pre-flight (before `load()`)** — the `webgl2Usable()` probe above. `getContext('webgl2', {failIfMajorPerformanceCaveat: true})` returning null means no hardware WebGL2 → start directly in `canvasKitForceCpuOnly` or show an HTML message.

**b) In-flight (engine already running — your case, since login/lobby work)** — the `console.error` monkey-patch matching `"Shader compilation error"` (CanvasKit logs via Emscripten's `printErr` → `console.error`) plus a capture-phase `webglcontextlost` listener. On trip: show a DOM overlay (`position:fixed` div — plain HTML still renders even when the Flutter canvas is dead) and/or set the sessionStorage flag and reload into CPU mode.

**c) First-frame watchdog (protects cold start)**:
```js
let framed = false;
window.addEventListener('flutter-first-frame', () => { framed = true; });
setTimeout(() => {
  if (!framed) { /* show fallback overlay / trip CPU reload */ }
}, 15000);
```

**d) Dart side** — engine-level shader errors never reach `FlutterError.onError` (they're C++/JS console prints; cf. [#92596](https://github.com/flutter/flutter/issues/92596)). To react in-app (e.g. route the user off the game table and show a "your graphics driver..." dialog), expose a Dart callback to the JS trap:

```dart
import 'dart:js_interop';

@JS('onGpuPipelineFailure')
external set _onGpuPipelineFailure(JSFunction f);

void installGpuFailureHook(void Function(String reason) handler) {
  _onGpuPipelineFailure = ((JSString r) => handler(r.toDart)).toJS;
}
```
and in the JS trap call `globalThis.onGpuPipelineFailure?.('shader-compile')` instead of (or before) reloading. You can also probe WebGL2 from Dart via `package:web`: `HTMLCanvasElement().getContext('webgl2')`.

## Bottom line

Most likely this is **(1) a GPU reset/context-loss cascade triggered by the blur/saveLayer-heavy screen**, on top of **(2) a fragile ANGLE-D3D11/driver combo**, with **(3) the open 3.41→3.44 CanvasKit-on-ANGLE regression (#188164)** a genuine suspect you can confirm with one 3.38.5 build. Ship Rung 1 (probe + auto CPU fallback + overlay) immediately — it is the only universally reliable mitigation on record for this exact signature (#186947) — then de-blur the game-table screen, and A/B a 3.38.5 build to decide whether to pin/downgrade pending #188164.

Sources:
- [flutter/flutter#140504 — Flutter web Shader compilation error (canonical, P1, ANGLE backend bug in Chromium)](https://github.com/flutter/flutter/issues/140504)
- [flutter/flutter#188164 — CanvasKit UI malformed/missing on ANGLE-backed WebGL, regression 3.38.5→3.41/3.44.2 (open)](https://github.com/flutter/flutter/issues/188164)
- [flutter/flutter#186947 — Shader compilation error in CanvasKit AND Skwasm; only canvasKitForceCpuOnly works](https://github.com/flutter/flutter/issues/186947)
- [flutter/flutter#184843 — skwasm blank screen when crossOriginIsolated=true](https://github.com/flutter/flutter/issues/184843)
- [flutter/flutter#75914 — "restoring WebGL context" / context-loss handling](https://github.com/flutter/flutter/issues/75914)
- [flutter/flutter#67949 — Random CanvasKit crash (context loss → shader error)](https://github.com/flutter/flutter/issues/67949)
- [flutter/flutter#92596 — shader compilation error handler not overridable](https://github.com/flutter/flutter/issues/92596)
- [flutter/flutter#123048 — canvasKitVariant documentation](https://github.com/flutter/flutter/issues/123048)
- [flutter/flutter#178133 — canvaskit_chromium variant differences](https://github.com/flutter/flutter/issues/178133)
- [flutter/flutter#131450 — Paint.enableDithering removal](https://github.com/flutter/flutter/issues/131450)
- [Flutter docs — Customize web app initialization (flutter_bootstrap.js, config options; reflects Flutter 3.44.0)](https://docs.flutter.dev/platform-integration/web/initialization)
- [Flutter docs — Web renderers (canvaskit vs skwasm, --wasm, SharedArrayBuffer requirements; reflects Flutter 3.44.0)](https://docs.flutter.dev/platform-integration/web/renderers)
- [Chromium issue 328302269 — ANGLE-Metal shader fix rollout referenced from #140504](https://issues.chromium.org/issues/328302269)