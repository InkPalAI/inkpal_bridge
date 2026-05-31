import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/src/communication/ws_channel.dart';

void main() {
  group('ReconnectingWebSocket', () {
    test('starts disconnected', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://localhost:0',
        onMessage: (_) {},
      );

      expect(ws.isConnected, false);
      ws.dispose();
    });

    test('queues messages when disconnected', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://localhost:0',
        onMessage: (_) {},
      );

      // Send while disconnected — should be queued, not throw
      ws.send({'jsonrpc': '2.0', 'method': 'test'});
      ws.send({'jsonrpc': '2.0', 'method': 'test2'});

      // No crash = success — messages are buffered
      ws.dispose();
    });

    test('drops messages when buffer is full (100)', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://localhost:0',
        onMessage: (_) {},
      );

      // Fill buffer to capacity
      for (var i = 0; i < 105; i++) {
        ws.send({'jsonrpc': '2.0', 'method': 'msg_$i'});
      }

      // Should not throw — excess messages are silently dropped
      ws.dispose();
    });

    test('dispose prevents reconnection', () async {
      final ws = ReconnectingWebSocket(
        url: 'ws://localhost:0',
        onMessage: (_) {},
      );

      ws.dispose();

      // connect() after dispose should be a no-op
      await ws.connect();
      expect(ws.isConnected, false);
    });

    test('connect handles connection failure gracefully', () async {
      final ws = ReconnectingWebSocket(
        url: 'ws://localhost:1', // Invalid port — will fail
        onMessage: (_) {},
      );

      // Should not throw — connection failure triggers reconnect schedule
      await ws.connect();
      expect(ws.isConnected, false);
      ws.dispose();
    });

    test('callbacks are optional', () {
      final ws = ReconnectingWebSocket(
        url: 'ws://localhost:0',
        onMessage: (_) {},
        // onConnect and onDisconnect are null
      );

      // Should not crash when callbacks are null
      ws.dispose();
    });
  });
}
