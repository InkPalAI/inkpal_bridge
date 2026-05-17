import '../logger/log_event.dart';
import '../logger/log_observer.dart';

/// In-memory ring buffer of the last [maxEvents] log events.
///
/// Used by VM Service extension `ext.flutter.inkpal.getRecentLogs` to give
/// InkPal's MCP tools a time-windowed view of what happened during an action:
///
///   1. MCP notes timestamp before tap
///   2. Tap executes
///   3. MCP calls `getRecentLogs?since=$beforeTimestamp`
///   4. Returns only logs that happened during the action window
///
/// This enables full log correlation without separate query calls.
class InkPalLogBuffer extends InkPalLogObserver {
  final int maxEvents;
  final String? Function()? getCurrentRoute;

  final List<Map<String, dynamic>> _events = [];

  InkPalLogBuffer({this.maxEvents = 200, this.getCurrentRoute});

  /// All buffered events (snapshot).
  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  /// Events since [sinceMs] (epoch milliseconds). Returns all if sinceMs is 0.
  List<Map<String, dynamic>> eventsSince(int sinceMs) {
    if (sinceMs <= 0) return events;
    return _events
        .where((e) => (e['timestamp_ms'] as int? ?? 0) > sinceMs)
        .toList();
  }

  void _add(Map<String, dynamic> event) {
    if (_events.length >= maxEvents) _events.removeAt(0);
    _events.add({
      ...event,
      'timestamp_ms': DateTime.now().millisecondsSinceEpoch,
      'route': getCurrentRoute?.call(),
    });
  }

  @override
  void onLog(InkPalLog log) {
    _add({
      'type': 'log',
      'level': log.level.label,
      'key': log.key,
      'message': log.generateTextMessage(),
    });
  }

  @override
  void onError(InkPalError err) {
    _add({
      'type': 'error',
      'message': err.message ?? err.error.toString(),
      'error': err.error.toString(),
      'stackTrace': err.stackTrace.toString().split('\n').take(8).join('\n'),
    });
  }

  @override
  void onException(InkPalException exception) {
    _add({
      'type': 'exception',
      'message': exception.message ?? exception.exception.toString(),
      'exception': exception.exception.toString(),
      'stackTrace': exception.stackTrace.toString().split('\n').take(8).join('\n'),
    });
  }
}
