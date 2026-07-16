All facts verified. Fact sheet follows.

---

# Fact Sheet: Goat — Flutter Web + SFX readiness

## 1. CORS — handled by Colyseus 0.17 core BY DEFAULT (no work needed)

**Installed:** `@colyseus/core` **0.17.44**, `@colyseus/ws-transport` **0.17.13** (`node_modules/@colyseus/core/package.json`, `.../ws-transport/package.json`).

**Evidence:** `node_modules/@colyseus/core/build/router/index.mjs`, `bindRouterToTransport()` lines 48–62: it does `server.prependListener("request", ...)` on the underlying `http.Server` and, for **every** HTTP request (before any routing):
- Answers `OPTIONS` preflight with `204` + CORS headers and returns (lines 53–57).
- Sets CORS headers on all other responses via `res.setHeader` (lines 58–60).

Headers come from `node_modules/@colyseus/core/build/matchmaker/controller.mjs` lines 7–14 (`DEFAULT_CORS_HEADERS`: `Access-Control-Allow-Headers: Origin, X-Requested-With, Content-Type, Accept, Authorization`, `Allow-Methods: GET,HEAD,PUT,PATCH,POST,DELETE`, `Allow-Credentials: true`, `Allow-Origin: *`, `Max-Age: 2592000`) merged with `controller.getCorsHeaders()` (lines 32–36) which sets `Access-Control-Allow-Origin: <request Origin>` (echo, credential-safe). Any `http://localhost:*` Flutter dev origin is allowed.

**Coverage of your endpoints:** `Server.bindRoutes()` (`build/Server.mjs` lines 150–158) merges the custom router (from `defineServer({routes: ...})`, `Server.mjs` lines 254–267 — `server.router = routes`) with the default matchmake routes and calls `bindRouterToTransport`. Since the CORS listener is prepended at the `http.Server` level, **all** of `POST /matchmake/*`, `POST /auth/guest`, `GET /rooms`, `GET /profile/:id` (defined in `packages/server/src/index.ts` lines 17–55) get CORS automatically.

**WebSocket:** browsers do not apply CORS to WebSocket; grep of `@colyseus/ws-transport/build/WebSocketTransport.mjs` shows no origin/`verifyClient` filtering — WS from web will connect.

**Config knob (if ever needed):** override `matchMaker.controller.getCorsHeaders = (headers) => ({...})` — documented in the source comment at `controller.mjs` lines 18–31. No server change needed for dev.

## 2. Dart web compatibility of `app/lib/core/net/transport.dart` — CLEAN

- **Imports** (lines 15–21): `dart:async`, `dart:convert`, `dart:typed_data`, `package:http`, `package:msgpack_dart`, `package:web_socket_channel`. **No `dart:io` anywhere.**
- **BytesBuilder** (used line 137) resolves from `dart:typed_data` — confirmed in installed SDK: `C:\Users\altai\flutter\bin\cache\pkg\sky_engine\lib\typed_data\typed_data.dart:18` → `export "dart:_internal" show BytesBuilder;`. Web-safe.
- **msgpack_dart 1.0.1** (pubspec.lock line 298): pure Dart. Its only imports across `lib/` are `dart:convert` and `dart:typed_data` (`~/AppData/Local/Pub/Cache/hosted/pub.dev/msgpack_dart-1.0.1/lib/msgpack_dart.dart:3-4`; grep for `dart:io|dart:html` over lib/ = no matches).
- **web_socket_channel 3.0.3** (pubspec.lock line 631): `WebSocketChannel.connect` → `AdapterWebSocketChannel.connect` → `package:web_socket` `WebSocket.connect` (`web_socket_channel-3.0.3/lib/src/channel.dart:107-108`, `adapter_web_socket_channel.dart:67-69`). On web, `web_socket 1.0.1` `browser_web_socket.dart:37` sets `binaryType = 'arraybuffer'` and line 78–79 delivers `BinaryDataReceived((eventData as JSArrayBuffer).toDart.asUint8List())` — i.e. **binary frames arrive as `Uint8List` on web**, same as IO. So `transport.dart:82` `(data as List<int>)` works unchanged (Uint8List implements List<int>). `closeCode` is populated from `CloseReceived` (`adapter_web_socket_channel.dart:88-91`).
- `http.Client()` (transport.dart:163) auto-selects `BrowserClient` on web via http 1.6.0's conditional imports. Web-safe.
- **Verdict: the client core compiles and runs on web with zero changes.**

## 3. shared_preferences

Installed **2.5.5** (pubspec.lock line 394), which is also the pub.dev latest. Web is fully supported: transitive `shared_preferences_web 2.4.3` is already in the lockfile (line 434), backed by localStorage. No change needed.

## 4. Audio package — recommend **audioplayers ^6.8.1**

