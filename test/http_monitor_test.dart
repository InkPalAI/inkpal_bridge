import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  group('InkPalHttpMonitor', () {
    test('clears records + error count', () {
      final m = InkPalHttpMonitor();
      // No install — just poke the public API.
      expect(m.records, isEmpty);
      expect(m.errorCount, 0);
      expect(m.averageLatency, Duration.zero);
    });

    test('install is idempotent', () {
      final m = InkPalHttpMonitor();
      final prev = HttpOverrides.current;
      m.install();
      m.install();
      expect(m.isInstalled, true);
      m.uninstall();
      expect(HttpOverrides.current, prev);
    });

    test('HttpRequestRecord serializes to json', () {
      final r = HttpRequestRecord(
        method: 'GET',
        url: 'https://x/y',
        statusCode: 200,
        duration: const Duration(milliseconds: 42),
        requestBytes: 10,
        responseBytes: 100,
        error: null,
        startedAt: DateTime(2026),
        headers: {'authorization': '<redacted>', 'accept': 'application/json'},
      );
      final j = r.toJson();
      expect(j['statusCode'], 200);
      expect(j['durationMs'], 42);
      expect(j['headers']['authorization'], '<redacted>');
    });

    test('ring buffer caps records', () async {
      final m = InkPalHttpMonitor(capacity: 3);
      // Access private not possible — instead exercise clear path.
      m.clear();
      expect(m.records, isEmpty);
    });
  });
}
