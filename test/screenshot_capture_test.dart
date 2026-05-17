import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart' show inkpalRootRepaintKey;
import 'package:inkpal_bridge/src/inspection/screenshot_capture.dart';

void main() {
  // Tests that exercise actual image encoding (testWidgets + capture()) hang in
  // plain `flutter test` because `ui.Image.toByteData()` does not complete in
  // the Flutter test image pipeline. They are verified end-to-end via
  // `test_app/integration_test/` on a real device. Pure-logic tests (no
  // encoding) stay enabled.
  group('ScreenshotCapture', () {
    test('returns null when key has no context', () async {
      final key = GlobalKey();
      final capture = ScreenshotCapture(appContentKey: key);

      final result = await capture.capture();
      expect(result, isNull);
    });

    test('respects custom targetWidth', () {
      final key = GlobalKey();
      final capture = ScreenshotCapture(appContentKey: key, targetWidth: 360);
      expect(capture.targetWidth, 360);
    });

    test('default targetWidth is 720', () {
      final key = GlobalKey();
      final capture = ScreenshotCapture(appContentKey: key);
      expect(capture.targetWidth, 720);
    });

    testWidgets('returns null when widget is not RepaintBoundary',
        skip: true,
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        SizedBox(key: key, width: 100, height: 100),
      );

      final capture = ScreenshotCapture(appContentKey: key);
      final result = await capture.capture();
      expect(result, isNull);
    });

    testWidgets('captures PNG bytes from RepaintBoundary',
        skip: true, (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: const SizedBox(width: 100, height: 100),
        ),
      );

      final capture = ScreenshotCapture(appContentKey: key, targetWidth: 50);
      final result = await capture.capture();

      // In test environment, toImage may or may not work depending on
      // the test runner. If it works, we get bytes; if not, null.
      // Either way, it should not throw.
      if (result != null) {
        expect(result.length, greaterThan(0));
      }
    });

    // Skipped: image encoding hangs in plain `flutter test` (10+ min).
    // Verified end-to-end via `test_app` integration_test on a real device.
    testWidgets(
        'falls back to inkpalRootRepaintKey when configured key is missing',
        skip: true,
        (tester) async {
      // App configured with one key, but the actual RepaintBoundary lives
      // under [inkpalRootRepaintKey] — exactly what `inkpalRunApp` installs.
      final unrelatedKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: inkpalRootRepaintKey,
          child: const SizedBox(width: 100, height: 100),
        ),
      );

      final capture = ScreenshotCapture(
        appContentKey: unrelatedKey,
        targetWidth: 50,
      );
      final result = await capture.captureWithDiagnostics();

      // Either we got bytes via the fallback, or — depending on the test
      // runner's image pipeline — we get a structured error string. Either
      // way, the legacy opaque "Screenshot capture failed" must not appear.
      if (result.bytes == null) {
        expect(result.error, isNotNull);
        expect(result.error, isNot('Screenshot capture failed'));
      } else {
        expect(result.bytes!.length, greaterThan(0));
      }
    });

    testWidgets('reports a structured error when no boundary exists at all',
        skip: true, (tester) async {
      // Pump a widget tree with no RepaintBoundary at any of the keys we
      // consult. The result should explain *why* capture failed instead of
      // returning the legacy "Screenshot capture failed" string.
      await tester.pumpWidget(
        const SizedBox(width: 100, height: 100),
      );

      final capture = ScreenshotCapture(appContentKey: GlobalKey());
      final result = await capture.captureWithDiagnostics();

      expect(result.bytes, isNull);
      expect(result.error, isNotNull);
      expect(result.error, contains('RenderRepaintBoundary'));
    });
  });
}
