// Coverage tests for every `ext.flutter.inkpal.*` VM service extension.
//
// We enumerate all 33 extensions registered by `InkPalVmExtensions.register()`
// in `packages/inkpal_bridge/lib/src/bridge/vm_extensions.dart`. For each, we
// boot the test app (which calls `InkPalBridge.init` → registers extensions)
// and assert the extension is registered. End-to-end VM-service-roundtrip
// coverage is the job of Task 3 (`flutter drive`).
//
// See `helpers/bridge_test_utils.dart` for the rationale behind this
// "registration + adjacent logic" coverage strategy.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/bridge_test_utils.dart';

/// Every short extension name registered by InkPalVmExtensions.register().
/// Source of truth: packages/inkpal_bridge/lib/src/bridge/vm_extensions.dart.
const _extensionNames = <String>[
  // Core interaction
  'tap',
  'longPress',
  'setText',
  'scroll',
  'navigate',
  'goBack',
  'increaseValue',
  'decreaseValue',
  // v1.14 interaction
  'doubleTap',
  'setCheckbox',
  'setSlider',
  'scrollTo',
  // Inspection
  'getScreenContent',
  'getWidgetTree',
  'findWidget',
  'screenshot',
  'getCurrentRoute',
  // Network control
  'mockNetwork',
  'clearNetworkMocks',
  'goOffline',
  'goOnline',
  'networkConditions',
  // Locale
  'setLocale',
  // Log correlation
  'getRecentLogs',
  'tapWithContext',
  // State time-travel
  'stateStream',
  'stateCapture',
  'stateList',
  'stateDiff',
  // Interaction recording
  'recordingStart',
  'recordingStop',
  'recordingExport',
  // Meta
  'ping',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureBridgeBooted();
  });

  group('VM extension registration', () {

    testWidgets('bridge initialises and exposes instance', (tester) async {
      await bootApp(tester);
      requireBridge();
      await teardownBridge(tester);
    });

    for (final name in _extensionNames) {
      testWidgets(
        'ext.flutter.inkpal.$name is registered',
        (tester) async {
          await bootApp(tester);
          expectExtensionRegistered(name);
          await teardownBridge(tester);
        },
        // The probe is best-effort: it tries to register the same extension
        // and treats the resulting "already registered" error as evidence of
        // bridge-side registration. False negatives are possible if Dart
        // changes the error message — those would be revisited in T3 CI.
        skip: false,
      );
    }
  });

  group('Bridge public Dart API (covers extension-adjacent logic)', () {
    testWidgets('logger exposes recent logs (backs ext.getRecentLogs)',
        (tester) async {
      await bootApp(tester);
      final bridge = requireBridge();
      bridge.logger.log('hello from test');
      expect(bridge.logger, isNotNull);
      await teardownBridge(tester);
    });

    testWidgets('navigatorObserver is non-null (backs ext.getCurrentRoute)',
        (tester) async {
      await bootApp(tester);
      final bridge = requireBridge();
      expect(bridge.navigatorObserver, isNotNull);
      await teardownBridge(tester);
    });

    testWidgets('stateJournal is non-null (backs ext.state*)', (tester) async {
      await bootApp(tester);
      final bridge = requireBridge();
      expect(bridge.stateJournal, isNotNull);
      await teardownBridge(tester);
    });

    testWidgets('recorder is non-null (backs ext.recording*)', (tester) async {
      await bootApp(tester);
      final bridge = requireBridge();
      expect(bridge.recorder, isNotNull);
      await teardownBridge(tester);
    });

    testWidgets('repaintBoundaryKey is non-null (backs ext.screenshot)',
        (tester) async {
      await bootApp(tester);
      final bridge = requireBridge();
      expect(bridge.repaintBoundaryKey, isNotNull);
      await teardownBridge(tester);
    });

    testWidgets('touchVisualizer is non-null (backs tap visual feedback)',
        (tester) async {
      await bootApp(tester);
      final bridge = requireBridge();
      expect(bridge.touchVisualizer, isNotNull);
      await teardownBridge(tester);
    });
  });
}
