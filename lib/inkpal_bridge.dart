/// InkPal Bridge — in-app intelligence for AI-powered Flutter development.
///
/// Add to your app:
/// ```dart
/// import 'package:inkpal_bridge/inkpal_bridge.dart';
///
/// void main() {
///   InkPalBridge.init(
///     serverUrl: 'ws://localhost:8765',
///     appRunner: () => runApp(const MyApp()),
///     licenseKey: 'ink_your_key_here',
///   );
/// }
/// ```
library;

export 'src/bridge/inkpal_bridge.dart';
export 'src/bridge/inkpal_config.dart';
export 'src/bridge/app_extensions.dart'
    show InkPalAppExtensions, InkPalAppExtensionHandler;
export 'src/bridge/inkpal_run_app.dart'
    show inkpalRunApp, inkpalRootRepaintKey;
export 'src/telemetry/error_catcher.dart'
    show InkPalErrorCatcher, InkPalCaughtError;
export 'src/telemetry/prompt_generator.dart' show generateInkPalBugReport;
export 'src/network/http_monitor.dart'
    show InkPalHttpMonitor, HttpRequestRecord;
export 'src/ui/error_boundary.dart' show InkPalErrorBoundary;
export 'src/bridge/inkpal_navigator.dart'
    show inkpalNavigatorKey, inkpalNavigatorObserver;
export 'src/inspection/navigator_observer.dart';
export 'src/inspection/ui_element.dart' show UiElement, UiElementType;
export 'src/inspection/screen_context.dart' show ScreenContext;
export 'src/inspection/semantics_walker.dart' show SemanticsWalker;
export 'src/inspection/walker_hooks.dart'
    show InkPalWalkerHooks, InteractiveWidgetPredicate, StopTraversalPredicate, WidgetTextExtractor;
export 'src/communication/command_router.dart' show CommandRouter;
export 'src/license/feature_tier.dart' show InkPalFeature, InkPalTier;
export 'src/license/license_validator.dart' show InkPalLicense;
export 'src/logger/inkpal_logger.dart' show InkPalLogger;
export 'src/logger/log_event.dart'
    show InkPalLogEvent, InkPalLog, InkPalError, InkPalException, InkPalLogLevel;
export 'src/logger/log_observer.dart' show InkPalLogObserver;
export 'src/manifest/manifest.dart';
export 'src/interaction/touch_visualizer.dart'
    show TouchVisualizerController, TouchVisualizerOverlay;
export 'src/memory/state_journal.dart' show StateJournal;
export 'src/memory/state_snapshot.dart' show StateSnapshot;
export 'src/memory/state_differ.dart' show StateDiffer;
export 'src/testing/interaction_recorder.dart' show InteractionRecorder;
export 'src/testing/recorded_action.dart' show RecordedAction;
export 'src/inspection/layout_differ.dart' show LayoutDiffer;
export 'src/telemetry/error_subscriber.dart' show ErrorSubscriber, EnrichedError;
export 'src/network/network_interceptor.dart' show InkPalNetworkInterceptor, MockRule;
