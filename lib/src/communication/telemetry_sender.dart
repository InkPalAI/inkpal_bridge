import 'dart:async';

import 'protocol.dart';
import 'ws_channel.dart';

/// Batches telemetry events and sends via WebSocket.
/// - Errors/exceptions: sent IMMEDIATELY
/// - Info/debug logs: batched every 500ms
class TelemetrySender {
  final ReconnectingWebSocket _ws;
  final List<Map<String, dynamic>> _batch = [];
  Timer? _batchTimer;

  TelemetrySender({required ReconnectingWebSocket ws}) : _ws = ws;

  /// Send an event immediately (for errors/exceptions).
  void sendImmediate(Map<String, dynamic> event) {
    _ws.send(JsonRpc.notification('telemetry', event));
  }

  /// Enqueue an event for batched sending.
  void enqueue(Map<String, dynamic> event) {
    _batch.add(event);
    _batchTimer ??= Timer(const Duration(milliseconds: 500), flush);
  }

  /// Send all queued events now.
  void flush() {
    _batchTimer?.cancel();
    _batchTimer = null;
    if (_batch.isEmpty) return;

    final events = List<Map<String, dynamic>>.from(_batch);
    _batch.clear();

    _ws.send(
      JsonRpc.notification('telemetry_batch', {'events': events}),
    );
  }

  void dispose() {
    _batchTimer?.cancel();
    _batchTimer = null;
    _batch.clear();
  }
}
