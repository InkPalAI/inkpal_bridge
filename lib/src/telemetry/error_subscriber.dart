import 'dart:async';

import '../inspection/navigator_observer.dart';
import '../inspection/semantics_walker.dart';
import '../logger/inkpal_logger.dart';
import '../logger/log_event.dart';
import '../logger/log_observer.dart' show InkPalLogObserver;
import '../memory/state_journal.dart';

/// Subscribes to runtime errors and enriches them with context.
///
/// When the AI asks to "watch for errors", this class:
/// 1. Listens to all errors from [InkPalLogger]
/// 2. Enriches each error with widget tree, state snapshot, route, and recent logs
/// 3. Streams enriched errors to subscribers (MCP server via WebSocket)
///
/// Used by the HEAL domain's AutoRepairLoop to get rich error context
/// for generating accurate fixes.
class ErrorSubscriber implements InkPalLogObserver {
  final InkPalLogger _logger;
  final SemanticsWalker _walker;
  final StateJournal? _journal;

  bool _watching = false;
  final _errorController = StreamController<EnrichedError>.broadcast();
  final List<EnrichedError> _recentErrors = [];
  static const _maxRecent = 50;

  /// Stream of enriched runtime errors.
  Stream<EnrichedError> get errors => _errorController.stream;

  /// Whether actively watching for errors.
  bool get isWatching => _watching;

  /// Recent errors (up to last 50).
  List<EnrichedError> get recentErrors => List.unmodifiable(_recentErrors);

  ErrorSubscriber({
    required InkPalLogger logger,
    required SemanticsWalker walker,
    StateJournal? journal,
  })  : _logger = logger,
        _walker = walker,
        _journal = journal {
    // Attach immediately so errors that occur before startWatching() are
    // retained in the ring buffer and drained when a subscriber attaches.
    _logger.addObserver(this);
  }

  /// Start watching for runtime errors. New errors are pushed to the
  /// [errors] stream. Pre-existing errors remain available via
  /// [recentErrors].
  void startWatching() {
    _watching = true;
  }

  /// Stop pushing to the error stream. Errors continue to be buffered in
  /// [recentErrors] so later subscribers don't miss them.
  void stopWatching() {
    _watching = false;
  }

  /// Check if a specific error pattern has occurred since [sinceMs].
  /// Used by FixVerifier to confirm an error no longer occurs.
  bool hasErrorSince(String errorPattern, int sinceMs) {
    final since = DateTime.fromMillisecondsSinceEpoch(sinceMs);
    return _recentErrors.any((e) =>
        e.timestamp.isAfter(since) &&
        (e.message.contains(errorPattern) ||
            e.error.contains(errorPattern)));
  }

  /// Get all errors matching a pattern since [sinceMs].
  List<EnrichedError> errorsSince(String errorPattern, int sinceMs) {
    final since = DateTime.fromMillisecondsSinceEpoch(sinceMs);
    return _recentErrors
        .where((e) =>
            e.timestamp.isAfter(since) &&
            (e.message.contains(errorPattern) ||
                e.error.contains(errorPattern)))
        .toList();
  }

  /// Clear all recent errors.
  void clear() {
    _recentErrors.clear();
  }

  @override
  void onLog(InkPalLog log) {
    // Regular logs are not errors — skip.
  }

  @override
  void onError(InkPalError err) {
    // Always capture — gating the ring buffer on _watching used to drop
    // errors that occurred before the first watch() call. _watching now
    // controls only stream notification.
    _captureEnriched(
      message: err.message ?? err.error.toString(),
      error: err.error.toString(),
      stackTrace: err.stackTrace?.toString(),
      time: err.time,
    );
  }

  @override
  void onException(InkPalException exception) {
    _captureEnriched(
      message: exception.message ?? exception.exception.toString(),
      error: exception.exception.toString(),
      stackTrace: exception.stackTrace?.toString(),
      time: exception.time,
    );
  }

  void _captureEnriched({
    required String message,
    required String error,
    String? stackTrace,
    required DateTime time,
  }) {
    // Capture widget tree context at error time
    String? screenContent;
    int elementCount = 0;
    try {
      final ctx = _walker.captureScreenContext();
      screenContent = ctx.toPromptString();
      elementCount = ctx.elements.length;
    } catch (_) {
      // Best-effort — walker may not be ready
    }

    // Capture current state snapshot
    Map<String, dynamic>? lastState;
    int? lastSnapshotId;
    final latest = _journal?.latest;
    if (latest != null) {
      lastState = latest.state;
      lastSnapshotId = latest.id;
    }

    final enriched = EnrichedError(
      message: message,
      error: error,
      stackTrace: stackTrace,
      route: InkPalNavigatorObserver.currentRoute,
      screenContent: screenContent,
      elementCount: elementCount,
      lastState: lastState,
      lastSnapshotId: lastSnapshotId,
      timestamp: time,
    );

    _recentErrors.add(enriched);
    while (_recentErrors.length > _maxRecent) {
      _recentErrors.removeAt(0);
    }
    // Stream notification is gated on _watching so subscribers can
    // opt in; the ring buffer is always populated.
    if (_watching) {
      _errorController.add(enriched);
    }
  }

  void dispose() {
    _watching = false;
    _logger.removeObserver(this);
    _errorController.close();
  }
}

/// A runtime error enriched with full app context.
///
/// This gives the AI everything it needs to generate an accurate fix:
/// - The error itself + stack trace
/// - What was on screen (widget tree)
/// - What route the user was on
/// - What the app state looked like
class EnrichedError {
  final String message;
  final String error;
  final String? stackTrace;
  final String? route;
  final String? screenContent;
  final int elementCount;
  final Map<String, dynamic>? lastState;
  final int? lastSnapshotId;
  final DateTime timestamp;

  EnrichedError({
    required this.message,
    required this.error,
    this.stackTrace,
    this.route,
    this.screenContent,
    this.elementCount = 0,
    this.lastState,
    this.lastSnapshotId,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'message': message,
        'error': error,
        'stackTrace': stackTrace,
        'route': route,
        'screenContent': screenContent,
        'elementCount': elementCount,
        'lastState': lastState,
        'lastSnapshotId': lastSnapshotId,
        'timestamp': timestamp.toIso8601String(),
        'timestampMs': timestamp.millisecondsSinceEpoch,
      };
}