- **audioplayers 6.8.1** (pub.dev latest, verified via API): endorsed federated plugins for **android, ios, web, linux, macos, windows** (pubspec `flutter.plugin.platforms` includes `web: audioplayers_web`).
- Rapid-fire SFX support: **`AudioPool`** class (`AudioPool.createFromAsset(path: 'sfx/x.wav', maxPlayers: N)` then `pool.start()`) — doc page exists at pub.dev/documentation/audioplayers/latest/audioplayers/AudioPool-class.html (HTTP 200). Plus `PlayerMode.lowLatency` (Android SoundPool-backed; doc verified) for single players. Asset API: `player.play(AssetSource('sfx/click.wav'))` reading from the Flutter asset bundle (declare under `flutter: assets:` in pubspec).
- **just_audio 0.10.6** supports web too but is designed for music/playlists (gapless, buffering, audio_session focus handling) — heavier init per player, no pool primitive; overkill and higher latency for tiny WAV SFX.
- **Firm recommendation: `audioplayers: ^6.8.1`**, using one `AudioPool` per SFX (works on all three targets) and `PlayerMode.lowLatency` where a plain player is used.
- *Flag (uncertain):* on web, `audioplayers_web` plays via HTML `AudioElement`, so first-play latency on web is browser-dependent and audio cannot start before a user gesture (browser autoplay policy) — standard for any web audio package, just_audio included.

## 5. Endpoint defaults + full port-2567 inventory

- `kIsWeb` (const, from `package:flutter/foundation.dart`) is the standard web detector and is tree-shaken correctly; combine with `defaultTargetPlatform` for android/ios. Nothing in the repo uses it yet (grep: 0 hits).
- Proposed default in `app/lib/core/session.dart:16-19` (keep `String.fromEnvironment('GOAT_SERVER')` as the override — it works on web via `--dart-define`):
  - **web (kIsWeb):** `http://localhost:2568` — chrome dev talks to the host directly.
  - **android + emulator:** `http://10.0.2.2:2568` (current behavior; a real Android device needs `--dart-define=GOAT_SERVER=http://<LAN-IP>:2568`).
  - **ios simulator:** `http://localhost:2567→2568` (iOS sim shares the host network); real iOS device → dart-define.
  - Logic shape: `kIsWeb ? localhost : defaultTargetPlatform == TargetPlatform.android ? 10.0.2.2 : localhost`, with `GOAT_SERVER` dart-define always winning. (Emulator-vs-real-device can't be distinguished at compile time — dart-define is the escape hatch.)
- **Every `2567` occurrence** (exhaustive grep incl. hidden files, excluding node_modules/build/.git/.dart_tool):
  - `app/lib/core/session.dart:18`
  - `app/test/e2e_transport_test.dart:3, 17`
  - `packages/server/src/config.ts:2` (and generated `packages/server/dist/config.js:2` — regenerated on build)
  - `docker/Dockerfile:24, 25`
  - `docker/compose.prod.yml:13, 20, 45`
  - `docs/design/design-client.md:313`
  - `README.md:29`
  - `10.0.2.2` appears only in `app/lib/core/session.dart:15, 18`.

## 6. Adding web platform (Flutter 3.44.6 installed, stable)

- App is `name: goat_app` (`app/pubspec.yaml:1`); `app/` currently has only `android/` and `ios/` platform dirs (no `web/`).
- **Command (run inside `app/`):** `flutter create --platforms web --project-name goat_app .` — adds only the web platform to the existing project. Generates: `web/index.html`, `web/manifest.json` (PWA manifest — generated for free, edit name/theme-color as nice-to-have), `web/favicon.png`, `web/icons/Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png`. **No pubspec.yaml changes are needed** (web needs no plugin edits; `flutter_web_plugins` is already in the lockfile as SDK transitive, line 158–162).
- **Renderer in Flutter 3.44:** the HTML renderer was removed from Flutter (gone since 3.29); the choices are **CanvasKit** (default for JS builds, `flutter run -d chrome`) and **skwasm** (only via `flutter build web --wasm`, needs wasm-GC browsers and COOP/COEP headers for multithreading). **Recommendation: CanvasKit default** — heavy `CustomPainter` card rendering is exactly its strength, and it requires zero config. No `index.html` renderer tweak exists anymore (the old `flutterWebRenderer` flag is obsolete). Optional later experiment: `flutter build web --wasm` for skwasm.
- *Flag (minor uncertainty):* exact `flutter create` output list is from Flutter's standard template; I could not dry-run it (read-only session), but `--platforms web` on an existing app is the documented, non-destructive path.

## Cross-cutting flags

- `transport.dart:82` casts frames as `List<int>` — verified safe on web (Uint8List), but a **text** frame would crash the cast; Colyseus 0.17 ws-transport sends binary only, so acceptable.
- Docker healthcheck (`docker/Dockerfile:25`) and Caddy proxy (`compose.prod.yml:45`) must move to 2568 together with `config.ts`, or containers will report unhealthy.
- Web dev server origin changes port per run; the server's origin-echo CORS makes that a non-issue.