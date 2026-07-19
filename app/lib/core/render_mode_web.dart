/// Web implementation of the render-mode probe: reads the mode the bootstrap
/// script exported before loading the engine.
library;

import 'dart:js_interop';

@JS('__goatRenderMode')
external JSString? get _goatRenderMode;

bool readCpuRenderMode() => _goatRenderMode?.toDart == 'cpu';
