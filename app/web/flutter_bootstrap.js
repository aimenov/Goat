{{flutter_js}}
{{flutter_build_config}}

// --- GPU health probe + persisted CPU fallback -----------------------------
// Broken WebGL stacks (driver/ANGLE bugs, GPU resets) make CanvasKit fail
// every shader compile and render a white screen (flutter#140504, #186947).
// canvasKitForceCpuOnly is the only confirmed rescue; we detect the failure
// and reload once into CPU mode instead of leaving the page white.

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

const forceCpu =
  sessionStorage.getItem('flt_force_cpu') === '1' || !webgl2Usable();

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
  window.addEventListener('webglcontextlost', () => trip('context-lost'), true);
})();

if (forceCpu) {
  console.warn('Козёл: rendering in CPU mode (WebGL unavailable or previously failed on this GPU).');
}

_flutter.loader.load({
  config: {
    canvasKitForceCpuOnly: forceCpu,
  },
});
