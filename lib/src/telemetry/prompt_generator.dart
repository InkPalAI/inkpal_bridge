import 'dart:convert';

import '../logger/inkpal_logger.dart';
import '../network/http_monitor.dart';
import 'error_catcher.dart';

const int _maxChars = 8000;

/// Packages runtime state as a markdown bug report suitable for LLM input.
///
/// Includes the last few deduped errors, recent HTTP requests, recent logs,
/// the current route, and app state. Caps total length at ~8k characters
/// (truncating sections with a `… N more entries` suffix).
String generateInkPalBugReport({
  required InkPalErrorCatcher errors,
  InkPalHttpMonitor? http,
  InkPalLogger? logger,
  String? currentRoute,
  Map<String, dynamic>? appState,
}) {
  final buf = StringBuffer();
  buf.writeln('# Bug Report');
  buf.writeln();

  // ── Summary ──
  buf.writeln('## Summary');
  final entries = errors.entries;
  if (entries.isEmpty) {
    buf.writeln('No errors captured.');
  } else {
    final top = entries.last;
    buf.writeln('- Top error: `${top.error.runtimeType}`');
    buf.writeln('- Message: ${_oneLine(top.error.toString())}');
    buf.writeln('- Source: ${top.source}');
    buf.writeln('- Seen: ${top.count}x');
  }
  buf.writeln();

  // ── Errors (last 5) ──
  buf.writeln('## Errors');
  if (entries.isEmpty) {
    buf.writeln('_none_');
  } else {
    final recent = entries.reversed.take(5).toList();
    for (var i = 0; i < recent.length; i++) {
      final e = recent[i];
      buf.writeln('### ${i + 1}. ${e.error.runtimeType} (x${e.count}) — ${e.source}');
      buf.writeln('`${_oneLine(e.error.toString())}`');
      final st = e.stackTrace;
      if (st != null) {
        final frames =
            st.toString().split('\n').where((l) => l.trim().isNotEmpty).take(10);
        buf.writeln('```');
        for (final f in frames) {
          buf.writeln(f);
        }
        buf.writeln('```');
      }
    }
    if (entries.length > 5) {
      buf.writeln('_… ${entries.length - 5} more entries_');
    }
  }
  buf.writeln();

  // ── Recent HTTP ──
  buf.writeln('## Recent HTTP');
  if (http == null || http.records.isEmpty) {
    buf.writeln('_none_');
  } else {
    final recs = http.records.reversed.take(10).toList();
    for (final r in recs) {
      final err = r.error != null ? ' ERROR=${_oneLine(r.error.toString())}' : '';
      buf.writeln(
          '- ${r.method} ${r.statusCode} ${r.url} (${r.duration.inMilliseconds}ms)$err');
    }
    if (http.records.length > 10) {
      buf.writeln('_… ${http.records.length - 10} more entries_');
    }
  }
  buf.writeln();

  // ── Recent Logs ──
  buf.writeln('## Recent Logs');
  if (logger == null || logger.history.isEmpty) {
    buf.writeln('_none_');
  } else {
    final hist = logger.history.reversed.take(20).toList();
    for (final evt in hist) {
      buf.writeln('- ${_oneLine(evt.generateTextMessage())}');
    }
    if (logger.history.length > 20) {
      buf.writeln('_… ${logger.history.length - 20} more entries_');
    }
  }
  buf.writeln();

  // ── Route ──
  buf.writeln('## Route');
  buf.writeln(currentRoute ?? '_unknown_');
  buf.writeln();

  // ── App State ──
  buf.writeln('## App State');
  if (appState == null || appState.isEmpty) {
    buf.writeln('_none_');
  } else {
    try {
      buf.writeln('```json');
      buf.writeln(const JsonEncoder.withIndent('  ').convert(appState));
      buf.writeln('```');
    } catch (_) {
      buf.writeln('_unserializable_');
    }
  }

  final out = buf.toString();
  if (out.length <= _maxChars) return out;
  return '${out.substring(0, _maxChars)}\n\n_… truncated (${out.length - _maxChars} chars)_';
}

String _oneLine(String s) => s.replaceAll('\n', ' ').replaceAll('\r', '');
