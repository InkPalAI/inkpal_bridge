// Lifecycle smoke test: app boot → bridge init → extension surface present
// → app continues to render → tester unmounts cleanly.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'helpers/bridge_test_utils.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureBridgeBooted();
  });

  testWidgets('bridge initialises and reports ready after first frame',
      (tester) async {
    await bootApp(tester);
    final bridge = requireBridge();
    expect(bridge.isAppReady, isTrue,
        reason: 'bridge should mark app ready after first frame');
    await teardownBridge(tester);
  });

  testWidgets(
    'harness widgets render [SKIP: needs flutter drive on device — '
    'finders cannot see the runApp-mounted tree from setUpAll inside '
    'flutter-tester; covered in T3 CI]',
    (tester) async {
      await bootApp(tester);
      expect(findExt('tap_target'), findsOneWidget);
      expect(findExt('text_field'), findsOneWidget);
      expect(findExt('long_press'), findsOneWidget);
      expect(findExt('checkbox'), findsOneWidget);
      expect(findExt('slider'), findsOneWidget);
      expect(findExt('navigate'), findsOneWidget);
      expect(findExt('throw'), findsOneWidget);
      expect(findExt('getScreenContent'), findsOneWidget);
      expect(findExt('icon_marker'), findsOneWidget);
      await teardownBridge(tester);
    },
    skip: true,
  );

  testWidgets(
    'navigation push works (covers ext.navigate-adjacent path) '
    '[SKIP: needs flutter drive — see harness-widgets test above]',
    (tester) async {
      await bootApp(tester);
      await tester.tap(findExt('navigate'));
      await tester.pumpAndSettle();
      expect(find.text('Pushed'), findsOneWidget);
      await teardownBridge(tester);
    },
    skip: true,
  );

  testWidgets(
    'typing into ext_text_field works (covers ext.setText path) '
    '[SKIP: needs flutter drive — see harness-widgets test above]',
    (tester) async {
      await bootApp(tester);
      await tester.enterText(findExt('text_field'), 'hello inkpal');
      await tester.pumpAndSettle();
      expect(find.text('hello inkpal'), findsOneWidget);
      await teardownBridge(tester);
    },
    skip: true,
  );

  testWidgets('bridge logger accepts log + handle calls (errors plumbing)',
      (tester) async {
    await bootApp(tester);
    final bridge = requireBridge();
    // We can't tap ext_throw without the runApp tree being finder-visible
    // (see skip notes above), but we can drive the logger directly to verify
    // the error-handling code path doesn't blow up.
    bridge.logger.log('test log');
    bridge.logger.handle(StateError('synthetic'), StackTrace.current);
    expect(bridge.logger, isNotNull);
    await teardownBridge(tester);
  });
}
