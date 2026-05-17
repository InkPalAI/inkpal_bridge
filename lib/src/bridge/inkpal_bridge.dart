import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../communication/command_router.dart';
import '../memory/state_journal.dart';
import '../testing/interaction_recorder.dart';
import '../communication/telemetry_sender.dart';
import '../telemetry/error_catcher.dart';
import '../telemetry/error_subscriber.dart';
import '../network/http_monitor.dart';
import '../communication/ws_channel.dart';
import '../inspection/context_cache.dart';
import '../inspection/layout_differ.dart';
import '../inspection/screen_context.dart';
import '../inspection/context_invalidator.dart';
import '../inspection/navigator_observer.dart';
import '../inspection/route_discovery.dart';
import '../inspection/screenshot_capture.dart';
import '../inspection/semantics_walker.dart';
import '../inspection/walker_hooks.dart';
import '../interaction/action_executor.dart';
import '../interaction/touch_visualizer.dart';
import '../license/feature_gate.dart';
import '../license/feature_tier.dart';
import '../license/license_validator.dart';
import '../logger/inkpal_logger.dart';
import '../logger/log_event.dart';
import '../manifest/ai_app_manifest.dart';
import '../telemetry/inkpal_observer.dart';
import '../telemetry/log_buffer.dart';
import '../telemetry/performance_monitor.dart';
import 'vm_extensions.dart';

/// InkPal Bridge — in-app intelligence for AI-powered Flutter development.
///
/// Gives AI tools (Claude Code, Cursor) direct control over your Flutter
/// app's UI + real-time error telemetry via WebSocket.
///
/// In release mode, [init] just calls appRunner() with zero overhead.
/// In debug mode, it sets up:
/// - **WebSocket** (primary channel) — bidirectional: commands IN, telemetry OUT
/// - Semantics tree inspection (read UI)
/// - Action execution (tap, text, scroll, navigate)
/// - Screenshot capture (on-demand only — never auto-captures)
/// - Real-time structured logging + error streaming
/// - VM Service extensions (fallback for local dev)
/// - License-gated feature access
///
/// ## Architecture
///
/// ```
/// AI Tool → MCP Server → WebSocket → inkpal_bridge (in-app)
///                                    ↑ commands (tap, inspect, navigate)
///                                    ↓ telemetry (logs, errors, perf)
///
/// Fallback: AI Tool → MCP Server → VM Service → ext.flutter.inkpal.*
/// ```
///
/// The WebSocket channel is the moat — real-time bidirectional communication
/// that no other Flutter AI tool provides. VM Service extensions serve as a
/// fallback for local development when the WebSocket server isn't running.
class InkPalBridge {
  /// Default InkPal API endpoint for license validation.
  /// Override via `apiUrl` parameter in [init] for self-hosted or staging.
  static const String defaultApiUrl = 'https://mcp.inkpal.ai';

  static InkPalBridge? _instance;
  static bool _disposed = false;

  /// Optional external error catcher injected via [init]. Null unless the
  /// caller uses `inkpalRunApp` or passes their own [InkPalErrorCatcher].
  static InkPalErrorCatcher? _injectedErrorCatcher;

  /// Optional external HTTP monitor injected via [init].
  static InkPalHttpMonitor? _injectedHttpMonitor;

  /// The injected error catcher, if any. Accessed by VM extensions /
  /// error subscribers that want to observe the wider catch net.
  static InkPalErrorCatcher? get injectedErrorCatcher => _injectedErrorCatcher;

  /// The injected HTTP monitor, if any.
  static InkPalHttpMonitor? get injectedHttpMonitor => _injectedHttpMonitor;

  // Nullable fields so that partial init + dispose is always safe.
  // A convenience getter exposes each one to in-class code (where we know
  // init() has completed). Any late-stage failure in init() or a re-init
  // cycle won't leave dispose() throwing LateInitializationError.
  InkPalLogger? _loggerField;
  SemanticsWalker? _walkerField;
  ActionExecutor? _executorField;
  ScreenshotCapture? _screenshotField;
  InkPalNavigatorObserver? _navObserverField;
  RouteDiscovery? _routeDiscoveryField;
  ContextCache? _contextCacheField;
  ContextInvalidator? _contextInvalidatorField;
  ReconnectingWebSocket? _wsField;
  CommandRouter? _routerField;
  TelemetrySender? _senderField;
  InkPalTelemetryObserver? _telemetryObserverField;
  InkPalLogBuffer? _logBufferField;
  PerformanceMonitor? _perfMonitorField;
  TouchVisualizerController? _touchVisualizerField;
  StateJournal? _stateJournalField;
  InteractionRecorder? _recorderField;
  ErrorSubscriber? _errorSubscriberField;

