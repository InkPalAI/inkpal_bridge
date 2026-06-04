## 1.5.0

- **Stability milestone.** `inkpalRunApp` is now the single recommended
  entry point and exposes the full configuration surface. Power-user
  flags previously reachable only through `InkPalBridge.init`
  (`knownRoutes`, `routeDescriptions`, `onNavigateToRoute`, `walkerHooks`)
  are now first-class parameters on `inkpalRunApp`.
- **Example app updated** to demonstrate the recommended pattern —
  multi-zone showcase (counter / forms / list / custom widgets) booted
  with one `inkpalRunApp(...)` call, no manual bridge wiring.
- **Example smoke test added** (`example/test/smoke_test.dart`) — three
  widget tests covering boot, counter interaction, and route navigation.
- **Package-level dartdoc rewritten** to lead with the one-line
  `inkpalRunApp(MyApp())` setup. `InkPalBridge.init` is documented as the
  power-user / release-mode path.
- **Version constant synced.** `inkpalBridgeVersion` is now bumped in
  lockstep with the pubspec; `ext.flutter.inkpal.ping` reports the real
  shipping version.
- Manual `InkPalBridge.init` and direct exports (`InkPalErrorCatcher`,
  `InkPalHttpMonitor`, `InkPalErrorBoundary`, etc.) remain fully
  supported — no breaking changes.

## 1.4.7

- `inkpalRunApp` now works without any license key. The bridge starts
  in offline free-tier mode, prints a welcome banner with next-step
  guidance, and begins watching for errors, navigation, and HTTP traffic
  immediately.
- Added periodic idle diagnostics when no client is connected, plus
  inline connect / disconnect notices when an AI client attaches.
- Caught errors now surface in a compact console format with location
  parsed from the stack trace.
- Default API endpoint now resolves through the canonical InkPal host.
- Dropped the unused device-fingerprint provisioning path.

## 1.4.6

- `defaultApiUrl` updated to the canonical production endpoint.

## 1.4.5

- Pubspec description trimmed to fit pub.dev's 60–180 character window so
  search snippets render the full description. No code change.

## 1.4.4

