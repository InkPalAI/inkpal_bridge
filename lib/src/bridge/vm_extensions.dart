import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../_version.dart';
import 'app_extensions.dart';
import '../interaction/action_executor.dart';
import '../inspection/semantics_walker.dart';
import '../inspection/screenshot_capture.dart';
import '../inspection/navigator_observer.dart';
import '../inspection/architecture_graph.dart';
import 'inkpal_navigator.dart';
import '../memory/state_journal.dart';
import '../network/network_interceptor_ref.dart';
import '../telemetry/log_buffer.dart';
import '../testing/interaction_recorder.dart';

/// Registers Dart VM Service Extensions under the `ext.flutter.inkpal.*`
/// namespace so InkPal's MCP server can call them directly via VM Service
/// protocol — no ADB, no WebSocket, no external bridge process needed.
///
/// The MCP server calls e.g.:
///   vmService.callServiceExtension('ext.flutter.inkpal.tap', args: {'label': 'Submit'})
///
/// This is the same approach used by Flutter's own devtools extensions and
/// flutter-skill's FlutterSkillBinding.
class InkPalVmExtensions {
  final ActionExecutor _executor;
  final SemanticsWalker _walker;
  final ScreenshotCapture _screenshot;
  final InkPalLogBuffer? logBuffer;
  final StateJournal? stateJournal;
  final InteractionRecorder? recorder;

  InkPalVmExtensions({
    required ActionExecutor executor,
    required SemanticsWalker walker,
    required ScreenshotCapture screenshot,
    this.logBuffer,
    this.stateJournal,
    this.recorder,
  })  : _executor = executor,
        _walker = walker,
        _screenshot = screenshot;

  /// Register all `ext.flutter.inkpal.*` VM Service extensions.
  ///
  /// Network extensions (mockNetwork, clearNetworkMocks, goOffline, goOnline,
  /// networkConditions) are skipped if already registered by
  /// [InkPalNetworkInterceptor.install()] to avoid "Extension already
  /// registered" crashes when both are used together.
  void register() {
    // Core interaction
    _registerTap();
    _registerLongPress();
    _registerSetText();
    _registerScroll();
    _registerNavigate();
    _registerGoBack();
    _registerIncreaseValue();
    _registerDecreaseValue();
    // v1.14 interaction
    _registerDoubleTap();
    _registerSetCheckbox();
    _registerSetSlider();
    _registerScrollTo();
    // Inspection
    _registerGetScreenContent();
    _registerGetWidgetTree();
    _registerFindWidget();
    _registerScreenshot();
    _registerGetCurrentRoute();
    // Network control — guarded; InkPalNetworkInterceptor may have
    // already registered these extensions before InkPalBridge.init() runs.
    _tryRegister('ext.flutter.inkpal.mockNetwork', _registerMockNetwork);
    _tryRegister('ext.flutter.inkpal.clearNetworkMocks', _registerClearNetworkMocks);
    _tryRegister('ext.flutter.inkpal.goOffline', _registerGoOffline);
    _tryRegister('ext.flutter.inkpal.goOnline', _registerGoOnline);
    _tryRegister('ext.flutter.inkpal.networkConditions', _registerNetworkConditions);
    _registerSetLocale();
    // Log correlation
    _registerGetRecentLogs();
    _registerTapWithContext();
    // State time-travel
    _registerStateStream();
    _registerStateCapture();
    _registerStateList();
    _registerStateDiff();
    // Interaction recording
    _registerRecordingStart();
    _registerRecordingStop();
    _registerRecordingExport();
    // Meta
    _registerPing();
    // App-side extension registry — two meta extensions so apps can register
    // their own VM handlers and have the MCP side list + invoke them without
    // a bridge republish.
    InkPalAppExtensions.installMetaExtensions();
  }

  /// Calls [register] only if the extension name is not already registered.
  /// Swallows "Extension already registered" errors so both
  /// [InkPalNetworkInterceptor] and [InkPalVmExtensions] can coexist.
  void _tryRegister(String name, void Function() register) {
    try {
      register();
    } catch (e) {
      // Ignore duplicate registration — extension already registered by
      // InkPalNetworkInterceptor.install() or another call site.
      if (!e.toString().contains('already registered')) rethrow;
    }
  }