  InkPalLogger get _logger => _loggerField!;
  SemanticsWalker get _walker => _walkerField!;
  ActionExecutor get _executor => _executorField!;
  ScreenshotCapture get _screenshot => _screenshotField!;
  InkPalNavigatorObserver get _navObserver => _navObserverField!;
  RouteDiscovery get _routeDiscovery => _routeDiscoveryField!;
  ContextCache get _contextCache => _contextCacheField!;
  ContextInvalidator get _contextInvalidator => _contextInvalidatorField!;
  ReconnectingWebSocket get _ws => _wsField!;
  CommandRouter get _router => _routerField!;
  TelemetrySender get _sender => _senderField!;
  InkPalTelemetryObserver get _telemetryObserver => _telemetryObserverField!;
  InkPalLogBuffer get _logBuffer => _logBufferField!;
  PerformanceMonitor get _perfMonitor => _perfMonitorField!;
  TouchVisualizerController get _touchVisualizer => _touchVisualizerField!;
  StateJournal get _stateJournal => _stateJournalField!;
  InteractionRecorder get _recorder => _recorderField!;
  ErrorSubscriber get _errorSubscriber => _errorSubscriberField!;
  final GlobalKey _repaintBoundaryKey = GlobalKey();

  /// Whether the app's widget tree has rendered at least one frame.
  /// In-app features (inspection, interaction, screenshot) require this.
  bool _appReady = false;

  /// Completes when license validation finishes (success or failure).
  /// Callers that need license-gated features can await this.
  final Completer<void> _licenseCompleter = Completer<void>();

