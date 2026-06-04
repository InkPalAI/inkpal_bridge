import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../inspection/walker_hooks.dart';
import '../network/http_monitor.dart';
import '../telemetry/error_catcher.dart';
import '../ui/error_boundary.dart';
import 'inkpal_bridge.dart';
import 'inkpal_navigator.dart';
import 'welcome_console.dart';

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
  // Defaults to `false` in 2.0.x: the visual overlay sits above MaterialApp
  // and therefore has no Directionality / Overlay ancestor of its own. On
  // some app shells that combination cascades into hit-test failures that
  // block coord-taps. The error CATCHER (which feeds `get_runtime_errors`
  // and friends) is a separate subsystem and remains active regardless of
  // this flag — set this to `true` only if you want the in-app banner.
  bool enableErrorBoundary = false,
  bool enableHttpMonitor = true,
  bool runInRelease = false,
  int screenshotWidth = 720,
  GlobalKey<NavigatorState>? navigatorKey,
  Future<Map<String, dynamic>> Function()? globalStateProvider,
  List<String> knownRoutes = const [],
  Map<String, String> routeDescriptions = const {},
  Future<void> Function(String routeName)? onNavigateToRoute,
  InkPalWalkerHooks? walkerHooks,
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

    // Three-state license behaviour. No silent cloud calls; everything
    // useful runs locally without registration.
    //   - Caller passed a key            → validate against the InkPal cloud
    //   - INKPAL_LICENSE_KEY env present → validate against the InkPal cloud
    //   - No key found                   → run locally in free-offline mode
    final envKey = const String.fromEnvironment('INKPAL_LICENSE_KEY');
    final effectiveKey = (licenseKey != null && licenseKey.isNotEmpty)
        ? licenseKey
        : (envKey.isNotEmpty ? envKey : '');

    // Print the welcome banner before starting the bridge so the developer
    // sees the bridge come alive immediately. This is the cure for the
    // "added it and nothing happened" silent install.
    InkPalWelcomeConsole.instance.start(
      serverUrl: serverUrl,
      licenseKey: effectiveKey,
      errorCatcher: catcher,
    );

    InkPalBridge.init(
      serverUrl: serverUrl,
      licenseKey: effectiveKey,
      apiUrl: apiUrl,
      screenshotWidth: screenshotWidth,
      navigatorKey: navigatorKey ?? inkpalNavigatorKey,
      navigatorObserver: inkpalNavigatorObserver,
      globalStateProvider: globalStateProvider,
      knownRoutes: knownRoutes,
      routeDescriptions: routeDescriptions,
      onNavigateToRoute: onNavigateToRoute,
      walkerHooks: walkerHooks,
      appRunner: () => runApp(root),
      errorCatcher: catcher,
      httpMonitor: monitor,
    );
  });
}
