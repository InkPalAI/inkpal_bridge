import 'dart:async';

import 'package:flutter/foundation.dart';

/// A single deduplicated caught error entry.
///
/// Multiple identical errors within the dedupe window collapse into one
/// entry with [count] incremented and [lastSeen] updated.
class InkPalCaughtError {
  /// Stable identifier derived from [hash].
  final String id;

  /// Where the error came from.
  ///
  /// One of: `flutter` (FlutterError.onError), `platform`
  /// (PlatformDispatcher.onError), `zone` (runZonedGuarded handler),
  /// or `app` (user-reported via [InkPalErrorCatcher.reportError]).
  final String source;

  /// The original error object.
  final Object error;

  /// The stack trace, if any.
  final StackTrace? stackTrace;

  /// When this error was first observed.
  final DateTime firstSeen;

  /// When this error was most recently observed.
  DateTime lastSeen;

  /// Number of times this error has been observed within the dedupe window.
  int count;

  /// Internal hash used for deduplication.
  final String hash;

  InkPalCaughtError({
    required this.id,
    required this.source,
    required this.error,
    required this.stackTrace,
    required this.firstSeen,
    required this.lastSeen,
    required this.count,
    required this.hash,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'source': source,
        'error': error.toString(),
        'errorType': error.runtimeType.toString(),
        'stackTrace': stackTrace?.toString(),
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'count': count,
      };
}

/// Captures Flutter framework errors, platform dispatcher errors, and
/// uncaught zone errors in one place.
///
/// Deduplicates identical errors within a configurable time window using
/// a hash of the error type, string form, and top-3 stack frames. Stores
/// entries in a ring buffer capped at [maxEntries].
///
/// **Debug-only** — release builds should avoid calling [install] /
/// [runGuarded]. Callers gate on `kReleaseMode`.
///
/// Chains any previously-installed [FlutterError.onError] and
/// [PlatformDispatcher.instance.onError] handlers so other tooling is
/// not clobbered.
class InkPalErrorCatcher {
  InkPalErrorCatcher({
    this.maxEntries = 100,
    this.dedupeWindow = const Duration(seconds: 2),
  });

  /// Max number of deduped entries retained in memory (ring buffer).
  final int maxEntries;

  /// Within this window, identical errors collapse into one entry.
  final Duration dedupeWindow;

  final List<InkPalCaughtError> _entries = [];
  final StreamController<InkPalCaughtError> _controller =
      StreamController<InkPalCaughtError>.broadcast();

  FlutterExceptionHandler? _previousFlutterOnError;
  bool Function(Object, StackTrace)? _previousPlatformOnError;
  bool _installed = false;

  /// Stream of deduplicated caught errors (broadcast).
  Stream<InkPalCaughtError> get stream => _controller.stream;

  /// Snapshot of current entries (oldest first).
  List<InkPalCaughtError> get entries => List.unmodifiable(_entries);

  /// Whether [install] has been called.
  bool get isInstalled => _installed;

  /// Install error capture hooks. Safe to call once; subsequent calls no-op.
  void install() {
    if (_installed) return;
    _installed = true;

    _previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _capture(
        source: 'flutter',
        error: details.exception,
        stackTrace: details.stack,
      );
      // Chain previous handler so other tooling still fires.
      _previousFlutterOnError?.call(details);
    };

    _previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      _capture(source: 'platform', error: error, stackTrace: stack);
      final prev = _previousPlatformOnError;
      if (prev != null) {
        return prev(error, stack);
      }
      return true;
    };
  }

  /// Restore previous handlers. Primarily for tests.
  void uninstall() {
    if (!_installed) return;
    FlutterError.onError = _previousFlutterOnError;
    PlatformDispatcher.instance.onError = _previousPlatformOnError;
    _installed = false;
  }

  /// Run [runner] inside a guarded zone. Uncaught errors from either sync
  /// or async code inside [runner] are captured with source='zone'.
  void runGuarded(void Function() runner) {
    runZonedGuarded(runner, (Object error, StackTrace stack) {
      _capture(source: 'zone', error: error, stackTrace: stack);
    });
  }

  /// Report an error from app code (e.g. inside a try/catch block).
  void reportError(Object error, StackTrace? stack, {String source = 'app'}) {
    _capture(source: source, error: error, stackTrace: stack);
  }

  /// Remove all entries.
  void clear() => _entries.clear();

  /// Close internal streams. Safe to call multiple times.
  Future<void> dispose() async {
    uninstall();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  // ── Internal ──

  void _capture({
    required String source,
    required Object error,
    required StackTrace? stackTrace,
  }) {
    final now = DateTime.now();
    final hash = _hashOf(error, stackTrace);

    // Search for a recent matching entry within the dedupe window.
    for (var i = _entries.length - 1; i >= 0; i--) {
      final e = _entries[i];
      if (e.hash == hash &&
          now.difference(e.lastSeen) <= dedupeWindow) {
        e.count += 1;
        e.lastSeen = now;
        _controller.add(e);
        return;
      }
    }

    final entry = InkPalCaughtError(
      id: hash,
      source: source,
      error: error,
      stackTrace: stackTrace,
      firstSeen: now,
      lastSeen: now,
      count: 1,
      hash: hash,
    );
    _entries.add(entry);
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }
    _controller.add(entry);
  }

  static String _hashOf(Object error, StackTrace? stack) {
    final typeStr = error.runtimeType.toString();
    final msgStr = error.toString();
    String top3 = '';
    if (stack != null) {
      final lines = stack
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(3)
          .join('\n');
      top3 = lines;
    }
    final combined = '$typeStr|$msgStr|$top3';
    // Simple non-crypto hash — deterministic and zero-dep.
    var h = 0;
    for (final codeUnit in combined.codeUnits) {
      h = (h * 31 + codeUnit) & 0x7fffffff;
    }
    return 'err_${h.toRadixString(16)}';
  }
}
