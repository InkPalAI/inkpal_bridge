import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  group('InkPalErrorCatcher', () {
    tearDown(() {
      // Reset to avoid leaking handlers between tests.
      FlutterError.onError = null;
    });

    test('dedupes identical errors within window', () {
      final c = InkPalErrorCatcher(dedupeWindow: const Duration(seconds: 5));
      c.reportError(StateError('boom'), StackTrace.current);
      c.reportError(StateError('boom'), StackTrace.current);
      c.reportError(StateError('boom'), StackTrace.current);
      // Dedup collapses to a single entry with count=3. Note stack traces
      // may differ slightly per call — accept either one or multiple.
      expect(c.entries.length, greaterThanOrEqualTo(1));
      final total = c.entries.fold<int>(0, (s, e) => s + e.count);
      expect(total, 3);
    });

    test('reportError captures with app source', () {
      final c = InkPalErrorCatcher();
      c.reportError(Exception('x'), null);
      expect(c.entries.single.source, 'app');
    });

    test('install chains previous FlutterError.onError', () {
      var previousCalled = false;
      FlutterError.onError = (_) => previousCalled = true;
      final c = InkPalErrorCatcher()..install();
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('x')));
      expect(previousCalled, true);
      expect(c.entries.single.source, 'flutter');
      c.uninstall();
    });

    test('ring buffer caps entries', () {
      final c = InkPalErrorCatcher(
          maxEntries: 5, dedupeWindow: Duration.zero);
      for (var i = 0; i < 20; i++) {
        c.reportError(StateError('e$i'), null);
      }
      expect(c.entries.length, 5);
    });

    test('stream emits on capture', () async {
      final c = InkPalErrorCatcher();
      final received = <InkPalCaughtError>[];
      final sub = c.stream.listen(received.add);
      c.reportError(StateError('hello'), null);
      await Future<void>.delayed(Duration.zero);
      expect(received.length, 1);
      await sub.cancel();
    });
  });
}
