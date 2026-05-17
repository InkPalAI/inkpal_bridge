import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../license/auto_provision.dart';
import '../network/http_monitor.dart';
import '../telemetry/error_catcher.dart';
import '../ui/error_boundary.dart';
import 'inkpal_bridge.dart';
import 'inkpal_navigator.dart';

/// Stable, package-wide [GlobalKey] attached to the [RepaintBoundary] that
/// `inkpalRunApp` wraps around the user's root widget.
///
/// `ScreenshotCapture` consults this key as its primary capture target so
/// `ext.flutter.inkpal.screenshot` works out of the box for any app booted
/// via `inkpalRunApp`, with no extra wiring from the user.
///
/// Apps that bypass `inkpalRunApp` and call `InkPalBridge.init` directly
/// can still wrap their root manually:
/// ```dart
/// runApp(RepaintBoundary(key: inkpalRootRepaintKey, child: MyApp()));
/// ```
final GlobalKey inkpalRootRepaintKey =
    GlobalKey(debugLabel: 'inkpal_root_repaint');

/// Drop-in replacement for `runApp` that installs InkPal's error catcher,
/// HTTP monitor, and error boundary, and initializes the bridge inside
/// a guarded zone.
///
/// Release builds short-circuit to plain `runApp(app)` when
/// [runInRelease] is false (default) — zero overhead.
///
/// Example:
/// ```dart
/// void main() {
///   inkpalRunApp(
///     const MyApp(),
///     serverUrl: 'ws://localhost:8765',
///     licenseKey: 'ink_...',
///   );
/// }
/// ```
///
/// The [errorCatcher] and [httpMonitor] instances are threaded into
/// [InkPalBridge.init] so the bridge's error subscriber and VM extensions
/// can observe them.
void inkpalRunApp(
  Widget app, {
  String serverUrl = 'ws://localhost:8765',
  String? licenseKey,
  String? apiUrl,
  bool enableErrorBoundary = true,
  bool enableHttpMonitor = true,
  bool runInRelease = false,
  int screenshotWidth = 720,
  GlobalKey<NavigatorState>? navigatorKey,
  Future<Map<String, dynamic>> Function()? globalStateProvider,
}) {
  if (kReleaseMode && !runInRelease) {
    runApp(app);
    return;
  }

  final catcher = InkPalErrorCatcher()..install();
  final monitor = enableHttpMonitor ? (InkPalHttpMonitor()..install()) : null;

  catcher.runGuarded(() async {
    final wrapped = enableErrorBoundary
        ? InkPalErrorBoundary(catcher: catcher, child: app)
        : app;

    // Wrap in a RepaintBoundary tagged with [inkpalRootRepaintKey] so the
    // screenshot extension can always find a render boundary, regardless of
    // whether the user's MaterialApp wraps anything similar at the top.
    final root = RepaintBoundary(key: inkpalRootRepaintKey, child: wrapped);

    // Zero-touch free-tier provisioning. If the caller didn't supply a
    // license key, ask the InkPal API to mint one for this device. Cached
    // locally so the next session is one network round-trip cheaper.
    // Falls back to an offline placeholder if the network is unreachable.
    final effectiveKey = (licenseKey != null && licenseKey.isNotEmpty)
        ? licenseKey
        : await InkPalAutoProvision.ensureKey(apiUrl: apiUrl ?? InkPalBridge.defaultApiUrl);

    InkPalBridge.init(
      serverUrl: serverUrl,
      licenseKey: effectiveKey,
      apiUrl: apiUrl,
      screenshotWidth: screenshotWidth,
      navigatorKey: navigatorKey ?? inkpalNavigatorKey,
      navigatorObserver: inkpalNavigatorObserver,
      globalStateProvider: globalStateProvider,
      appRunner: () => runApp(root),
      errorCatcher: catcher,
      httpMonitor: monitor,
    );
  });
}
