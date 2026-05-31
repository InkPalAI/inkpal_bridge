import 'dart:async';

import 'package:flutter/foundation.dart';

import '../license/feature_tier.dart';
import '../license/license_validator.dart';
import '../telemetry/error_catcher.dart';

/// Prints a one-time welcome banner + ongoing diagnostic activity to the
/// debug console. Designed so a developer who runs `inkpalRunApp(MyApp())`
/// sees the bridge come alive immediately, with a clear path to richer
/// integration whenever they want it.
///
/// Three responsibilities:
///   1. Print the welcome banner once on bridge startup.
///   2. Print periodic idle diagnostics when no client is connected.
///   3. Surface client connect / disconnect transitions inline.
///
/// Skipped entirely in release builds.
class InkPalWelcomeConsole {
  InkPalWelcomeConsole._();
  static final InkPalWelcomeConsole instance = InkPalWelcomeConsole._();

  Timer? _idleTimer;
  StreamSubscription<InkPalCaughtError>? _errorSub;
  bool _clientConnected = false;
  DateTime? _startedAt;

  /// Counters that the bridge updates as it observes runtime activity.
  /// Read by the idle reporter to show "the bridge is alive and watching."
  int _widgetCount = 0;
  int _routeCount = 0;
  int _errorCount = 0;
  int _httpRequestCount = 0;

  /// Called once at bridge startup. Prints the banner and arms the idle
  /// reporter.
  void start({
    required String serverUrl,
    required String licenseKey,
    InkPalErrorCatcher? errorCatcher,
  }) {
    if (kReleaseMode) return;
    if (_startedAt != null) return;
    _startedAt = DateTime.now();

    if (errorCatcher != null) {
      _errorSub?.cancel();
      _errorSub = errorCatcher.stream.listen(_onCaughtError);
    }

    final tier = InkPalLicense.instance.tier;
    final licenseLine = _licenseLine(licenseKey: licenseKey, tier: tier);
    final lines = <String>[
      '',
      '┌──────────────────────────────────────────────────────────────┐',
      '│  InkPal Bridge active   ·   $serverUrl${' ' * (33 - serverUrl.length)}│',
      '│                                                              │',
      '│  Connect an AI assistant to see + debug your running app.    │',
      '│                                                              │',
      '│    npx inkpal start    (one-line setup for Claude/Cursor/…)  │',
      '│    inkpal.ai/setup     (manual MCP config + per-IDE guides)  │',
      '│                                                              │',
      '│  ${licenseLine.padRight(60)}│',
      '└──────────────────────────────────────────────────────────────┘',
      '',
    ];
    for (final l in lines) {
      debugPrint(l);
    }

    _scheduleIdleReport();
  }

  /// Called when a client (MCP proxy) connects over WebSocket.
  void onClientConnected({String? clientName}) {
    if (kReleaseMode) return;
    _clientConnected = true;
    final tag = clientName == null || clientName.isEmpty
        ? 'AI client connected'
        : 'AI client connected ($clientName)';
    debugPrint('→ [InkPal] $tag');
    debugPrint('→ [InkPal] Ready to receive commands.');
    _idleTimer?.cancel();
    _idleTimer = null;
  }

  /// Called when the client disconnects.
  void onClientDisconnected() {
    if (kReleaseMode) return;
    if (!_clientConnected) return;
    _clientConnected = false;
    debugPrint('→ [InkPal] AI client disconnected');
    _scheduleIdleReport();
  }

  /// Bridge plumbing updates these counts as it observes the app.
  /// Used by the idle reporter.
  void updateCounts({
    int? widgets,
    int? routes,
    int? errors,
    int? httpRequests,
  }) {
    if (widgets != null) _widgetCount = widgets;
    if (routes != null) _routeCount = routes;
    if (errors != null) _errorCount = errors;
    if (httpRequests != null) _httpRequestCount = httpRequests;
  }

  /// Called when a Flutter error is caught. Prints a compact, scannable
  /// summary so developers see immediate value even without cloud lookup.
  void onErrorCaught({
    required String message,
    String? location,
    String? hint,
  }) {
    if (kReleaseMode) return;
    _errorCount++;
    debugPrint('');
    debugPrint('✗ [InkPal] Flutter error');
    debugPrint('  $message');
    if (location != null && location.isNotEmpty) {
      debugPrint('  at $location');
    }
    if (hint != null && hint.isNotEmpty) {
      debugPrint('  hint: $hint');
    }
    debugPrint('');
  }

  /// Cancel the idle reporter (used on bridge shutdown / hot restart).
  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _errorSub?.cancel();
    _errorSub = null;
  }

  // Internal stream listener — translates a caught-error event into the
  // friendly console format. First-line location parsing is best-effort.
  void _onCaughtError(InkPalCaughtError e) {
    if (kReleaseMode) return;
    if (_clientConnected) return;
    final stackText = e.stackTrace?.toString() ?? '';
    final loc = _firstLocation(stackText);
    onErrorCaught(message: e.error.toString(), location: loc);
  }

  String? _firstLocation(String stackText) {
    if (stackText.isEmpty) return null;
    final lines = stackText.split('\n');
    for (final l in lines) {
      final match = RegExp(r'package:[^\s]+\.dart[: \s][\d:]+').firstMatch(l);
      if (match != null) return match.group(0);
    }
    return null;
  }

  // ── private ──

  void _scheduleIdleReport() {
    if (kReleaseMode) return;
    _idleTimer?.cancel();
    // First idle report after 30s. Subsequent reports every 2 minutes so
    // the console doesn't get spammy during long sessions.
    _idleTimer = Timer(const Duration(seconds: 30), () {
      _emitIdleReport();
      _idleTimer = Timer.periodic(
        const Duration(minutes: 2),
        (_) => _emitIdleReport(),
      );
    });
  }

  void _emitIdleReport() {
    if (_clientConnected) return;
    final parts = <String>[
      'widgets ${_widgetCount > 0 ? '$_widgetCount' : '-'}',
      'routes ${_routeCount > 0 ? '$_routeCount' : '-'}',
      'errors $_errorCount',
      'http $_httpRequestCount',
    ];
    debugPrint('→ [InkPal] Idle — ${parts.join(', ')}.   Connect: npx inkpal start');
  }

  String _licenseLine({required String licenseKey, required InkPalTier tier}) {
    final isOffline = licenseKey.startsWith('ink_offline_');
    final isUnregistered = licenseKey.isEmpty;

    if (isOffline || isUnregistered) {
      return 'License: Free (offline)   ·   Get more: inkpal.ai/signup';
    }
    switch (tier) {
      case InkPalTier.pro:
        return 'License: Pro   ·   Thanks for supporting InkPal';
      case InkPalTier.studio:
        return 'License: Studio   ·   Thanks for supporting InkPal';
      case InkPalTier.free:
        return 'License: Free   ·   Get more: inkpal.ai/signup';
    }
  }
}
