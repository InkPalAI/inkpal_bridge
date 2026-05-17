import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../telemetry/error_catcher.dart';

/// Wraps the app in a [Stack] so the error overlay survives app crashes.
/// Listens to [InkPalErrorCatcher.stream]; shows an overlay when a new
/// error arrives. Tap X to dismiss (resumes capture).
///
/// Debug builds render a compact red bar at the top with the error type +
/// message (tap to expand stack trace). Release builds render a friendly
/// "Something went wrong" card with a retry button, but only when
/// [showInRelease] is true.
class InkPalErrorBoundary extends StatefulWidget {
  const InkPalErrorBoundary({
    super.key,
    required this.child,
    required this.catcher,
    this.debugBuilder,
    this.releaseBuilder,
    this.showInRelease = false,
  });

  final Widget child;
  final InkPalErrorCatcher catcher;
  final Widget Function(
      BuildContext context, InkPalCaughtError error, VoidCallback dismiss)? debugBuilder;
  final Widget Function(BuildContext context, VoidCallback retry)? releaseBuilder;
  final bool showInRelease;

  @override
  State<InkPalErrorBoundary> createState() => _InkPalErrorBoundaryState();
}

class _InkPalErrorBoundaryState extends State<InkPalErrorBoundary> {
  StreamSubscription<InkPalCaughtError>? _sub;
  InkPalCaughtError? _active;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    _sub = widget.catcher.stream.listen((e) {
      if (!mounted) return;
      setState(() {
        _active = e;
        _expanded = false;
      });
    });
  }

  @override
  void didUpdateWidget(covariant InkPalErrorBoundary old) {
    super.didUpdateWidget(old);
    if (old.catcher != widget.catcher) {
      _sub?.cancel();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _dismiss() {
    setState(() {
      _active = null;
      _expanded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final overlay = _buildOverlay();
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (overlay != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(
              color: Colors.transparent,
              child: SafeArea(child: overlay),
            ),
          ),
      ],
    );
  }

  Widget? _buildOverlay() {
    final active = _active;
    if (active == null) return null;

    if (kReleaseMode) {
      if (!widget.showInRelease) return null;
      final builder = widget.releaseBuilder ?? _defaultReleaseBuilder;
      return builder(context, _dismiss);
    }

    final builder = widget.debugBuilder ?? _defaultDebugBuilder;
    return builder(context, active, _dismiss);
  }

  Widget _defaultDebugBuilder(
      BuildContext context, InkPalCaughtError err, VoidCallback dismiss) {
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        color: const Color(0xFFB00020),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${err.error.runtimeType} (x${err.count}) from ${err.source}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    err.error.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: _expanded ? 20 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_expanded && err.stackTrace != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      err.stackTrace.toString().split('\n').take(10).join('\n'),
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontFamily: 'monospace'),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              onPressed: dismiss,
              tooltip: 'Dismiss',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultReleaseBuilder(BuildContext context, VoidCallback retry) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Something went wrong',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(onPressed: retry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
