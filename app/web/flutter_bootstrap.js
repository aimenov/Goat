{{flutter_js}}
{{flutter_build_config}}

// --- GPU health probe + persisted CPU fallback -----------------------------
// Broken WebGL stacks (driver/ANGLE bugs, GPU resets) make CanvasKit fail
// every shader compile and render a white screen (flutter#140504, #186947).
// canvasKitForceCpuOnly is the only confirmed rescue; we detect the failure
// and reload into CPU mode instead of leaving the page white — but a single
// transient trip (sleep/resume context loss) must not cost GPU rendering for
// the whole tab session, so the fallback expires and GPU gets retried.

const TRIP_WINDOW_MS = 10 * 60 * 1000; // recent-trip counting window
const CPU_TTL_MS = 30 * 60 * 1000; // how long a timestamped CPU flag holds
const MAX_RECENT_TRIPS = 2; // trips inside TRIP_WINDOW before CPU
const MAX_TOTAL_TRIPS = 4; // trips ever (this tab) before permanent CPU
const HEALTHY_MS = 90 * 1000; // GPU uptime that clears recent counters

function webgl2Usable() {
  try {
    const c = document.createElement('canvas');
    // failIfMajorPerformanceCaveat filters out SwiftShader/software GL
    const gl = c.getContext('webgl2', { failIfMajorPerformanceCaveat: true });
    if (!gl) return false;
    const ok = gl.getParameter(gl.MAX_TEXTURE_SIZE) >= 4096;
    const lose = gl.getExtension('WEBGL_lose_context');
    if (lose) lose.loseContext();
    return ok;
  } catch (_) {
    return false;
  }
}

function readInt(key) {
  const n = parseInt(sessionStorage.getItem(key), 10);
  return Number.isFinite(n) ? n : 0;
}

// Load-time decision. The probe is authoritative: when it fails we render on
// CPU without touching any flags (no retry loop against a GPU that isn't
// there). Otherwise `flt_force_cpu` holds either 'perm' (this tab gave up)
// or the epoch-ms of the trip that set it; a stale timestamp (>30 min, incl.
// the legacy value '1' which parses as epoch 1) earns one guarded GPU retry —
// pre-armed to 1 recent trip so a single failure drops straight back to CPU.
const forceCpu = (() => {
  if (!webgl2Usable()) return true;
  const flag = sessionStorage.getItem('flt_force_cpu');
  if (flag === null) return false;
  if (flag === 'perm') return true;
  if (Date.now() - (parseInt(flag, 10) || 0) < CPU_TTL_MS) return true;
  sessionStorage.removeItem('flt_force_cpu');
  sessionStorage.setItem('flt_gpu_trips', '1');
  sessionStorage.setItem('flt_gpu_trip_ts', String(Date.now()));
  console.info('Козёл: прошло достаточно времени — пробуем снова включить GPU-рендеринг (одна попытка; при сбое вернёмся в CPU-режим).');
  return false;
})();

(function installShaderErrorTrap() {
  let tripped = false;
  function trip(reason) {
    if (tripped || forceCpu) return;
    tripped = true;
    console.warn('Flutter GPU pipeline failed (' + reason + ')');
    const now = Date.now();
    const total = readInt('flt_gpu_trips_total') + 1;
    sessionStorage.setItem('flt_gpu_trips_total', String(total));
    const lastTs = readInt('flt_gpu_trip_ts');
    const recent = (now - lastTs < TRIP_WINDOW_MS ? readInt('flt_gpu_trips') : 0) + 1;
    if (total >= MAX_TOTAL_TRIPS) {
      // This GPU keeps failing across retries — stop burning reloads on it.
      sessionStorage.setItem('flt_force_cpu', 'perm');
      sessionStorage.removeItem('flt_gpu_trips');
      sessionStorage.removeItem('flt_gpu_trip_ts');
      console.warn('Козёл: GPU-рендеринг сбоит постоянно — CPU-режим включён до закрытия вкладки.');
    } else if (recent >= MAX_RECENT_TRIPS) {
      // Two trips inside 10 min: back off to CPU, but only for 30 min.
      sessionStorage.setItem('flt_force_cpu', String(now));
      sessionStorage.removeItem('flt_gpu_trips');
      sessionStorage.removeItem('flt_gpu_trip_ts');
      console.warn('Козёл: перезагрузка в CPU-режиме (примерно на 30 минут, затем GPU будет опробован снова).');
    } else {
      // First trip in the window: one free GPU retry — a transient context
      // loss (sleep/resume, driver reset) usually succeeds on reload.
      sessionStorage.setItem('flt_gpu_trips', String(recent));
      sessionStorage.setItem('flt_gpu_trip_ts', String(now));
      console.warn('Козёл: перезагрузка с повторной попыткой GPU-рендеринга.');
    }
    location.reload();
  }
  const origErr = console.error.bind(console);
  console.error = function (...args) {
    if (String(args[0]).includes('Shader compilation error')) trip('shader-compile');
    origErr(...args);
  };
  // CanvasKit's canvases live inside the flutter view; capture phase catches them all.
  window.addEventListener('webglcontextlost', () => trip('context-lost'), true);
  // 90 s of healthy GPU rendering forgives earlier trips, so a rare hiccup
  // hours later starts the count from scratch instead of tripping to CPU.
  if (!forceCpu) {
    setTimeout(() => {
      if (tripped) return;
      sessionStorage.removeItem('flt_gpu_trips');
      sessionStorage.removeItem('flt_gpu_trip_ts');
    }, HEALTHY_MS);
  }
})();

if (forceCpu) {
  console.warn('Козёл: rendering in CPU mode (WebGL unavailable or previously failed on this GPU).');
  // The flag lives in sessionStorage, so it survives reloads of this tab only.
  console.info('Козёл: CPU-режим временный — закройте вкладку и откройте игру заново, чтобы сразу попробовать GPU-рендеринг ещё раз.');
}

// The app reads this to switch into reduced-effects mode (fewer particles,
// no glows/gradients) — CPU rasterization can't keep 60 fps otherwise.
window.__goatRenderMode = forceCpu ? 'cpu' : 'gpu';

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpu,
  },
});
