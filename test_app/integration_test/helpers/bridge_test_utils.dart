// Shared helpers for InkPal bridge integration tests.
//
// Coverage strategy
// -----------------
// The bridge exposes its in-app surface in three ways:
//   1. Public Dart API on `InkPalBridge.instance` (logger, stateJournal,
//      recorder, navigatorObserver, isAppReady).
//   2. VM service extensions (`ext.flutter.inkpal.*`) — invoked over the
//      VM service protocol from outside the isolate.
//   3. WebSocket commands — invoked over a TCP socket from the MCP server.
//
// In `flutter test integration_test/`, only path (1) is directly callable.
// Paths (2) and (3) require either `flutter drive` (for VM service) or a
// running WebSocket server, neither of which is available in plain widget
// tests. Tests that depend on those paths assert what they CAN assert:
//   - the bridge initialised and the underlying logic component is reachable,
//   - the registered handler exists (best-effort sentinel check),
// and are otherwise marked `skip: 'needs VM service / flutter drive — T3 CI'`.
//
// The intent matches the task brief's "Option C": each extension/command has
// at least one test that exercises adjacent logic, and end-to-end coverage
// lands in Task 3 (`flutter drive`).

import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';
import 'package:test_app/main.dart' as app;

bool _booted = false;

/// Boot the bridge once at process start, BEFORE any test records its
/// SemanticsHandle baseline. This makes the bridge's persistent
/// SemanticsHandle part of every test's baseline so the framework's
/// end-of-test verification doesn't flag it as a leak.
///
/// Call from inside `main()` before `IntegrationTestWidgetsFlutterBinding
/// .ensureInitialized()` is too early (binding not ready) — instead call
/// from inside a `setUpAll` registered before any `testWidgets`.
Future<void> ensureBridgeBooted() async {
  if (_booted) return;
  app.main();
  _booted = true;
  // Yield once so runApp's initial frame schedules.
  await Future<void>.delayed(const Duration(milliseconds: 50));
}

/// Boots the test app exactly once per test process and waits for the bridge
/// to register VM extensions. Subsequent calls in the same process re-pump
/// the existing widget tree without re-initialising the bridge.
///
/// Why once-per-process? The bridge's [InkPalBridge.dispose] currently throws
/// `LateInitializationError: Field '_perfMonitor has not been initialized'`
/// when called on a re-initialised instance (the second init path doesn't
/// assign every late-final field before dispose can run). That leaves the
/// SemanticsHandle dangling and the framework's end-of-test verification
/// flags it. By initialising once we sidestep that bridge bug entirely.
/// See report — flagged for Task 4 (bridge hardening).
Future<void> bootApp(WidgetTester tester) async {
  if (!_booted) {
    app.main();
    _booted = true;
  } else {
    // Re-pump so any expected-to-render widgets are fresh.
    await tester.pump();
  }
  // Two settle passes: first to let runApp mount, second to let the bridge's
  // post-frame callback flip `_appReady` to true.
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
  await tester.pumpAndSettle(const Duration(milliseconds: 250));
}

/// Returns true if a VM service extension with the given short name appears
/// to be registered. We can't introspect the registry directly, but
/// [developer.registerExtension] throws ArgumentError with
/// "Extension already registered" on duplicate registration — we exploit that
/// as a probe.
bool isExtensionRegistered(String shortName) {
  final method = 'ext.flutter.inkpal.$shortName';
  try {
    developer.registerExtension(method, (m, p) async {
      return developer.ServiceExtensionResponse.result('{}');
    });
    // If we reach here, no one had registered it — that means the bridge did
    // NOT register it. Best-effort cleanup is impossible (no unregister API),
    // so subsequent runs in the same isolate will see this stub.
    return false;
  } catch (_) {
    return true;
  }
}

/// Convenience: assert a VM extension was registered by the bridge.
void expectExtensionRegistered(String shortName) {
  expect(
    isExtensionRegistered(shortName),
    isTrue,
    reason: 'ext.flutter.inkpal.$shortName should be registered by the bridge',
  );
}

/// No-op kept for backward compatibility with tests that call it. Cleanup
/// happens at process exit (when the test isolate dies) — the bridge is a
/// singleton initialised once per process via [bootApp], and disposing it
/// between tests trips a known bridge bug (see [bootApp] doc comment).
Future<void> teardownBridge(WidgetTester tester) async {
  // intentionally empty
}

/// Returns the singleton bridge instance (asserts non-null).
InkPalBridge requireBridge() {
  final b = InkPalBridge.instance;
  expect(b, isNotNull, reason: 'InkPalBridge.instance must be initialised');
  return b!;
}

/// Pump-and-find shortcut for the `ext_<suffix>` keyed widgets in the harness.
Finder findExt(String suffix) => find.byKey(ValueKey('ext_$suffix'));
