import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/src/communication/ws_channel.dart';

/// A connector that always fails — used to drive the reconnect loop.
Future<WebSocket> _failingConnector(String url) {
  return Future<WebSocket>.error(
      const SocketException('test: refused connection'));
}

/// A fake scheduler that records requested delays and fires them
/// synchronously via microtasks on demand.
class _FakeScheduler {
  final List<Duration> delays = [];
  final List<void Function()> _actions = [];

  void schedule(Duration delay, void Function() action) {
    delays.add(delay);
    _actions.add(action);
  }

  /// Pop + fire the earliest scheduled action.
  Future<void> fireNext() async {
    if (_actions.isEmpty) return;
    final fn = _actions.removeAt(0);
    fn();
    // Let the async connect complete and potentially re-schedule.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  int get pendingCount => _actions.length;
}

void main() {
  group('ReconnectingWebSocket reconnect policy', () {
    test('exponential backoff doubles each attempt (no jitter)', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://test',
        onMessage: (_) {},
        baseDelayMs: 500,
        jitterMs: 0,
        random: Random(0),
      );

      expect(ws.computeDelay(0).inMilliseconds, 500);
      expect(ws.computeDelay(1).inMilliseconds, 1000);
      expect(ws.computeDelay(2).inMilliseconds, 2000);
      expect(ws.computeDelay(3).inMilliseconds, 4000);
      expect(ws.computeDelay(4).inMilliseconds, 8000);

      ws.dispose();
    });

    test('jitter stays within [0, jitterMs]', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://test',
        onMessage: (_) {},
        baseDelayMs: 500,
        jitterMs: 200,
        random: Random(42),
      );

      for (var i = 0; i < 50; i++) {
        final d = ws.computeDelay(0).inMilliseconds;
        expect(d, greaterThanOrEqualTo(500));
        expect(d, lessThanOrEqualTo(700));
      }

      ws.dispose();
    });

    test('delay is capped at 5 minutes', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://test',
        onMessage: (_) {},
        baseDelayMs: 500,
        jitterMs: 0,
        random: Random(0),
      );

      // Large attempt count — unclamped value would be astronomical.
      final capped = ws.computeDelay(25);
      expect(capped.inMilliseconds, 5 * 60 * 1000);

      ws.dispose();
    });

    test('after 30 failures, stops retrying and logs exhausted',
        () async {
      final scheduler = _FakeScheduler();
      final ws = ReconnectingWebSocket(
        url: 'ws://test',
        onMessage: (_) {},
        baseDelayMs: 1,
        jitterMs: 0,
        maxRetries: 30,
        connector: _failingConnector,
        scheduler: scheduler.schedule,
        random: Random(0),
      );

      // First attempt fails → schedules attempt 2, etc.
      await ws.connect();

      // Drive the loop forward: each fireNext triggers the next failed
      // connect which schedules another retry — until exhaustion.
      var safety = 100;
      while (scheduler.pendingCount > 0 && safety-- > 0) {
        await scheduler.fireNext();
      }

      expect(ws.isExhausted, isTrue);
      expect(ws.reconnectAttempt, greaterThan(30));

      ws.dispose();
    });

    test('exhausted socket does not reconnect on further connect() calls',
        () async {
      final scheduler = _FakeScheduler();
      final ws = ReconnectingWebSocket(
        url: 'ws://test',
        onMessage: (_) {},
        baseDelayMs: 1,
        jitterMs: 0,
        maxRetries: 2,
        connector: _failingConnector,
        scheduler: scheduler.schedule,
      );

      await ws.connect();
      var safety = 20;
      while (scheduler.pendingCount > 0 && safety-- > 0) {
        await scheduler.fireNext();
      }
      expect(ws.isExhausted, isTrue);

      // Further connect() calls must not re-enter the loop.
      final before = scheduler.delays.length;
      await ws.connect();
      expect(scheduler.delays.length, before);

      ws.dispose();
    });

    test('scheduler observes the delay sequence for first few attempts',
        () async {
      final scheduler = _FakeScheduler();
      final ws = ReconnectingWebSocket(
        url: 'ws://test',
        onMessage: (_) {},
        baseDelayMs: 100,
        jitterMs: 0,
        maxRetries: 5,
        connector: _failingConnector,
        scheduler: scheduler.schedule,
        random: Random(0),
      );

      await ws.connect(); // first fail → schedules attempt 1
      await scheduler.fireNext(); // runs → fails → schedules attempt 2
      await scheduler.fireNext(); // runs → fails → schedules attempt 3

      // Delays should be 100, 200, 400 (first 3 entries).
      expect(scheduler.delays[0].inMilliseconds, 100);
      expect(scheduler.delays[1].inMilliseconds, 200);
      expect(scheduler.delays[2].inMilliseconds, 400);

      ws.dispose();
    });
  });
}
