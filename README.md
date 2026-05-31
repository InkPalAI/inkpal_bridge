# inkpal_bridge

> **Let your AI inspect, debug, and control your running Flutter app.**

Works with Claude Code, Cursor, Windsurf, Codex CLI, and Copilot in VS Code.

[![pub package](https://img.shields.io/pub/v/inkpal_bridge.svg)](https://pub.dev/packages/inkpal_bridge)
[![pub points](https://img.shields.io/pub/points/inkpal_bridge)](https://pub.dev/packages/inkpal_bridge/score)

## 60-second setup

```yaml
# pubspec.yaml
dependencies:
  inkpal_bridge: ^1.4.7
```

```dart
// lib/main.dart
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() => inkpalRunApp(const MyApp());
```

```bash
flutter run
```

That's it. No license key required, no signup, no flags. The bridge starts
itself and prints:

```
┌──────────────────────────────────────────────────────────────┐
│  InkPal Bridge active   ·   ws://localhost:8765              │
│                                                              │
│  Connect an AI assistant to see + debug your running app.    │
│                                                              │
│    npx inkpal start    (one-line setup for Claude/Cursor/…)  │
│    inkpal.ai/setup     (manual MCP config + per-IDE guides)  │
│                                                              │
│  License: Free (offline)   ·   Get more: inkpal.ai/signup    │
└──────────────────────────────────────────────────────────────┘
```

The bridge is already watching for errors, HTTP traffic, navigation events,
and widget-tree changes. It runs entirely **debug-only** — release builds
collapse `inkpalRunApp` to a plain `runApp` with zero overhead.

## Connect an AI assistant

Run this in another terminal:

```bash
npx inkpal start
```

That installs the InkPal MCP server into every editor it can find (Claude
Code, Cursor, Windsurf, Codex CLI, Copilot). Restart your editor, then ask
your AI assistant any of these:

```
"What does this app look like right now?"
"Audit my UI for layout issues."
"Trace the navigation from / to /settings."
"Show me where this error came from."
"Tap the save button and screenshot the result."
```

The AI uses the bridge to look at, drive, and reason about your real
running app — not a static analysis of your code.

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

## What you get

### Read your app

Every widget, the active route, form values, error context, log history.
No more "tell me what you see in the simulator." The agent just looks.

### Drive your app

Tap, scroll, type, navigate, capture a screenshot, replay a flow. The agent
can run end-to-end paths through your real app the same way a human QA
would, and verify each step worked.

### Catch what went wrong

When something throws, the bridge captures the error with the widget tree,
navigation stack, and recent logs already attached. The agent gets enough
context to find the cause on the first attempt instead of the fifth.

## Free for everyone

`inkpal_bridge` is free for personal and commercial use. The bridge itself
works offline with no registration.

To unlock the cloud-backed audit + error-catalog + pattern-search features
of the AI agent, sign up at [inkpal.ai/signup](https://inkpal.ai/signup) and
get a free key in 30 seconds. A 24-hour Pro trial of the full AI workflow
ships with every signup.

## Custom widgets (`walkerHooks`)

Have proprietary design-system widgets (`BrandButton`, `GlassCard`) without
standard Material semantics? Teach the bridge to recognise them:

```dart
inkpalRunApp(
  const MyApp(),
  walkerHooks: InkPalWalkerHooks(
    isInteractiveWidget: (w) => w is BrandButton,
    extractTextFrom: (w) => w is BrandButton ? w.label : null,
  ),
);
```

The agent can then say "tap the Save button" and the bridge resolves it
correctly — no need to wrap every callsite in `Semantics(label:)`.

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
inkpalRunApp(
  const MyApp(),
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

The bridge runs entirely in **debug mode**. In release builds, `inkpalRunApp`
collapses to a direct `runApp` call — **zero overhead, zero memory
allocation, no socket, no extension registration**. Your release builds
ship as if the bridge wasn't there.

## Privacy + security

- **Debug-only.** Release builds bypass everything.
- **Local-first.** Communication binds to localhost. Nothing leaves your
  machine without explicit configuration.
- **Sensitive headers redacted.** `Authorization`, `Cookie`, `X-Api-Key`,
  and similar patterns are stripped before any HTTP request is surfaced
  to the agent.
- **Open-source.** MIT-licensed.

## Advanced configuration

For release-mode shipping, custom server URLs, or fine-grained control over
the bridge's subsystems, use `InkPalBridge.init` directly:

```dart
void main() {
  InkPalBridge.init(
    serverUrl: 'ws://localhost:8765',
    licenseKey: const String.fromEnvironment('INKPAL_LICENSE_KEY'),
    appRunner: () => runApp(const MyApp()),
  );
}
```

See [API docs](https://pub.dev/documentation/inkpal_bridge/latest/) for
the full surface.

## Documentation

- [Get started](https://inkpal.ai/docs/install) — sign up + run in 60 seconds
- [Quickstart](https://inkpal.ai/docs/quickstart) — first agent-driven workflow
- [Demo](https://inkpal.ai/demo) — see it in action
- [Support](https://inkpal.ai/support) — Discord, GitHub, email

## Requirements

- Flutter ≥ 3.10
- Dart ≥ 3.0
