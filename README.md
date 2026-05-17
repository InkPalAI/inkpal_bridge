# inkpal_bridge

> **Let your AI inspect, debug, and control your running Flutter app.**

Works with Claude Code, Cursor, Windsurf, Codex CLI, and Copilot in VS Code.

[![pub package](https://img.shields.io/pub/v/inkpal_bridge.svg)](https://pub.dev/packages/inkpal_bridge)
[![pub points](https://img.shields.io/pub/points/inkpal_bridge)](https://pub.dev/packages/inkpal_bridge/score)

## What it looks like in your editor

```
You:    "There's a layout bug on the settings screen. Find it and fix it."

Agent:  → navigates to /settings
        → reads the widget tree
        → captures the runtime error
        → screenshots the broken state
        → applies the fix in lib/screens/settings.dart
        → re-runs the screen
        → screenshots the fixed state

        "Fixed: Row was missing Expanded around the long Text. Diff committed."
```

That's the loop. Real Flutter apps. Real fixes. Visible proof.
The bridge is what lets the agent *do* any of that on a real running app.

## Free forever — register once

`inkpal_bridge` is debug-only and **free for personal and commercial use**.
Sign up at [inkpal.ai](https://inkpal.ai/signup) — takes 30 seconds, no
card — and you get an API key that works **forever** with this package.

The optional 24-hour trial of the AI agent layer (the part that turns
your editor's AI into a Flutter-aware automation agent) is a separate
upgrade — see [inkpal.ai](https://inkpal.ai). The bridge keeps working
with your free key whether you continue with the AI layer or not.

## 60-second setup

```yaml
# pubspec.yaml
dependencies:
  inkpal_bridge: ^1.4.4
```

```dart
// lib/main.dart
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  InkPalBridge.init(
    serverUrl: 'ws://localhost:8765',
    appRunner: () => runApp(const MyApp()),
    licenseKey: const String.fromEnvironment('INKPAL_LICENSE_KEY'),
  );
}
```

```bash
flutter run --dart-define=INKPAL_LICENSE_KEY=your_free_key
```

That's the install.

## What you get

The bridge gives the AI agent three capabilities that change what it can
do for you:

### Read your app

The agent can see what's actually on screen — every widget, the active
route, form values, error context, log history. No more "tell me what
you see in the simulator." It just looks.

### Drive your app

Tap, scroll, type, navigate, capture a screenshot, replay a flow. The
agent can run end-to-end paths through your real app the same way a
human QA would, and verify each step worked.

### Catch what went wrong

When something throws, the bridge captures the error with the widget
tree, navigation stack, and recent logs already attached. The agent
gets enough context to find the cause on the first attempt instead of
the fifth.

## (Optional) Wire navigator + screenshot anchor

For named-route navigation and faster screenshots, add two optional
hooks to your `MaterialApp`:

```dart
MaterialApp(
  navigatorObservers: [
    if (InkPalBridge.instance != null)
      InkPalBridge.instance!.navigatorObserver,
  ],
  home: RepaintBoundary(
    key: InkPalBridge.instance?.repaintBoundaryKey,
    child: const HomeScreen(),
  ),
)
```

## Custom widgets (`walkerHooks`)

Have proprietary design-system widgets (`BrandButton`, `GlassCard`)
without standard Material semantics? Teach the bridge to recognise them:

```dart
InkPalBridge.init(
  serverUrl: 'ws://localhost:8765',
  appRunner: () => runApp(const MyApp()),
  walkerHooks: InkPalWalkerHooks(
    isInteractiveWidget: (w) => w is BrandButton,
    extractTextFrom: (w) => w is BrandButton ? w.label : null,
  ),
);
```

The agent can then say "tap the Save button" and the bridge resolves
it correctly — no need to wrap every callsite in `Semantics(label:)`.

A working demo lives in [example/lib/main.dart](example/lib/main.dart).

## Router support

Works with every major Flutter router. Pass `onNavigateToRoute` so the
bridge can drive named navigation:

```dart
// go_router
onNavigateToRoute: (route) async => router.go(route),

// GetX
onNavigateToRoute: (route) async => Get.toNamed(route),

// Beamer
onNavigateToRoute: (route) async => beamerDelegate.beamToNamed(route),
```

Standard `Navigator` works without any callback.

## App-state context

Expose your app's runtime state so the agent has more to reason about:

```dart
InkPalBridge.init(
  serverUrl: 'ws://localhost:8765',
  appRunner: () => runApp(const MyApp()),
  globalStateProvider: () async => {
    'user': {'plan': currentUser.plan},
    'cart': {'items': cart.length, 'total': cart.total},
  },
);
```

## Architecture

```
Your AI assistant   ⇄   inkpal_bridge   ⇄   your running Flutter app
```

The bridge runs entirely in **debug mode**. In release builds, `init()`
collapses to a direct `appRunner()` call — **zero overhead, zero memory
allocation, no socket, no extension registration**. Your release builds
ship as if the bridge wasn't there.

## Privacy + security

- **Debug-only.** Release builds bypass everything.
- **Local-first.** Communication binds to localhost. Nothing leaves
  your machine without explicit configuration.
- **Sensitive headers redacted.** `Authorization`, `Cookie`, `X-Api-Key`,
  and similar patterns are stripped before any HTTP request is surfaced
  to the agent.
- **Offline-tolerant.** Cached license grants survive network outages.
- **Open-source.** MIT-licensed.

## Documentation

- [Get started](https://inkpal.ai/docs/install) — sign up + run in 60 seconds
- [Quickstart](https://inkpal.ai/docs/quickstart) — first agent-driven workflow
- [Demo](https://inkpal.ai/demo) — see it in action
- [Support](https://inkpal.ai/support) — Discord, GitHub, email

## Requirements

- Flutter ≥ 3.10
- Dart ≥ 3.0
- Debug mode (zero overhead in release)

Supported platforms: Android · iOS · macOS · Linux · Windows.

## License

MIT — see [LICENSE](LICENSE).
