import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Signature for a connector function that returns a live [WebSocket].
/// Injected for testing so the reconnect logic can be exercised without
/// touching real sockets.
typedef WebSocketConnector = Future<WebSocket> Function(String url);

/// Reconnecting WebSocket with exponential backoff + jitter.
///
/// Zero third-party deps — uses dart:io WebSocket directly.
///
/// Backoff policy:
/// - delay = `baseDelay * 2^attempt + random(0..jitterMs)`
/// - base delay: 500ms, jitter: 200ms
/// - capped at 5 minutes (300_000 ms)
/// - after [maxRetries] (default 30) consecutive failures, reconnect is
///   abandoned and `'bridge: reconnect exhausted'` is logged.
/// - attempt counter resets to 0 on a successful connect.
///
/// VM service extensions are intentionally decoupled from this channel —
/// they continue to work whether the WS is connected, reconnecting, or
/// exhausted.
class ReconnectingWebSocket {
  final String url;
  final void Function(Map<String, dynamic> message) onMessage;
  final void Function()? onConnect;
  final void Function()? onDisconnect;

  /// Base delay in ms for the first reconnect attempt.
  final int baseDelayMs;

  /// Maximum random jitter (ms) added on each scheduled reconnect.
  final int jitterMs;

  /// Hard cap on the computed delay.
  final int maxDelayMs;

  /// After this many consecutive failed reconnects, give up.
  final int maxRetries;

  /// Injectable connector so tests can swap in a fake.
  final WebSocketConnector _connector;

  /// Injectable scheduler so tests can observe the chosen delays without
  /// actually waiting. Defaults to [Future.delayed].
  final void Function(Duration delay, void Function() action) _scheduler;

  /// Injectable random source so jitter is deterministic in tests.
  final Random _random;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  int _attempt = 0;
  bool _disposed = false;
  bool _connected = false;
  bool _reconnecting = false;
  bool _exhausted = false;

  /// Messages queued while disconnected, flushed on reconnect.
  /// Capped at 100 to avoid unbounded memory growth.
  final List<Map<String, dynamic>> _pendingMessages = [];
  static const int _maxPendingMessages = 100;

  bool get isConnected => _connected;

  /// Current consecutive failure count. Resets on successful connect.
  @visibleForTesting
  int get reconnectAttempt => _attempt;

  /// True once the retry budget is exhausted.
  @visibleForTesting
  bool get isExhausted => _exhausted;

  ReconnectingWebSocket({
    required this.url,
    required this.onMessage,
    this.onConnect,
    this.onDisconnect,
    this.baseDelayMs = 500,
    this.jitterMs = 200,
    this.maxDelayMs = 5 * 60 * 1000,
    this.maxRetries = 30,
    @visibleForTesting WebSocketConnector? connector,
    @visibleForTesting
    void Function(Duration delay, void Function() action)? scheduler,
    @visibleForTesting Random? random,
  })  : _connector = connector ?? WebSocket.connect,
        _scheduler = scheduler ??
            ((delay, action) => Future<void>.delayed(delay, action)),
        _random = random ?? Random();

  /// Compute the delay for the next reconnect attempt.
  /// Exposed for testing — keeps the math visible.
  @visibleForTesting
  Duration computeDelay(int attempt) {
    // Protect against overflow: 2^attempt grows fast; clamp before multiply.
    final capped = attempt.clamp(0, 30);
    final expPart = baseDelayMs * (1 << capped);
    final jitter = jitterMs > 0 ? _random.nextInt(jitterMs + 1) : 0;
    final total = expPart + jitter;
    return Duration(milliseconds: total > maxDelayMs ? maxDelayMs : total);
  }

  Future<void> connect() async {
    if (_disposed || _exhausted) return;

    try {
      _socket = await _connector(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
            'WebSocket connection to $url timed out after 10s',
            const Duration(seconds: 10),
          );
        },
      );
      _connected = true;
      _reconnecting = false;
      _attempt = 0;
      onConnect?.call();
      _flushPendingMessages();

      _subscription = _socket!.listen(
        (data) {
          try {
            final message = jsonDecode(data as String) as Map<String, dynamic>;
            onMessage(message);
          } catch (e) {
            debugPrint('[InkPal WS] Failed to parse message: $e');
          }
        },
        onDone: () {
          _connected = false;
          onDisconnect?.call();
          _scheduleReconnect();
        },
        onError: (Object error) {
          debugPrint('[InkPal WS] Stream error: $error');
          _connected = false;
          onDisconnect?.call();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      debugPrint('[InkPal WS] Connection failed: $e');
      _connected = false;
      _scheduleReconnect();
    }
  }

  void send(Map<String, dynamic> jsonRpcMessage) {
    if (!_connected || _socket == null || _reconnecting) {
      if (_pendingMessages.length < _maxPendingMessages) {
        _pendingMessages.add(jsonRpcMessage);
      } else {
        debugPrint(
            '[InkPal WS] Message dropped — pending buffer full ($_maxPendingMessages)');
      }
      return;
    }
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.add(jsonEncode(jsonRpcMessage));
    } catch (e) {
      debugPrint('[InkPal WS] Send failed: $e');
    }
  }

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty) return;
    debugPrint(
        '[InkPal WS] Flushing ${_pendingMessages.length} buffered messages');
    final messages = List<Map<String, dynamic>>.from(_pendingMessages);
    _pendingMessages.clear();
    for (final msg in messages) {
      send(msg);
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _attempt++;
    if (_attempt > maxRetries) {
      _exhausted = true;
      _reconnecting = false;
      debugPrint('bridge: reconnect exhausted');
      return;
    }
    _reconnecting = true;
    final delay = computeDelay(_attempt - 1);
    debugPrint(
        '[InkPal WS] Reconnecting in ${delay.inMilliseconds}ms (attempt $_attempt/$maxRetries)...');
    _scheduler(delay, () {
      if (!_disposed && !_exhausted) connect();
    });
  }

  void dispose() {
    _disposed = true;
    _connected = false;
    _subscription?.cancel();
    _socket?.close();
  }
}