  /// Resolves when license validation finishes. Times out after 5s.
  /// Safe to call multiple times — returns immediately if already resolved.
  static Future<void> get licenseReady =>
      _instance?._licenseCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      ) ??
      Future<void>.value();

  /// Whether the Flutter app is ready for in-app features.
  bool get isAppReady => _appReady;

  /// The navigator observer — users add this to MaterialApp.navigatorObservers.
  InkPalNavigatorObserver get navigatorObserver => _navObserver;

  /// The RepaintBoundary key — wrap your root widget for screenshot support.
  GlobalKey get repaintBoundaryKey => _repaintBoundaryKey;

  /// The logger instance used by the bridge.
  InkPalLogger get logger => _logger;

  /// The touch visualizer controller — connect to [TouchVisualizerOverlay].
  TouchVisualizerController get touchVisualizer => _touchVisualizer;

  /// The state journal for time-travel debugging.
  StateJournal get stateJournal => _stateJournal;

  /// The interaction recorder for flow recording + test generation.
  InteractionRecorder get recorder => _recorder;

  /// The error subscriber for real-time enriched error streaming.
  ErrorSubscriber get errorSubscriber => _errorSubscriber;

  /// Initialize the InkPal Bridge.
  ///
  /// In release mode, just calls appRunner() with zero overhead.
  ///
  /// ## Channels
  ///
  /// **WebSocket** (primary — the moat) — bidirectional real-time channel.
  /// Commands flow IN from the MCP server; telemetry flows OUT to server.
  /// This is what makes InkPal unique: live control + error streaming.
  ///
  /// **VM Service Extensions** (fallback) — registered for local dev.
  /// `ext.flutter.inkpal.*` extensions work when WebSocket isn't available.
  /// Useful for direct VM Service access from DevTools or local tooling.
  ///
  /// ## Screenshot
  ///
  /// Screenshots are **on-demand only** — captured when `take_screenshot`
  /// command or `ext.flutter.inkpal.screenshot` VM extension is called.
  /// Never auto-captures. Never polls. Zero overhead until requested.
  ///
  /// ## Navigator Setup
  ///
  /// **Standard Navigator / Navigator 2.0:**
  /// ```dart
  /// MaterialApp(
  ///   navigatorObservers: [
  ///     if (InkPalBridge.instance != null)
  ///       InkPalBridge.instance!.navigatorObserver,
  ///   ],
  /// )
  /// ```
  ///
  /// **GetX (Get.toNamed):**
  /// ```dart
  /// InkPalBridge.init(
  ///   navigatorKey: Get.key,
  ///   onNavigateToRoute: (route) async => Get.toNamed(route),
  ///   appRunner: () => runApp(const MyApp()),
  /// );
  /// ```
  ///
  /// **go_router:**
  /// ```dart
  /// InkPalBridge.init(
  ///   onNavigateToRoute: (route) async => router.go(route),
  ///   appRunner: () => runApp(const MyApp()),
  /// );
  /// ```
  static void init({
    required String serverUrl,
    required void Function() appRunner,
    String? licenseKey,
    String? apiUrl,
    GlobalKey<NavigatorState>? navigatorKey,
    InkPalNavigatorObserver? navigatorObserver,
    List<String> knownRoutes = const [],
    Map<String, String> routeDescriptions = const {},
    AiAppManifest? manifest,
    Future<Map<String, dynamic>> Function()? globalStateProvider,
    int screenshotWidth = 720,
    Future<void> Function(String routeName)? onNavigateToRoute,
    InkPalErrorCatcher? errorCatcher,
    InkPalHttpMonitor? httpMonitor,
    InkPalWalkerHooks? walkerHooks,
  }) {
    // Optional error catcher + http monitor — threaded through for VM
    // extensions / telemetry observers to access. Backward compatible:
    // both default to null.
    _injectedErrorCatcher = errorCatcher;
    _injectedHttpMonitor = httpMonitor;
    if (!kDebugMode) {
      appRunner();
      return;
    }

    WidgetsFlutterBinding.ensureInitialized();

    if (_instance != null) {
      debugPrint('[InkPal] Warning: init() called twice — disposing previous instance');
      _instance!.dispose();
    }

    if (_disposed) {
      debugPrint('[InkPal] Warning: init() called after dispose — resetting');
      _disposed = false;
    }

    final bridge = InkPalBridge._();
    _instance = bridge;

    // 1. Logger (our own — zero third-party deps)
    bridge._loggerField = InkPalLogger();

    // 2. License validation (async — features unlock after server responds)
    // License validation runs asynchronously — features may be temporarily
    // restricted until validation completes. This is by design: the app
    // starts immediately with free-tier features, then upgrades once validated.
    if (licenseKey != null && licenseKey.isNotEmpty) {
      final validationUrl = apiUrl ?? InkPalBridge.defaultApiUrl;

      // Wire the per-session upgrade banner: when the server reports a
      // strictly-higher tier than what we saw at session start, log a
      // loud console banner AND broadcast a `tier_upgraded` event over
      // the WebSocket so connected MCP clients can prompt a session
      // restart in the IDE.
      InkPalLicense.instance.onTierUpgrade = (from, to) {
        // Hard restart is required when bridge-only feature wiring (VM
        // extensions registered at init) needs to change. Tier upgrades
        // that only unlock already-registered tools (the common case)
        // can be applied via a soft refresh — the MCP host re-fetches
        // tools/list and the new tier's gate immediately allows them.
        // All current InkPal VM extensions register at init regardless of
        // tier (the FeatureGate runs at command time, not registration
        // time), so every tier upgrade we ship today is soft-refreshable.
        // Reserve `false` for future bridge versions that introduce new
        // VM extensions only registered for higher tiers.
        bool isSoftRefreshable(InkPalTier f, InkPalTier t) => true;
        final softRefreshable = isSoftRefreshable(from, to);
        final msg = softRefreshable
            ? '⚡ InkPal: plan upgraded ${from.name} → ${to.name}. New tools unlocked — your IDE will refresh capabilities automatically.'
            : '⚡ InkPal: plan upgraded ${from.name} → ${to.name}. Restart your `flutter run` and re-open the IDE session to unlock the new tools.';
        debugPrint('================================================');
        debugPrint(msg);
        debugPrint('================================================');
        bridge._logger.warning(msg);
        try {
          if (bridge._wsField != null && bridge._ws.isConnected) {
            bridge._ws.send({
              'type': 'tier_upgraded',
              'from': from.name,
              'to': to.name,
              'restart_required': !softRefreshable,
              'capabilities_updated': true,
              'message': msg,
            });
          }
        } catch (_) {/* WS may not be up yet — banner already logged */}
      };

      InkPalLicense.instance
          .validate(apiUrl: validationUrl, licenseKey: licenseKey)
          .then((ok) {
        if (ok) {
          bridge._logger.log('License validated: ${InkPalLicense.instance.tier.name}');
        } else {
          bridge._logger.warning('License validation failed — running in free tier');
        }
        if (!bridge._licenseCompleter.isCompleted) {
          bridge._licenseCompleter.complete();
        }
      }).catchError((Object error) {
        bridge._logger.warning('License validation error: $error');
        if (!bridge._licenseCompleter.isCompleted) {
          bridge._licenseCompleter.complete();
        }
      });
    } else {
      // No license key — complete immediately (free tier)
      if (!bridge._licenseCompleter.isCompleted) {
        bridge._licenseCompleter.complete();
      }
    }

    // 3. Unhandled async error capture via PlatformDispatcher (zone-free)
    PlatformDispatcher.instance.onError = (error, stack) {
      bridge._logger.handle(error, stack);
      return true;
    };

    // 4. Inspection
    bridge._walkerField = SemanticsWalker(hooks: walkerHooks);
    bridge._walker.ensureSemantics();

    // Prefer the user-provided observer (so MaterialApp.navigatorObservers
    // and the bridge share the same instance and route stack). Fall back to
    // a freshly-constructed one when the caller doesn't supply one — the
    // class uses a static _routeStack so they still share state.
    bridge._navObserverField = navigatorObserver ?? InkPalNavigatorObserver();
    bridge._routeDiscoveryField = RouteDiscovery(
      knownRoutes: knownRoutes,
      routeDescriptions: routeDescriptions,
    );

    bridge._contextCacheField = ContextCache(
      onCaptureScreen: () => bridge._walker.captureScreenContext(),
      onCaptureGlobal: globalStateProvider,
    );

    bridge._contextInvalidatorField = ContextInvalidator(
      cache: bridge._contextCache,
    );
    bridge._contextInvalidator.attach();

    bridge._navObserver.onRouteChanged = (_) {
      bridge._contextCache.invalidateScreen();
    };

    // 5. Touch visualizer (visible AI interaction feedback)
    bridge._touchVisualizerField = TouchVisualizerController();

    // 5b. State Journal (time-travel debugging)
    bridge._stateJournalField = StateJournal();
    bridge._stateJournal.stateProvider = globalStateProvider;
    bridge._stateJournal.routeProvider =
        () => InkPalNavigatorObserver.currentRoute;
    bridge._stateJournal.elementCountProvider =
        () => bridge._walker.captureScreenContext().elements.length;

    // 5c. Interaction Recorder
    bridge._recorderField = InteractionRecorder();
    bridge._recorder.routeProvider =
        () => InkPalNavigatorObserver.currentRoute;
    bridge._recorder.elementCountProvider =
        () => bridge._walker.captureScreenContext().elements.length;

    // 5d. Error Subscriber (enriched runtime error streaming for HEAL domain)
    bridge._errorSubscriberField = ErrorSubscriber(
      logger: bridge._logger,
      walker: bridge._walker,
      journal: bridge._stateJournal,
    );

    // 6. Interaction
    bridge._executorField = ActionExecutor(
      walker: bridge._walker,
      onNavigateToRoute: onNavigateToRoute,
      navigatorKey: navigatorKey,
      navigatorObserver: bridge._navObserver,
      touchVisualizer: bridge._touchVisualizer,
      knownRoutes: knownRoutes,
    );

    // 6. Screenshot (on-demand only — never auto-captures)
    bridge._screenshotField = ScreenshotCapture(
      appContentKey: bridge._repaintBoundaryKey,
      targetWidth: screenshotWidth,
    );

    // 7. Log buffer — in-memory ring buffer for interaction log correlation
    bridge._logBufferField = InkPalLogBuffer(
      getCurrentRoute: () => InkPalNavigatorObserver.currentRoute,
    );
    bridge._logger.addObserver(bridge._logBuffer);

    // 8. VM Service Extensions (ext.flutter.inkpal.*) — FALLBACK
    // For local dev / DevTools. WebSocket is the primary channel.
    InkPalVmExtensions(
      executor: bridge._executor,
      walker: bridge._walker,
      screenshot: bridge._screenshot,
      logBuffer: bridge._logBuffer,
      stateJournal: bridge._stateJournal,
      recorder: bridge._recorder,
    ).register();

    // 9. WebSocket — PRIMARY CHANNEL (the moat)
    // Bidirectional: commands IN from MCP server, telemetry OUT to server.
    bridge._routerField = CommandRouter()
      ..isAppReady = () => bridge._appReady;
    bridge._wsField = ReconnectingWebSocket(
      url: serverUrl,
      onMessage: bridge._onMessage,
      onConnect: () => debugPrint('[InkPal Bridge] Connected to $serverUrl'),
      onDisconnect: () => debugPrint('[InkPal Bridge] Disconnected'),
    );
    bridge._senderField = TelemetrySender(ws: bridge._ws);
    bridge._telemetryObserverField = InkPalTelemetryObserver(
      sender: bridge._sender,
      getCurrentRoute: () => InkPalNavigatorObserver.currentRoute,
    );
    bridge._logger.addObserver(bridge._telemetryObserver);
    bridge._registerCommands(manifest, globalStateProvider);
    bridge._ws.connect();

    // 10. Performance monitor
    bridge._perfMonitorField = PerformanceMonitor();
    bridge._perfMonitor.start();

    // 11. Hook into FlutterError to capture framework errors
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      bridge._logger.handle(
        details.exception,
        details.stack ?? StackTrace.current,
        details.toStringShort(),
      );
      originalOnError?.call(details);
    };

    // 12. Run the app in the same zone as ensureInitialized (root zone).
    appRunner();

    // 13. Mark app ready after first frame renders — in-app features
    // (inspection, interaction, screenshot) are gated on this flag.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      bridge._appReady = true;
      bridge._logger.log('App ready — first frame rendered, in-app features enabled');
    });
  }

  InkPalBridge._();

  /// Get the singleton instance (only available in debug mode).
  static InkPalBridge? get instance => _instance;

  /// Dispose all resources. Safe to call even if [init] never completed,
  /// or to call multiple times. Each resource is released independently so
  /// a failure in one doesn't leak the rest (e.g. SemanticsHandle).
  void dispose() {
    void guard(void Function() action) {
      try {
        action();
      } catch (e) {
        debugPrint('[InkPal] dispose step failed: $e');
      }
    }

    guard(() => _contextInvalidatorField?.detach());
    guard(() => _perfMonitorField?.dispose());
    guard(() => _errorSubscriberField?.dispose());
    guard(() => _stateJournalField?.dispose());
    guard(() => _recorderField?.dispose());
    guard(() => _touchVisualizerField?.dispose());
    guard(() => _senderField?.dispose());
    guard(() => _wsField?.dispose());
    guard(() => _walkerField?.dispose());
    guard(() => _contextCacheField?.clear());

    _loggerField = null;
    _walkerField = null;
    _executorField = null;
    _screenshotField = null;
    _navObserverField = null;
    _routeDiscoveryField = null;
    _contextCacheField = null;
    _contextInvalidatorField = null;
    _wsField = null;
    _routerField = null;
    _senderField = null;
    _telemetryObserverField = null;
    _logBufferField = null;
    _perfMonitorField = null;
    _touchVisualizerField = null;
    _stateJournalField = null;
    _recorderField = null;
    _errorSubscriberField = null;

    _disposed = true;
    if (identical(_instance, this)) {
      _instance = null;
    }
  }

  /// Command router — exposed for in-process integration tests that need
  /// to invoke registered handlers without spinning up the WS server.
  @visibleForTesting
  CommandRouter get router => _router;

  /// Semantics walker — exposed for in-process unit tests.
  @visibleForTesting
  SemanticsWalker get semanticsWalker => _walker;

  /// Force-set an internal field to a fake for testing. Use sparingly.
  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void debugSetPerfMonitor(PerformanceMonitor monitor) {
    _perfMonitorField = monitor;
  }

  void _onMessage(Map<String, dynamic> message) {
    _router.handle(message).then((response) {
      if (response.containsKey('id') && _ws.isConnected) {
        _ws.send(response);
      }
    });
  }

  void _registerCommands(
    AiAppManifest? manifest,
    Future<Map<String, dynamic>> Function()? globalStateProvider,
  ) {
    final router = _router;

    // Note: The following commands are registered for future MCP handler integration:
    // - decrease_value, increase_value: Advanced interaction (planned)
    // - get_app_map, get_app_state: Deep diagnostics (planned)
    // - get_performance: Profiling bridge (planned)
    // - get_screen_manifest: Screen inventory (planned)
    // - go_back: Navigation — registered and wired
    // - heal_get_error_context, heal_get_errors, heal_verify_no_error: Self-healing pipeline (planned)
    // - long_press, tap_with_context: Advanced gestures (planned)

    // === INSPECTION COMMANDS (free tier) ===

    router.register('get_screen_content', (params) async {
      final gate = FeatureGate.check(InkPalFeature.inspection);
      if (!gate.allowed) return gate.denied();
      final context = await _walker.captureScreenContextAsync();
      return {
        'success': true,
        'content': context.toPromptString(),
        'elementCount': context.elements.length,
      };
    });

    router.register('get_widget_tree', (params) async {
      final gate = FeatureGate.check(InkPalFeature.inspection);
      if (!gate.allowed) return gate.denied();
      final context = await _walker.captureScreenContextAsync();
      return {
        'success': true,
        'elements': context.elements.map((e) => e.toJson()).toList(),
      };
    });

    router.register('find_widget', (params) async {
      final gate = FeatureGate.check(InkPalFeature.inspection);
      if (!gate.allowed) return gate.denied();
      final query = params['query'] as String? ?? '';
      final context = await _walker.captureScreenContextAsync();
      final matches = context.findByLabel(query);
      return {
        'success': true,
        'matches': matches.map((e) => e.toJson()).toList(),
      };
    });

    router.register('get_current_route', (params) async {
      final gate = FeatureGate.check(InkPalFeature.navigation);
      if (!gate.allowed) return gate.denied();
      return {
        'success': true,
        'currentRoute': InkPalNavigatorObserver.currentRoute,
        'navigationStack': InkPalNavigatorObserver.routeStack,
        'availableRoutes': _routeDiscovery
            .getAvailableRoutes()
            .map((r) => {'name': r.name, 'description': r.description})
            .toList(),
      };
    });

    router.register('get_routes', (params) async {
      final gate = FeatureGate.check(InkPalFeature.navigation);
      if (!gate.allowed) return gate.denied();

      final routes = <Map<String, dynamic>>[];

      // Source 1: Routes observed via navigator observer (visited routes)
      for (final route in InkPalNavigatorObserver.routeStack) {
        routes.add({'name': route, 'source': 'navigator_stack'});
      }

      // Source 2: All discovered routes (visited + developer-provided knownRoutes)
      for (final route in _routeDiscovery.getAvailableRoutes()) {
        if (!routes.any((r) => r['name'] == route.name)) {
          routes.add({
            'name': route.name,
            'description': route.description,
            'source': 'route_discovery',
          });
        }
      }

      return {
        'success': true,
        'routes': routes,
        'routeCount': routes.length,
        'hint':
            'For GetX apps, also check GetPage definitions in lib/ files.',
      };
    });

    router.register('get_app_state', (params) async {
      final gate = FeatureGate.check(InkPalFeature.navigation);
      if (!gate.allowed) return gate.denied();
      final screenContext = _walker.captureScreenContext();
      final globalState =
          globalStateProvider != null ? await globalStateProvider() : null;
      final buffer = StringBuffer();

      buffer.writeln(
        'CURRENT SCREEN: ${InkPalNavigatorObserver.currentRoute ?? "unknown"}',
      );
      buffer.writeln(
        'NAVIGATION STACK: [${InkPalNavigatorObserver.routeStack.join(' -> ')}]',
      );
      buffer.writeln();
      buffer.writeln("WHAT'S ON SCREEN:");
      buffer.writeln(screenContext.toPromptString());

      if (manifest != null) {
        final currentRoute = InkPalNavigatorObserver.currentRoute;
        if (currentRoute != null) {
          final detail = manifest.toScreenDetailPrompt(currentRoute);
          if (detail != null) {
            buffer.writeln();
            buffer.writeln(detail);
          }
        }
      }

      final routes = _routeDiscovery.getAvailableRoutes();
      if (routes.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('ALL APP SCREENS:');
        for (final route in routes) {
          if (route.description != null) {
            buffer.writeln('- ${route.name}: ${route.description}');
          } else {
            buffer.writeln('- ${route.name}');
          }
        }
      }

      if (globalState != null && globalState.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('APP STATE:');
        for (final entry in globalState.entries) {
          buffer.writeln('- ${entry.key}: ${entry.value}');
        }
      }

      return {'success': true, 'appState': buffer.toString()};
    });

    // === LAYOUT DIFF COMMANDS (pro tier) ===

    // Stores the last screen context for diffing
    ScreenContext? lastScreenCapture;

    router.register('screen_snapshot', (params) async {
      final gate = FeatureGate.check(InkPalFeature.inspection);
      if (!gate.allowed) return gate.denied();
      lastScreenCapture = _walker.captureScreenContext();
      return {
        'success': true,
        'elementCount': lastScreenCapture!.elements.length,
        'hint': 'Snapshot saved. Perform an action, then call screen_diff to see changes.',
      };
    });

    router.register('screen_diff', (params) async {
      final gate = FeatureGate.check(InkPalFeature.inspection);
      if (!gate.allowed) return gate.denied();
      if (lastScreenCapture == null) {
        return {
          'success': false,
          'error': 'No snapshot saved. Call screen_snapshot first.',
        };
      }
      final current = _walker.captureScreenContext();
      final result = LayoutDiffer.diff(lastScreenCapture!, current);
      return {
        'success': true,
        'diff': result,
        'summary': LayoutDiffer.summarize(result),
      };
    });

    // === INTERACTION COMMANDS (pro tier) ===

    router.register('tap_element', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final label = params['label'] as String;
      final parentContext = params['parentContext'] as String?;
      final result = await _executor.tapElement(label, parentContext: parentContext);
      _stateJournal.capture('tap:$label');
      _recorder.record(type: 'tap', label: label, success: result['success'] == true);
      return result;
    });

    router.register('set_text', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final label = params['label'] as String;
      final text = params['text'] as String;
      final parentContext = params['parentContext'] as String?;
      final result = await _executor.setText(label, text, parentContext: parentContext);
      _recorder.record(type: 'setText', label: label, params: {'text': text}, success: result['success'] == true);
      return result;
    });

    router.register('scroll', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final direction = params['direction'] as String;
      final result = await _executor.scroll(direction);
      _stateJournal.capture('scroll:$direction');
      _recorder.record(type: 'scroll', params: {'direction': direction}, success: result['success'] == true);
      return result;
    });

    router.register('navigate_to_route', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final routeName = params['routeName'] as String;
      final result = await _executor.navigateToRoute(routeName);
      _stateJournal.capture('route:$routeName');
      _recorder.record(type: 'navigate', label: routeName, params: {'routeName': routeName}, success: result['success'] == true);
      return result;
    });

    router.register('go_back', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      if (InkPalNavigatorObserver.routeStack.length <= 1) {
        return {'success': false, 'error': 'Cannot go back — already at the root screen.'};
      }
      return await _executor.goBack();
    });

    router.register('long_press', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final label = params['label'] as String;
      final parentContext = params['parentContext'] as String?;
      return await _executor.longPress(label, parentContext: parentContext);
    });

    router.register('increase_value', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final label = params['label'] as String;
      return await _executor.increaseValue(label);
    });

    router.register('decrease_value', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final label = params['label'] as String;
      return await _executor.decreaseValue(label);
    });

    // === SCREENSHOT (pro tier, on-demand only) ===

    router.register('take_screenshot', (params) async {
      final gate = FeatureGate.check(InkPalFeature.screenshot);
      if (!gate.allowed) return gate.denied();
      // Use the diagnostic API so the WS caller learns the *actual* failure
      // cause instead of the legacy opaque string — see B1 in v1.3.1.
      final result = await _screenshot.captureWithDiagnostics();
      final bytes = result.bytes;
      if (bytes == null) {
        return {
          'success': false,
          'error': result.error ?? 'Screenshot capture failed',
        };
      }
      final b64 = base64Encode(bytes);
      return {
        'success': true,
        'screenshot': b64,
        'format': 'png',
        'bytes': bytes.length,
      };
    });

    // === TELEMETRY COMMANDS (pro tier) ===

    router.register('get_log_history', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final lastN = params['last_n'] as int? ?? 50;
      final levelFilter = params['level'] as String?;
      Iterable<InkPalLogEvent> logs = _logger.history;
      if (levelFilter != null && levelFilter.isNotEmpty) {
        logs = logs.where((data) => data.level.label == levelFilter);
      }
      final history = logs
          .take(lastN)
          .map((data) => {
                'type': data is InkPalError
                    ? 'error'
                    : data is InkPalException
                        ? 'exception'
                        : 'log',
                'level': data.level.label,
                'message': data.message,
                'key': data.key,
                'timestamp': data.time.toIso8601String(),
              })
          .toList();
      return {'success': true, 'logs': history, 'count': history.length};
    });

    router.register('get_error_history', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final errors = _logger.history
          .where((d) => d is InkPalError || d is InkPalException)
          .map((data) {
        final map = <String, dynamic>{
          'message': data.message,
          'timestamp': data.time.toIso8601String(),
        };
        if (data is InkPalError) {
          map['error'] = data.error.toString();
          map['stackTrace'] = data.stackTrace?.toString();
        } else if (data is InkPalException) {
          map['exception'] = data.exception.toString();
          map['stackTrace'] = data.stackTrace?.toString();
        }
        return map;
      }).toList();
      return {'success': true, 'errors': errors, 'count': errors.length};
    });

    // === PERFORMANCE (pro tier) ===

    router.register('get_performance', (params) async {
      final gate = FeatureGate.check(InkPalFeature.performance);
      if (!gate.allowed) return gate.denied();
      return {'success': true, 'metrics': _perfMonitor.getMetrics()};
    });

    // === MANIFEST COMMANDS (pro tier) ===

    if (manifest != null) {
      router.register('get_app_map', (params) async {
        final gate = FeatureGate.check(InkPalFeature.manifest);
        if (!gate.allowed) return gate.denied();
        return {'success': true, 'appMap': manifest.toAppMapPrompt()};
      });

      router.register('get_screen_manifest', (params) async {
        final gate = FeatureGate.check(InkPalFeature.manifest);
        if (!gate.allowed) return gate.denied();
        final route = params['route'] as String;
        final detail = manifest.toScreenDetailPrompt(route);
        if (detail == null) {
          return {
            'success': false,
            'error': "No manifest found for route '$route'",
          };
        }
        return {'success': true, 'detail': detail};
      });
    }

    // === LOG CORRELATION COMMANDS (pro tier) ===

    router.register('get_recent_logs', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final sinceMs = params['since_ms'] as int? ?? 0;
      final events = _logBuffer.eventsSince(sinceMs);
      return {
        'success': true,
        'count': events.length,
        'events': events,
        'current_route': InkPalNavigatorObserver.currentRoute,
        'now_ms': DateTime.now().millisecondsSinceEpoch,
      };
    });

    router.register('tap_with_context', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final label = params['label'] as String;
      final parentContext = params['parentContext'] as String?;
      final sinceMs = params['since_ms'] as int? ?? 0;

      final routeBefore = InkPalNavigatorObserver.currentRoute;
      final tapResult = await _executor.tapElement(label, parentContext: parentContext);

      await Future.delayed(const Duration(milliseconds: 500));

      final routeAfter = InkPalNavigatorObserver.currentRoute;
      final logs = _logBuffer.eventsSince(sinceMs);
      final errors = logs
          .where((e) => e['type'] == 'error' || e['type'] == 'exception')
          .toList();

      return {
        ...tapResult,
        'context': {
          'route_before': routeBefore,
          'route_after': routeAfter,
          'navigated': routeBefore != routeAfter,
          'errors': errors,
          'logs': logs,
          'log_count': logs.length,
          'now_ms': DateTime.now().millisecondsSinceEpoch,
        },
      };
    });

    // === LIFECYCLE COMMANDS (always available) ===

    router.register('ping', (params) async {
      return {
        'success': true,
        'bridge': 'inkpal_bridge',
        'version': '1.0.0',
        'platform': defaultTargetPlatform.name,
        'appReady': _appReady,
        'currentRoute': InkPalNavigatorObserver.currentRoute,
        'connected': _ws.isConnected,
        'license': {
          'tier': InkPalLicense.instance.tier.name,
          'validated': InkPalLicense.instance.isValidated,
          'features': InkPalLicense.instance.tier.features
              .map((f) => f.name)
              .toList(),
        },
      };
    });

    // === STATE TIME-TRAVEL COMMANDS (pro tier) ===

    router.register('stream_state', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();

      final duration = params['duration_ms'] as int? ?? 10000;
      final maxEvents = params['max_events'] as int? ?? 50;

      final changes = <Map<String, dynamic>>[];
      final completer = Completer<List<Map<String, dynamic>>>();

      // Get current state snapshot first
      final currentState = _stateJournal.latest;

      Timer(Duration(milliseconds: duration), () {
        if (!completer.isCompleted) {
          completer.complete(changes);
        }
      });

      // Listen to state journal for new snapshots during window
      StreamSubscription<dynamic>? sub;
      sub = _stateJournal.onSnapshot.listen((snapshot) {
        changes.add({
          'timestamp': snapshot.timestamp,
          'trigger': snapshot.trigger,
          'route': snapshot.route,
          'state_keys': snapshot.state.keys.toList(),
          'element_count': snapshot.elementCount,
        });
        if (changes.length >= maxEvents) {
          sub?.cancel();
          if (!completer.isCompleted) completer.complete(changes);
        }
      });

      final results = await completer.future;
      sub.cancel();

      return {
        'success': true,
        'duration_ms': duration,
        'events_captured': results.length,
        'changes': results,
        'current_state_keys': currentState?.state.keys.toList() ?? [],
      };
    });

    router.register('state_capture', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final trigger = params['trigger'] as String? ?? 'manual';
      final snapshot = await _stateJournal.capture(trigger);
      if (snapshot == null) {
        return {
          'success': false,
          'error': 'No globalStateProvider configured — pass one to InkPalBridge.init()',
        };
      }
      return {'success': true, 'snapshot': snapshot.toJson()};
    });

    router.register('state_list', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final last = params['last'] as int?;
      return {
        'success': true,
        'count': _stateJournal.length,
        'snapshots': _stateJournal.listSnapshots(last: last),
      };
    });

    router.register('state_get', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final id = params['id'] as int;
      final snapshot = _stateJournal.get(id);
      if (snapshot == null) {
        return {'success': false, 'error': 'Snapshot $id not found'};
      }
      return {'success': true, 'snapshot': snapshot.toJson()};
    });

    router.register('state_diff', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final fromId = params['from'] as int;
      final toId = params['to'] as int;
      final result = _stateJournal.diff(fromId, toId);
      if (result == null) {
        return {'success': false, 'error': 'One or both snapshot IDs not found'};
      }
      return {
        'success': true,
        'diff': result,
        'summary': _stateJournal.diffSummary(fromId, toId),
      };
    });

    // === INTERACTION RECORDING COMMANDS (pro tier) ===

    router.register('recording_start', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final name = params['name'] as String?;
      return _recorder.start(name: name);
    });

    router.register('recording_stop', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      return _recorder.stop();
    });

    router.register('recording_status', (params) async {
      return {
        'success': true,
        'recording': _recorder.isRecording,
        'session': _recorder.sessionName,
        'actionCount': _recorder.actions.length,
      };
    });

    router.register('recording_export', (params) async {
      final gate = FeatureGate.check(InkPalFeature.interaction);
      if (!gate.allowed) return gate.denied();
      final format = params['format'] as String? ?? 'json';
      if (format == 'test') {
        return {
          'success': true,
          'format': 'integration_test',
          'code': _recorder.toIntegrationTest(),
        };
      }
      return {
        'success': true,
        'format': 'json',
        'recording': _recorder.toJson(),
      };
    });

    // === HEAL COMMANDS (error watching + verification) ===

    router.register('heal_watch_start', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      _errorSubscriber.startWatching();
      return {'success': true, 'watching': true};
    });

    router.register('heal_watch_stop', (params) async {
      _errorSubscriber.stopWatching();
      return {'success': true, 'watching': false};
    });

    router.register('heal_get_errors', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final sinceMs = params['since_ms'] as int? ?? 0;
      final pattern = params['pattern'] as String?;
      final errors = pattern != null
          ? _errorSubscriber.errorsSince(pattern, sinceMs)
          : _errorSubscriber.recentErrors;
      return {
        'success': true,
        'count': errors.length,
        'errors': errors.map((e) => e.toJson()).toList(),
        'watching': _errorSubscriber.isWatching,
      };
    });

    router.register('heal_verify_no_error', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      final pattern = params['pattern'] as String;
      final sinceMs = params['since_ms'] as int;
      // Wait a moment to let any errors propagate
      await Future.delayed(const Duration(milliseconds: 500));
      final hasError = _errorSubscriber.hasErrorSince(pattern, sinceMs);
      return {
        'success': true,
        'errorCleared': !hasError,
        'pattern': pattern,
        'checkedSinceMs': sinceMs,
      };
    });

    router.register('heal_get_error_context', (params) async {
      final gate = FeatureGate.check(InkPalFeature.telemetry);
      if (!gate.allowed) return gate.denied();
      // Return the most recent enriched error with full context
      final errors = _errorSubscriber.recentErrors;
      if (errors.isEmpty) {
        return {'success': false, 'error': 'No recent errors captured'};
      }
      final latest = errors.last;
      return {'success': true, 'enrichedError': latest.toJson()};
    });

    // === VISUAL FEEDBACK COMMANDS (always available) ===

    router.register('set_touch_feedback', (params) async {
      final enabled = params['enabled'] as bool? ?? true;
      _touchVisualizer.enabled = enabled;
      return {'success': true, 'touchFeedback': enabled};
    });

    router.register('disconnect', (params) async {
      dispose();
      return {'success': true, 'disconnected': true};
    });
  }
}
