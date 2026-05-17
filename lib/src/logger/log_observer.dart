import 'log_event.dart';

/// Observer interface for InkPalLogger events.
///
/// Replaces TalkerObserver — attach to InkPalLogger to receive
/// all log, error, and exception events in real-time.
abstract class InkPalLogObserver {
  /// Called for regular log entries.
  void onLog(InkPalLog log) {}

  /// Called when an error is captured.
  void onError(InkPalError err) {}

  /// Called when an exception is captured.
  void onException(InkPalException exception) {}
}