  // ── Interaction ──────────────────────────────────────────────────────────

  void _registerTap() {
    developer.registerExtension('ext.flutter.inkpal.tap', (method, params) async {
      // Coordinate tap: when x + y are passed, dispatch synthetic pointer
      // events through the real gesture pipeline instead of going through
      // Semantics. Works on widgets that never emit a SemanticsAction.tap —
      // raw Listener, custom gesture recognizers, CustomPaint hit regions.
      if (params.containsKey('x') && params.containsKey('y')) {
        final x = double.tryParse(params['x'] ?? '');
        final y = double.tryParse(params['y'] ?? '');
        if (x == null || y == null) {
          return _ok({
            'success': false,
            'error': 'x and y must be numeric when provided',
          });
        }
        final skipHit = params['skipHitCheck'] == 'true';
        final result = await _executor.tapAt(x, y, skipHitCheck: skipHit);
        return _ok(result);
      }
      final label = params['label'] ?? '';
      final parentContext = params['parentContext'];
      final result = await _executor.tapElement(label, parentContext: parentContext);
      return _ok(result);
    });
  }

  void _registerLongPress() {
    developer.registerExtension('ext.flutter.inkpal.longPress', (method, params) async {
      final label = params['label'] ?? '';
      final parentContext = params['parentContext'];
      final result = await _executor.longPress(label, parentContext: parentContext);
      return _ok(result);
    });
  }

  void _registerSetText() {
    developer.registerExtension('ext.flutter.inkpal.setText', (method, params) async {
      final label = params['label'] ?? '';
      final text = params['text'] ?? '';
      final parentContext = params['parentContext'];
      final result = await _executor.setText(label, text, parentContext: parentContext);
      return _ok(result);
    });
  }

  void _registerScroll() {
    developer.registerExtension('ext.flutter.inkpal.scroll', (method, params) async {
      final direction = params['direction'] ?? 'down';
      final result = await _executor.scroll(direction);
      return _ok(result);
    });
  }

  void _registerNavigate() {
    developer.registerExtension('ext.flutter.inkpal.navigate', (method, params) async {
      final routeName = params['routeName'] ?? '';
      final result = await _executor.navigateToRoute(routeName);
      // When using onNavigateToRoute (GetX/go_router), the NavigatorObserver
      // doesn't see the navigation. Manually track it so getCurrentRoute works.
      if (result['success'] == true) {
        InkPalNavigatorObserver.trackExternalNavigation(routeName);
      }
      return _ok(result);
    });
  }

  void _registerGoBack() {
    developer.registerExtension('ext.flutter.inkpal.goBack', (method, params) async {
      // Prefer the global navigator key — works for any push, named or
      // builder-based. Falls back to the executor's tap-the-back-arrow
      // behaviour when the host app didn't wire `inkpalNavigatorKey`.
      final navState = inkpalNavigatorKey.currentState;
      if (navState != null && navState.canPop()) {
        navState.pop();
        return _ok({'success': true, 'method': 'navigatorKey.pop'});
      }
      final result = await _executor.goBack();
      return _ok(result);
    });
  }

  void _registerIncreaseValue() {
    developer.registerExtension('ext.flutter.inkpal.increaseValue', (method, params) async {
      final label = params['label'] ?? '';
      final result = await _executor.increaseValue(label);
      return _ok(result);
    });
  }

  void _registerDecreaseValue() {
    developer.registerExtension('ext.flutter.inkpal.decreaseValue', (method, params) async {
      final label = params['label'] ?? '';
      final result = await _executor.decreaseValue(label);
      return _ok(result);
    });
  }

  // ── Inspection ───────────────────────────────────────────────────────────

  void _registerGetScreenContent() {
    developer.registerExtension('ext.flutter.inkpal.getScreenContent', (method, params) async {
      final ctx = await _walker.captureScreenContextAsync();
      return _ok({
        'success': true,
        'content': ctx.toPromptString(),
        'elementCount': ctx.elements.length,
      });
    });
  }

