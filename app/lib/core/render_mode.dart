/// Render-mode bridge: whether the web bootstrap fell back to CPU-only
/// CanvasKit (`window.__goatRenderMode`, set by `web/flutter_bootstrap.js`
/// before the engine loads). CPU rasterization can't keep 60 fps with the
/// full effect stack, so widgets consult [cpuRenderMode] to drop shadows,
/// gradients and particle counts. Always false on mobile/desktop/VM tests.
library;

import 'package:flutter/foundation.dart';

import 'render_mode_stub.dart'
    if (dart.library.js_interop) 'render_mode_web.dart' as impl;

bool? _cpuRenderMode;

/// True when the page renders without GPU acceleration. Cached: the mode is
/// fixed for the lifetime of the page (the bootstrap reloads to change it).
bool get cpuRenderMode => _cpuRenderMode ??= impl.readCpuRenderMode();

/// Test hook: force the mode (`null` restores platform detection).
@visibleForTesting
void debugSetCpuRenderMode(bool? value) {
  _cpuRenderMode = value;
}
