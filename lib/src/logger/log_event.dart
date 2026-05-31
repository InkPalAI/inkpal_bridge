/// Log severity levels.
enum InkPalLogLevel {
  debug,
  info,
  warning,
  error,
  critical;

  /// Display name for serialization.
  String get label => name;
}

/// Base log event — every log, error, and exception produces one of these.
sealed class InkPalLogEvent {
  final String? message;
  final String? key;
  final DateTime time;
  final InkPalLogLevel level;

  InkPalLogEvent({
    this.message,
    this.key,
    DateTime? time,
    this.level = InkPalLogLevel.info,
  }) : time = time ?? DateTime.now();

  /// Human-readable text representation.
  String generateTextMessage() {
    final buf = StringBuffer();
    if (key != null) buf.write('[$key] ');
    buf.write(message ?? '');
    return buf.toString();
  }
}

/// A regular log entry (info, debug, warning).
class InkPalLog extends InkPalLogEvent {
  InkPalLog(
    String message, {
    super.key,
    super.level,
    super.time,
  }) : super(message: message);
}

/// An error captured by the logger.
class InkPalError extends InkPalLogEvent {
  final Object error;
  final StackTrace? stackTrace;

  InkPalError(
    this.error, {
    this.stackTrace,
    super.message,
    super.key,
    super.time,
  }) : super(level: InkPalLogLevel.error);
}

/// An exception captured by the logger.
class InkPalException extends InkPalLogEvent {
  final Object exception;
  final StackTrace? stackTrace;

  InkPalException(
    this.exception, {
    this.stackTrace,
    super.message,
    super.key,
    super.time,
  }) : super(level: InkPalLogLevel.error);
}