  void _registerGetWidgetTree() {
    developer.registerExtension('ext.flutter.inkpal.getWidgetTree', (method, params) async {
      final ctx = await _walker.captureScreenContextAsync();
      return _ok({
        'success': true,
        'elements': ctx.elements.map((e) => e.toJson()).toList(),
      });
    });
  }

  void _registerFindWidget() {
    developer.registerExtension('ext.flutter.inkpal.findWidget', (method, params) async {
      final query = params['query'] ?? '';
      final ctx = await _walker.captureScreenContextAsync();
      final matches = ctx.findByLabel(query);
      return _ok({
        'success': true,
        'matches': matches.map((e) => e.toJson()).toList(),
        'count': matches.length,
      });
    });
  }

  void _registerGetCurrentRoute() {
    developer.registerExtension('ext.flutter.inkpal.getCurrentRoute', (method, params) async {
      return _ok({
        'success': true,
        'currentRoute': InkPalNavigatorObserver.currentRoute,
        'navigationStack': InkPalNavigatorObserver.routeStack,
      });
    });
  }

  void _registerScreenshot() {
    developer.registerExtension('ext.flutter.inkpal.screenshot', (method, params) async {
      final result = await _screenshot.captureWithDiagnostics();
      final bytes = result.bytes;
      if (bytes == null) {
        return _ok({
          'success': false,
          // Surface the *actual* failure instead of the legacy opaque
          // "Screenshot capture failed" string — see B1 in v1.3.1 changelog.
          'error': result.error ?? 'Screenshot capture failed',
        });
      }
      return _ok({
        'success': true,
        'screenshot': base64Encode(bytes),
        'format': 'png',
        'bytes': bytes.length,
      });
    });
  }

  // ── Meta ─────────────────────────────────────────────────────────────────

  // ── v1.14 extensions ──────────────────────────────────────────────────────

  void _registerDoubleTap() {
    developer.registerExtension('ext.flutter.inkpal.doubleTap', (method, params) async {
      final label         = params['label'] ?? '';
      final parentContext = params['parentContext'];
      final result = await _executor.doubleTap(label, parentContext: parentContext);
      return _ok(result);
    });
  }

  void _registerSetCheckbox() {
    developer.registerExtension('ext.flutter.inkpal.setCheckbox', (method, params) async {
      final label   = params['label'] ?? '';
      final checked = params['checked'] == 'true';
      final result  = await _executor.setCheckbox(label, checked);
      return _ok(result);
    });
  }

  void _registerSetSlider() {
    developer.registerExtension('ext.flutter.inkpal.setSlider', (method, params) async {
      final label       = params['label'] ?? '';
      final targetValue = double.tryParse(params['value'] ?? '0.5') ?? 0.5;
      final result      = await _executor.setSliderValue(label, targetValue);
      return _ok(result);
    });
  }

  void _registerScrollTo() {
    developer.registerExtension('ext.flutter.inkpal.scrollTo', (method, params) async {
      final label      = params['label'] ?? '';
      final direction  = params['direction'] ?? 'down';
      final maxSwipes  = int.tryParse(params['max_swipes'] ?? '10') ?? 10;
      final result     = await _executor.scrollToFind(label, direction: direction, maxAttempts: maxSwipes);
      return _ok(result);
    });
  }

  // ── Network control stubs (full implementation via InkPalNetworkInterceptor) ──

  void _registerMockNetwork() {
    developer.registerExtension('ext.flutter.inkpal.mockNetwork', (method, params) async {
      // Delegate to InkPalNetworkInterceptor if initialized
      try {
        final interceptor = InkPalNetworkInterceptorRef.instance;
        if (interceptor != null) {
          interceptor.addMockRule(
            urlPattern:   params['url_pattern'] ?? '*',
            responseCode: int.tryParse(params['response_code'] ?? '200') ?? 200,
            responseBody: params['response_body'],
            method:       params['method'] ?? 'ANY',
            delayMs:      int.tryParse(params['delay_ms'] ?? '0') ?? 0,
          );
          return _ok({'success': true, 'rule_added': params['url_pattern']});
        }
      } catch (_) { /* interceptor not initialized */ }
      return _ok({'success': false, 'error': 'InkPalNetworkInterceptor not initialized. Call InkPalNetworkInterceptor.install() in main().'});
    });
  }