- README simplified — single primary use case ("let your AI inspect,
  debug, and control your running Flutter app"), real-conversation example
  near the top, three-capability summary (Read / Drive / Catch), trimmed
  command catalog. The example app already demonstrates the full surface.
- License flow clarified: `inkpal_bridge` is **free for personal and
  commercial use** with a key from inkpal.ai signup. Documented as the
  install path.

## 1.4.3

- **README rewrite.** Stronger positioning ("give your AI a working set of
  hands inside your Flutter app"), explicit comparison vs
  `marionette_flutter` and `flutter_driver`, simplified quick-start path
  (1 init call), reordered tier capabilities into use-case columns, added
  privacy/security section, dropped jargon ("MCP-native"). No code change.
- **Pubspec description rewritten** to lead with capability, not
  acronym — improves first-touch comprehension on pub.dev search results.
- **Custom widgets documented.** `InkPalWalkerHooks` (already public since
  1.4.0) is now first-class in the README + has a working demo in
  `example/lib/main.dart`. Lets the AI agent recognise proprietary widgets
  (`BrandButton`, `GlassCard`, etc.) by label without `Semantics(label:)`
  wrappers. Closes the recognised gap vs `marionette_flutter`.
- **Example app rewritten** as a multi-zone showcase modelled on the
  InkPal battlefield app — counter zone, forms zone, list zone,
  custom-widgets zone exercising `walkerHooks`.
- **Pub.dev score recovery.** Score was 145/160. Two deductions fixed:
  (1) `auto_provision.dart:20` and `log_buffer.dart:11` had `<placeholder>`
  tokens in dartdoc that the analyser flagged as HTML. Replaced with
  shell-style `$placeholder`. (2) CHANGELOG now lists 1.4.1+1.4.2+1.4.3
  in canonical heading format.
- **Topics updated** for discoverability: `mcp`, `ai`, `claude`,
  `copilot`, `agent` (was `ai`, `mcp`, `testing`, `automation`,
  `devtools`).
- **Pricing copy aligned with single Pro model.** Earlier 1.4.3 draft
  carried over the legacy Free / Pro / Studio capability table. Replaced
  with one "What you can do" table — every capability ships with any
  valid license (trial or paid). Reflects the locked single-Pro pricing
  model on inkpal.ai.
- **First-touch pivot: lead with "start free, full power", not prices.**
  Dollar/rupee amounts removed from the README — pub.dev visitors are
  evaluating, not buying. Pricing details live at inkpal.ai/pricing
  for visitors who're already convinced. Same change applied to the
  npm `inkpal` package README. Studies show pricing-on-first-touch is
  a conversion killer for dev tools when the product hasn't earned
  attention yet.

## 1.4.2

- **Version-sync fix.** `inkpalBridgeVersion` constant in
  `lib/src/_version.dart` (which `ext.flutter.inkpal.ping` reports to the
  MCP server) was stuck at `1.4.0` while pubspec moved to 1.4.1, causing
  every handshake to mis-report the running bridge version.
- **Pub.dev score recovery.** 1.4.1 lost 5 score points because its
  CHANGELOG.md didn't include a `## 1.4.1` heading. This release fixes
  the doc convention going forward and documents both 1.4.1 + 1.4.2
  changes below.
- No public API changes from 1.4.1 — drop-in upgrade.

## 1.4.1

- **Packaging hygiene.** Untracked stale `.dart_tool/` artefacts that were
  leaking into the published archive (3 entries in package root, 2 under
  `example/`). Tarball validation cleaner, no source changes.
- **`.pubignore` extended** to explicitly exclude `example/.dart_tool/` and
  `example/build/` so the `example/` showcase app's local build state can
  never bloat future releases.

## 1.4.0

- **App-registered VM extensions.** Host apps can expose their own
  operations via `InkPalAppExtensions.register(name:, description:,
  handler:)` under `ext.flutter.inkpal.app.<name>`. Enumerated + invoked
  through the new MCP tools so downstream teams extend InkPal without
  a bridge republish.
- **Synthetic pointer driver + hit-test probe.** New coordinate-tap
  path dispatches `PointerAdded/Down/Up/Removed` through
  `GestureBinding.handlePointerEvent`, interpolating 40px steps for
  drags. Works on widgets that never emit a `SemanticsAction.tap` —
  raw `Listener`, custom `GestureRecognizer`, `CustomPaint` hit
  regions. Opt-in via `x` + `y` params on
  `ext.flutter.inkpal.tap`; semantics stays the default. Includes a
  `probeHit()` helper that reports whether a point can actually reach
  a target RenderObject or is absorbed by a `ModalBarrier` /
  `IgnorePointer` / overlay first.
- **Walker hooks for design-system widgets.** `InkPalBridge.init(walkerHooks:
  InkPalWalkerHooks(isInteractiveWidget:, shouldStopTraversal:,
  extractTextFrom:))` lets host apps surface their own widget types
  to the agent's interaction vocabulary. All three callbacks optional;
  built-in walker rules still apply when hooks are missing.
- **Zero-config screenshot.** When no `RepaintBoundary` is wired by
  the host app, falls back to compositing the first `RenderView`'s
  live layer tree into a fresh `Scene` and encoding offscreen. Apps
  that initialise the bridge manually without `inkpalRunApp` now get
  working screenshots out of the box. Identical return shape — callers
  can't tell which path ran.
- **Adaptive scroll.** `scrollToFind` now iterates every on-screen
  scrollable deepest-first and gives each a full-budget down + up
  sweep instead of splitting 10/10. Default attempt cap raised to 50;
  stall detection still breaks the loop early on short lists. Fixes
  the "scrolling the wrong scrollable" class of miss on nested lists.

## 1.3.4

- Default API host updated.
- Topics: add `automation`, drop `debugging`.

## 1.3.3

- **B5 fix: element walker re-acquires semantics handle per capture.**
  After multiple push/pop navigation cycles the original `SemanticsHandle`
  could become detached from the current `PipelineOwner`, leaving the
  semantics tree empty even though widgets render visually. The walker now
  disposes + re-acquires the handle before each `captureScreenContext()`
  call (`_reensureSemantics()`), and iterates all `renderViews` instead of
  only the first. This fixes `getWidgetTree` + `getScreenContent` + `tap`
  all returning empty/failing after navigation.

## 1.3.2

- **Auto-wired navigator key + observer.** Two new globals exported from
  the package barrel:
  - `inkpalNavigatorKey` — `GlobalKey<NavigatorState>` the bridge uses
    to drive `Navigator.pop()` directly from `ext.flutter.inkpal.goBack`,
    no more "tap the back arrow" gymnastics.
  - `inkpalNavigatorObserver` — singleton `InkPalNavigatorObserver` so
    `getCurrentRoute` works without consumers having to construct their
    own observer.
  Wire on your `MaterialApp`:
  ```dart
  MaterialApp(
    navigatorKey: inkpalNavigatorKey,
    navigatorObservers: [inkpalNavigatorObserver],
    home: ...,
  )
  ```
  Without these, `goBack` falls back to its old tap-the-arrow behaviour.

## 1.3.1

Field-test bug fixes surfaced by running the bridge against a real Flutter
benchmark app and exercising `ext.flutter.inkpal.*` extensions.

- **B1 — Screenshot extension always failed on freshly launched apps.**
  `inkpalRunApp` now wraps the user's root in a `RepaintBoundary` tagged
  with the package-wide `inkpalRootRepaintKey`. `ScreenshotCapture` falls
  back to that key when the configured `appContentKey` has no context, and
  the new `captureWithDiagnostics()` API surfaces the actual exception +
  truncated stack instead of the opaque `"Screenshot capture failed"`
  string. The `ext.flutter.inkpal.screenshot` extension now reports the
  real cause of failure.
- **B2 — `getCurrentRoute` returned null after `MaterialPageRoute(builder:)`
  pushes.** `InkPalNavigatorObserver` previously skipped routes whose
  `settings.name` was null, leaving the stack empty even after a successful
  push. The observer now falls back to a `<RuntimeType>` synthetic
  identifier (e.g. `<MaterialPageRoute<void>>`). For stable identifiers
  across builds, callers should still pass
  `MaterialPageRoute(builder: ..., settings: RouteSettings(name: '/foo'))`.
- **B3 — `getWidgetTree` did not surface `ValueKey<String>`-tagged anchors
  like Figma `Scaffold(key: ValueKey('fig-2-5'))`.** The tree walker now
  runs an Element-tree pass after the semantics pass and emits a
  `UiElementType.keyed` entry (with the new `key` field on `UiElement`)
  for every `ValueKey<String>`-tagged widget — surfacing structural
  anchors that don't carry a semantics label of their own.
- **B4 — `ext.flutter.inkpal.ping` reported the hardcoded version
  `"1.0.0"`.** Added `lib/src/_version.dart` — a single
  `inkpalBridgeVersion` constant that the ping handler reads. Bump this
  in lockstep with `pubspec.yaml` (no codegen, no extra dep).

### New tests

- `test/screenshot_capture_test.dart` — fallback to `inkpalRootRepaintKey`
  + structured failure-error coverage.
- `test/route_observer_test.dart` — unnamed `MaterialPageRoute` push now
  populates the route stack; explicit `RouteSettings.name` still wins;
  pop removes the synthetic identifier.
- `test/widget_tree_keyed_test.dart` — `ValueKey<String>`-tagged Scaffold
  surfaces with `type: keyed`; multiple keyed widgets de-dupe; non-string
  ValueKeys are ignored; JSON round-trip carries the key.

## 1.3.0

- **Socket reconnect hardened** — exponential backoff with jitter (500ms base × 2^attempt, ±200ms), 5-minute cap, stops after 30 consecutive failures
- **VM extensions decoupled from WS state** — extensions now work regardless of WebSocket connection status
- **Fixed `dispose()` LateInit crash** — safe to call repeatedly, including after failed init
- **`_perfMonitor` guaranteed initialized** in all `init()` code paths
- **Testing hooks exposed** — `@visibleForTesting` getters for `router` (CommandRouter) and `semanticsWalker` (SemanticsWalker)
- **`SemanticsWalker` re-exported** from public barrel
- **New tests:** `reconnect_test.dart`, `dispose_test.dart`, `visible_for_testing_test.dart` — 12+ new tests across all new/fixed behavior
- **New test fixture:** `test_app/` with keyed widget harness + 40 integration tests covering all 33 VM extensions
- **New CI:** `.github/workflows/bridge-e2e.yml` runs on Android emulator + iOS simulator on every bridge push

## 1.2.2

- Remove comparison-to-alternatives section from README
- No code changes

## 1.2.1

- Sharpened pubspec description with target search keywords (Flutter MCP, runtime error capture, HTTP monitor, VM service extensions)
- README: added comparison table vs `moinsen_runapp` and `marionette_mcp`
- README: bumped install version to ^1.2.1
- No code changes

## 1.2.0

- Added `InkPalErrorCatcher`: three-layer error capture (FlutterError + PlatformDispatcher + runZonedGuarded) with time-windowed deduplication and handler chaining
- Added `InkPalHttpMonitor`: read-only HTTP request monitor with redacted headers, ring buffer, and collision detection against `InkPalNetworkInterceptor`
- Added `InkPalErrorBoundary`: Stack-based overlay widget that survives app rebuild failures, with debug + release builders
- Added `generateInkPalBugReport`: packages errors, HTTP, logs, route, and app state as markdown for LLM consumption (capped at 8k chars)
- Added `inkpalRunApp`: drop-in `runApp` replacement wiring error catcher + HTTP monitor + error boundary + bridge init inside a guarded zone
- Added optional `errorCatcher` and `httpMonitor` parameters to `InkPalBridge.init` (backward-compatible)
- Fixed `ErrorSubscriber` silently dropping errors before `startWatching()` — ring buffer now always populated, `_watching` gates only stream notification

## 1.1.0

- WebSocket connect timeout (10s) with TimeoutException on miss
- `licenseReady` future on InkPalBridge for license-gated startup flows
- Grace period enforcement moved to `tier` getter (callers bypassing `hasFeature()` now get downgraded correctly)
- Screenshot capture wrapped in 5s timeout — returns null instead of hanging
- License validator test suite (validation flow, grace period, throttle, network failure)

## 1.0.1

- Shortened package description for pub.dev display
- Fixed homepage URL (now points to GitHub repo)
- Removed web platform declaration (package uses `dart:io`)
- Suppressed `hasFlag` deprecation warnings

## 1.0.0

Initial stable release.

### Core
- WebSocket-based bidirectional communication (JSON-RPC 2.0)
- Automatic reconnection with exponential backoff (1s-64s)
- 10-second connection timeout
- Message buffering during disconnects (100 message cap)
- Zero overhead in release builds (bridge is `null`)

### Inspection
- Semantics tree walking — read UI without instrumentation
- Widget tree as structured JSON
- Element search by label or text
- Screenshot capture with configurable width (default 720px, 5s timeout)
- Screen context caching with automatic invalidation

### Interaction
- Tap, long press, double tap by label/key/semantics
- Text field input
- Scroll (directional + scroll-to-element)
- Slider/stepper increment and decrement
- Route navigation (push, pop, go)

### Navigation
- Route tracking via NavigatorObserver
- Full navigation stack access
- Route discovery (all routes seen in session)
- Support for standard Navigator, go_router, GetX, and Beamer
- Custom `onNavigateToRoute` callback for any router

### Telemetry
- Structured logging (log, debug, warning, error levels)
- Real-time error streaming with immediate delivery
- Log batching (500ms intervals for non-error logs)
- Error context enrichment (widget tree, state, recent logs)
- Log correlation — time-windowed action-to-log mapping

### State Time-Travel
- State snapshot capture
- Snapshot listing and retrieval
- State diffing between any two snapshots
- Live state stream observation
- Max 50 snapshots with automatic eviction

### Interaction Recording
- Record user/AI interactions as typed actions
- Export as JSON or Dart integration test code
- Recording status monitoring

### Layout Diffing
- Screen layout snapshot capture
- Before/after layout comparison

### Performance
- FPS monitoring
- Jank detection

### Network Control (Studio tier)
- Per-URL HTTP mock rules (pattern matching, response code, body, delay)
- Offline mode (block all requests)
- Latency and packet loss simulation

### VM Service Extensions
- 33 extensions registered under `ext.flutter.inkpal.*`
- Fallback channel for local development without WebSocket
- Mirrors all WebSocket commands

### License Gating
- Three tiers: Free, Pro, Studio
- Server-side validation with signed grants (HMAC-SHA256)
- 24-hour grant TTL with 7-day grace period
- Validation throttling (60s cooldown)
- `licenseReady` future for callers needing gate sync

### App Manifest
- Rich `AiAppManifest` for LLM context
- Screen manifest with widget descriptions
- App map with full structure

### Touch Visualization
- Visual ripple overlay for AI-driven interactions
- Configurable via `TouchVisualizerController`

### Platform
- Zero third-party dependencies (Flutter SDK only)
- Flutter 3.10+ / Dart 3.0+
- MIT license
