import 'package:flutter/scheduler.dart';

/// Monitors frame timing and memory usage.
class PerformanceMonitor {
  final List<Duration> _frameDurations = [];
  bool _listening = false;
  bool _disposed = false;

  void start() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_disposed) return;
    for (final t in timings) {
      _frameDurations.add(t.totalSpan);
      if (_frameDurations.length > 120) _frameDurations.removeAt(0);
    }
  }

  Map<String, dynamic> getMetrics() {
    if (_frameDurations.isEmpty) {
      return {
        'avgFrameMs': '0.0',
        'jankFrames': 0,
        'totalFrames': 0,
        'fps': 'N/A',
      };
    }

    final totalMicros =
        _frameDurations.map((d) => d.inMicroseconds).reduce((a, b) => a + b);
    final avgMs = totalMicros / _frameDurations.length / 1000;
    final jankCount =
        _frameDurations.where((d) => d.inMilliseconds > 16).length;

    return {
      'avgFrameMs': avgMs.toStringAsFixed(1),
      'jankFrames': jankCount,
      'totalFrames': _frameDurations.length,
      'fps': avgMs > 0 ? (1000 / avgMs).toStringAsFixed(0) : 'N/A',
    };
  }

  void dispose() {
    _disposed = true;
    if (_listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
    _frameDurations.clear();
  }
}