  void _registerClearNetworkMocks() {
    developer.registerExtension('ext.flutter.inkpal.clearNetworkMocks', (method, params) async {
      try {
        InkPalNetworkInterceptorRef.instance?.clearRules();
        return _ok({'success': true});
      } catch (_) {
        return _ok({'success': false, 'error': 'InkPalNetworkInterceptor not initialized'});
      }
    });
  }

  void _registerGoOffline() {
    developer.registerExtension('ext.flutter.inkpal.goOffline', (method, params) async {
      try {
        InkPalNetworkInterceptorRef.instance?.setOffline(true);
        return _ok({'success': true, 'message': 'Network blocked in-app'});
      } catch (_) {
        return _ok({'success': false, 'error': 'InkPalNetworkInterceptor not initialized'});
      }
    });
  }

  void _registerGoOnline() {
    developer.registerExtension('ext.flutter.inkpal.goOnline', (method, params) async {
      try {
        InkPalNetworkInterceptorRef.instance?.setOffline(false);
        return _ok({'success': true, 'message': 'Network restored in-app'});
      } catch (_) {
        return _ok({'success': false, 'error': 'InkPalNetworkInterceptor not initialized'});
      }
    });
  }

  void _registerNetworkConditions() {
    developer.registerExtension('ext.flutter.inkpal.networkConditions', (method, params) async {
      try {
        final delayMs     = int.tryParse(params['delay_ms']     ?? '0') ?? 0;
        final lossPercent = int.tryParse(params['loss_percent'] ?? '0') ?? 0;
        InkPalNetworkInterceptorRef.instance?.setConditions(delayMs, lossPercent);
        return _ok({'success': true, 'delay_ms': delayMs, 'loss_percent': lossPercent});
      } catch (_) {
        return _ok({'success': false, 'error': 'InkPalNetworkInterceptor not initialized'});
      }
    });
  }

  void _registerSetLocale() {
    developer.registerExtension('ext.flutter.inkpal.setLocale', (method, params) async {
      // Locale change at runtime requires app-level support (Localizations.override)
      // This stub signals that the app must handle it via onLocaleChange callback
      return _ok({
        'success': false,
        'error': 'Runtime locale change requires app-level Localizations.override support',
        'hint': 'Use ADB: adb shell settings put system system_locales "fr-FR" + hot restart',
      });
    });
  }

  // ── Log correlation ───────────────────────────────────────────────────────

