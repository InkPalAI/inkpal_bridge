import '../communication/telemetry_sender.dart';
import '../logger/log_event.dart';
import '../logger/log_observer.dart';

/// Log observer that serializes events and streams to InkPal MCP server.
class InkPalTelemetryObserver extends InkPalLogObserver {
  final TelemetrySender _sender;
  final String? Function() _getCurrentRoute;

  InkPalTelemetryObserver({
    required TelemetrySender sender,
    required String? Function() getCurrentRoute,
  })  : _sender = sender,
        _getCurrentRoute = getCurrentRoute;

  @override
  void onLog(InkPalLog log) {
    _sender.enqueue({
      'type': 'log',
      'level': log.level.label,
      'key': log.key,
      'message': log.message,
      'timestamp': log.time.toIso8601String(),
      'route': _getCurrentRoute(),
    });
  }

  @override
  void onError(InkPalError err) {
    _sender.sendImmediate({
      'type': 'error',
      'message': err.message,
      'error': err.error.toString(),
      'stackTrace': err.stackTrace?.toString(),
      'timestamp': err.time.toIso8601String(),
      'route': _getCurrentRoute(),
    });
  }

  @override
  void onException(InkPalException exception) {
    _sender.sendImmediate({
      'type': 'exception',
      'message': exception.message,
      'exception': exception.exception.toString(),
      'stackTrace': exception.stackTrace?.toString(),
      'timestamp': exception.time.toIso8601String(),
      'route': _getCurrentRoute(),
    });
  }
}
