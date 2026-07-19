/// Non-web implementation of the render-mode probe: mobile/desktop/VM tests
/// always render with GPU acceleration (or don't care).
library;

bool readCpuRenderMode() => false;