  void _registerGetRecentLogs() {
    developer.registerExtension('ext.flutter.inkpal.getRecentLogs', (method, params) async {
      final buf = logBuffer;
      if (buf == null) {
        return _ok({'success': false, 'error': 'LogBuffer not initialized — pass logBuffer to InkPalVmExtensions'});
      }
      final sinceMs = int.tryParse(params['since_ms'] ?? '0') ?? 0;
      final events = buf.eventsSince(sinceMs);
      return _ok({
        'success': true,
        'count': events.length,
        'events': events,
        'current_route': InkPalNavigatorObserver.currentRoute,
        'now_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  /// Tap an element AND return the log window around the action in one call.
  /// MCP passes `since_ms` = timestamp before the action was initiated —
  /// the response includes all logs captured from that point until 500 ms
  /// after the tap completes, giving full cause-effect context.
  void _registerTapWithContext() {
    developer.registerExtension('ext.flutter.inkpal.tapWithContext', (method, params) async {
      final label         = params['label'] ?? '';
      final parentContext = params['parentContext'];
      final sinceMs       = int.tryParse(params['since_ms'] ?? '0') ?? 0;

      final routeBefore = InkPalNavigatorObserver.currentRoute;
      final tapResult   = await _executor.tapElement(label, parentContext: parentContext);

      // Brief settle window so navigation / state logs flush into the buffer
      await Future.delayed(const Duration(milliseconds: 500));

      final routeAfter = InkPalNavigatorObserver.currentRoute;
      final buf = logBuffer;
      final logs = buf != null ? buf.eventsSince(sinceMs) : <Map<String, dynamic>>[];
      final errors = logs.where((e) => e['type'] == 'error' || e['type'] == 'exception').toList();

      return _ok({
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
      });
    });

    // Architecture graph — runtime introspection of the live app's
    // class/widget/route topology. Returns {nodes, edges, clusters, stats}
    // in the same shape an AI agent or a CodeFlow-style visualizer wants.
    // Bounded by max_nodes (default 2000) to stop a pathological app from
    // OOMing the bridge.
    _tryRegister('ext.flutter.inkpal.getArchitectureGraph',
        () => developer.registerExtension('ext.flutter.inkpal.getArchitectureGraph', (method, params) async {
      final maxNodes = int.tryParse(params['max_nodes'] ?? '') ?? 2000;
      final includeFw = (params['include_framework'] ?? 'true').toLowerCase() == 'true';
      final graph = InkPalArchitectureGraph.capture(
        maxNodes: maxNodes,
        includeFramework: includeFw,
      );
      return _ok(graph);
    }));
  }

  // ── State time-travel ────────────────────────────────────────────────────

  void _registerStateStream() {
    developer.registerExtension('ext.flutter.inkpal.stateStream', (method, params) async {
      final journal = stateJournal;
      if (journal == null) {
        return _ok({'success': false, 'error': 'StateJournal not initialized'});
      }
      final duration = int.tryParse(params['duration_ms'] ?? '10000') ?? 10000;
      final maxEvents = int.tryParse(params['max_events'] ?? '50') ?? 50;

      final changes = <Map<String, dynamic>>[];
      final completer = Completer<List<Map<String, dynamic>>>();

      final currentState = journal.latest;

      Timer(Duration(milliseconds: duration), () {
        if (!completer.isCompleted) {
          completer.complete(changes);
        }
      });

      final sub = journal.onSnapshot.listen((snapshot) {
        changes.add({
          'timestamp': snapshot.timestamp,
          'trigger': snapshot.trigger,
          'route': snapshot.route,
          'state_keys': snapshot.state.keys.toList(),
          'element_count': snapshot.elementCount,
        });
        if (changes.length >= maxEvents) {
          if (!completer.isCompleted) completer.complete(changes);
        }
      });

      final results = await completer.future;
      sub.cancel();

      return _ok({
        'success': true,
        'duration_ms': duration,
        'events_captured': results.length,
        'changes': results,
        'current_state_keys': currentState?.state.keys.toList() ?? [],
      });
    });
  }

  void _registerStateCapture() {
    developer.registerExtension('ext.flutter.inkpal.stateCapture', (method, params) async {
      final journal = stateJournal;
      if (journal == null) {
        return _ok({'success': false, 'error': 'StateJournal not initialized'});
      }
      final trigger = params['trigger'] ?? 'manual';
      final snapshot = await journal.capture(trigger);
      if (snapshot == null) {
        return _ok({'success': false, 'error': 'No globalStateProvider configured'});
      }
      return _ok({'success': true, 'snapshot': snapshot.toJson()});
    });
  }

  void _registerStateList() {
    developer.registerExtension('ext.flutter.inkpal.stateList', (method, params) async {
      final journal = stateJournal;
      if (journal == null) {
        return _ok({'success': false, 'error': 'StateJournal not initialized'});
      }
      final last = int.tryParse(params['last'] ?? '');
      return _ok({
        'success': true,
        'count': journal.length,
        'snapshots': journal.listSnapshots(last: last),
      });
    });
  }

  void _registerStateDiff() {
    developer.registerExtension('ext.flutter.inkpal.stateDiff', (method, params) async {
      final journal = stateJournal;
      if (journal == null) {
        return _ok({'success': false, 'error': 'StateJournal not initialized'});
      }
      final fromId = int.tryParse(params['from'] ?? '');
      final toId = int.tryParse(params['to'] ?? '');
      if (fromId == null || toId == null) {
        return _ok({'success': false, 'error': 'Missing from/to snapshot IDs'});
      }
      final result = journal.diff(fromId, toId);
      if (result == null) {
        return _ok({'success': false, 'error': 'Snapshot not found'});
      }
      return _ok({
        'success': true,
        'diff': result,
        'summary': journal.diffSummary(fromId, toId),
      });
    });
  }

  // ── Interaction recording ──────────────────────────────────────────────────

  void _registerRecordingStart() {
    developer.registerExtension('ext.flutter.inkpal.recordingStart', (method, params) async {
      final rec = recorder;
      if (rec == null) {
        return _ok({'success': false, 'error': 'InteractionRecorder not initialized'});
      }
      final name = params['name'];
      return _ok(rec.start(name: name));
    });
  }

  void _registerRecordingStop() {
    developer.registerExtension('ext.flutter.inkpal.recordingStop', (method, params) async {
      final rec = recorder;
      if (rec == null) {
        return _ok({'success': false, 'error': 'InteractionRecorder not initialized'});
      }
      return _ok(rec.stop());
    });
  }

  void _registerRecordingExport() {
    developer.registerExtension('ext.flutter.inkpal.recordingExport', (method, params) async {
      final rec = recorder;
      if (rec == null) {
        return _ok({'success': false, 'error': 'InteractionRecorder not initialized'});
      }
      final format = params['format'] ?? 'json';
      if (format == 'test') {
        return _ok({'success': true, 'format': 'integration_test', 'code': rec.toIntegrationTest()});
      }
      return _ok({'success': true, 'format': 'json', 'recording': rec.toJson()});
    });
  }

  void _registerPing() {
    developer.registerExtension('ext.flutter.inkpal.ping', (method, params) async {
      return _ok({
        'success': true,
        'bridge': 'inkpal_bridge',
        'version': inkpalBridgeVersion,
        'vmExtensions': true,
        'currentRoute': InkPalNavigatorObserver.currentRoute,
        'extensions': [
          'ext.flutter.inkpal.tap',
          'ext.flutter.inkpal.longPress',
          'ext.flutter.inkpal.setText',
          'ext.flutter.inkpal.scroll',
          'ext.flutter.inkpal.navigate',
          'ext.flutter.inkpal.goBack',
          'ext.flutter.inkpal.increaseValue',
          'ext.flutter.inkpal.decreaseValue',
          'ext.flutter.inkpal.doubleTap',
          'ext.flutter.inkpal.setCheckbox',
          'ext.flutter.inkpal.setSlider',
          'ext.flutter.inkpal.scrollTo',
          'ext.flutter.inkpal.getScreenContent',
          'ext.flutter.inkpal.getWidgetTree',
          'ext.flutter.inkpal.findWidget',
          'ext.flutter.inkpal.getCurrentRoute',
          'ext.flutter.inkpal.screenshot',
          'ext.flutter.inkpal.mockNetwork',
          'ext.flutter.inkpal.clearNetworkMocks',
          'ext.flutter.inkpal.goOffline',
          'ext.flutter.inkpal.goOnline',
          'ext.flutter.inkpal.networkConditions',
          'ext.flutter.inkpal.setLocale',
          'ext.flutter.inkpal.getRecentLogs',
          'ext.flutter.inkpal.tapWithContext',
          'ext.flutter.inkpal.stateStream',
          'ext.flutter.inkpal.stateCapture',
          'ext.flutter.inkpal.stateList',
          'ext.flutter.inkpal.stateDiff',
          'ext.flutter.inkpal.recordingStart',
          'ext.flutter.inkpal.recordingStop',
          'ext.flutter.inkpal.recordingExport',
          'ext.flutter.inkpal.ping',
        ],
      });
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  developer.ServiceExtensionResponse _ok(Map<String, dynamic> data) {
    return developer.ServiceExtensionResponse.result(jsonEncode(data));
  }
}

