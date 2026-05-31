import 'package:flutter/foundation.dart';

import 'log_event.dart';
import 'log_observer.dart';

/// InkPal's own structured logger — zero third-party dependencies.
///
/// Drop-in replacement for Talker with the exact API surface InkPal needs:
/// - [log], [debug], [warning], [error] for direct logging
/// - [handle] for capturing errors/exceptions from Flutter hooks
/// - [history] for querying past events
/// - [addObserver] for real-time streaming to WebSocket / ring buffer
class InkPalLogger {
  final List<InkPalLogEvent> _history = [];
  final List<InkPalLogObserver> _observers = [];
  final int maxHistorySize;

  /// All recorded events (oldest first).
  List<InkPalLogEvent> get history => List.unmodifiable(_history);

  InkPalLogger({this.maxHistorySize = 1000});

  /// Attach an observer that receives all future events.
  void addObserver(InkPalLogObserver observer) {
    _observers.add(observer);
  }

  /// Remove a previously attached observer.
  void removeObserver(InkPalLogObserver observer) {
    _observers.remove(observer);
  }

  // ── Direct logging ──────────────────────────────────────────────

  void log(String message, {String? key, InkPalLogLevel level = InkPalLogLevel.info}) {
    final event = InkPalLog(message, key: key, level: level);
    _record(event);
    _notifyLog(event);
  }

  void debug(String message, {String? key}) =>
      log(message, key: key, level: InkPalLogLevel.debug);

  void warning(String message, {String? key}) =>
      log(message, key: key, level: InkPalLogLevel.warning);

  void error(Object error, [StackTrace? stackTrace, String? message]) {
    final event = InkPalError(error, stackTrace: stackTrace, message: message);
    _record(event);
    _notifyError(event);
  }

  // ── Error/exception capture (called by Flutter hooks) ───────────

  /// Capture an error or exception from Flutter's error hooks.
  ///
  /// Automatically distinguishes Exception vs Error:
  /// - [Exception] → dispatched as [InkPalException]
  /// - Everything else → dispatched as [InkPalError]
  void handle(Object errorOrException, [StackTrace? stackTrace, String? message]) {
    if (errorOrException is Exception) {
      final event = InkPalException(
        errorOrException,
        stackTrace: stackTrace,
        message: message,
      );
      _record(event);
      _notifyException(event);
    } else {
      final event = InkPalError(
        errorOrException,
        stackTrace: stackTrace,
        message: message,
      );
      _record(event);
      _notifyError(event);
    }
  }

  // ── Internal ────────────────────────────────────────────────────

  void _record(InkPalLogEvent event) {
    if (_history.length >= maxHistorySize) {
      _history.removeAt(0);
    }
    _history.add(event);

    if (kDebugMode) {
      debugPrint('[InkPal] ${event.generateTextMessage()}');
    }
  }

  void _notifyLog(InkPalLog log) {
    for (final o in _observers) {
      try {
        o.onLog(log);
      } catch (e) {
        debugPrint('[InkPal] Logger observer error: $e');
      }
    }
  }

  void _notifyError(InkPalError err) {
    for (final o in _observers) {
      try {
        o.onError(err);
      } catch (e) {
        debugPrint('[InkPal] Logger observer error: $e');
      }
    }
  }

  void _notifyException(InkPalException ex) {
    for (final o in _observers) {
      try {
        o.onException(ex);
      } catch (e) {
        debugPrint('[InkPal] Logger observer error: $e');
      }
    }
  }
}
