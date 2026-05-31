import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  test('symbols are exported from the barrel', () {
    expect(InkPalErrorCatcher, isNotNull);
    expect(InkPalHttpMonitor, isNotNull);
    expect(HttpRequestRecord, isNotNull);
    expect(InkPalErrorBoundary, isNotNull);
    expect(InkPalCaughtError, isNotNull);
    expect(inkpalRunApp, isNotNull);
    expect(generateInkPalBugReport, isNotNull);
    expect(inkpalRootRepaintKey, isA<GlobalKey>());
  });
}
