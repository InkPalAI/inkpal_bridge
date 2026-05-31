import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  group('generateInkPalBugReport', () {
    test('generates report with empty inputs', () {
      final out = generateInkPalBugReport(
        errors: InkPalErrorCatcher(),
      );
      expect(out, contains('# Bug Report'));
      expect(out, contains('## Summary'));
      expect(out, contains('No errors captured'));
    });

    test('includes error info', () {
      final c = InkPalErrorCatcher();
      c.reportError(StateError('boom'), StackTrace.current);
      final out = generateInkPalBugReport(
        errors: c,
        currentRoute: '/home',
        appState: {'user': 'tezz'},
      );
      expect(out, contains('StateError'));
      expect(out, contains('/home'));
      expect(out, contains('tezz'));
    });

    test('truncates very long output', () {
      final c = InkPalErrorCatcher(dedupeWindow: Duration.zero);
      final big = 'x' * 500;
      for (var i = 0; i < 30; i++) {
        c.reportError(StateError('$big-$i'), StackTrace.current);
      }
      final out = generateInkPalBugReport(errors: c);
      expect(out.length, lessThanOrEqualTo(8200));
    });
  });
}
