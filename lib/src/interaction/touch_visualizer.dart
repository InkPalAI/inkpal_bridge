import 'dart:async';

import 'package:flutter/material.dart';

/// Visual touch feedback overlay for AI-driven interactions.
///
/// Shows animated ripples at tap locations and directional indicators
/// when the AI scrolls — so users can SEE what the AI is doing.
///
/// Only active in debug mode. Zero overhead in release.
///
/// Usage: Wrap your root widget with [TouchVisualizerOverlay]:
/// ```dart
/// TouchVisualizerOverlay(
///   controller: bridge.touchVisualizer,
///   child: const MyApp(),
/// )
/// ```
class TouchVisualizerController {
  final _tapController = StreamController<_TapEvent>.broadcast();
  final _scrollController = StreamController<_ScrollEvent>.broadcast();

  /// Whether visual feedback is enabled.
  bool enabled = true;

  /// Show a tap ripple at the given screen coordinates.
  void showTap(Offset position, {String? label}) {
    if (!enabled) return;
    _tapController.add(_TapEvent(position: position, label: label));
  }

  /// Show a scroll indicator in the given direction.
  void showScroll(String direction) {
    if (!enabled) return;
    _scrollController.add(_ScrollEvent(direction: direction));
  }

  /// Show a long press indicator at the given screen coordinates.
  void showLongPress(Offset position, {String? label}) {
    if (!enabled) return;
    _tapController.add(_TapEvent(
      position: position,
      label: label,
      isLongPress: true,
    ));
  }

  Stream<_TapEvent> get _taps => _tapController.stream;
  Stream<_ScrollEvent> get _scrolls => _scrollController.stream;

  void dispose() {
    _tapController.close();
    _scrollController.close();
  }
}

/// Overlay widget that renders AI touch feedback on top of your app.
///
/// Place this as the outermost widget (above MaterialApp) so it can
/// render feedback on any screen.
class TouchVisualizerOverlay extends StatefulWidget {
  final TouchVisualizerController controller;
  final Widget child;

  const TouchVisualizerOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<TouchVisualizerOverlay> createState() => _TouchVisualizerOverlayState();
}

class _TouchVisualizerOverlayState extends State<TouchVisualizerOverlay> {
  final List<_ActiveRipple> _ripples = [];
  final List<_ActiveScrollIndicator> _scrollIndicators = [];
  StreamSubscription<_TapEvent>? _tapSub;
  StreamSubscription<_ScrollEvent>? _scrollSub;
  int _nextId = 0;

  @override
  void initState() {
    super.initState();
    _tapSub = widget.controller._taps.listen(_onTap);
    _scrollSub = widget.controller._scrolls.listen(_onScroll);
  }

  @override
  void didUpdateWidget(TouchVisualizerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _tapSub?.cancel();
      _scrollSub?.cancel();
      _tapSub = widget.controller._taps.listen(_onTap);
      _scrollSub = widget.controller._scrolls.listen(_onScroll);
    }
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    _scrollSub?.cancel();
    for (final r in _ripples) {
      r.timer.cancel();
    }
    for (final s in _scrollIndicators) {
      s.timer.cancel();
    }
    super.dispose();
  }

  void _onTap(_TapEvent event) {
    final id = _nextId++;
    final duration = event.isLongPress
        ? const Duration(milliseconds: 1200)
        : const Duration(milliseconds: 800);

    final timer = Timer(duration, () {
      if (mounted) {
        setState(() => _ripples.removeWhere((r) => r.id == id));
      }
    });

    setState(() {
      _ripples.add(_ActiveRipple(
        id: id,
        position: event.position,
        label: event.label,
        isLongPress: event.isLongPress,
        timer: timer,
        createdAt: DateTime.now(),
      ));
    });
  }

  void _onScroll(_ScrollEvent event) {
    final id = _nextId++;
    final timer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() => _scrollIndicators.removeWhere((s) => s.id == id));
      }
    });

    setState(() {
      _scrollIndicators.add(_ActiveScrollIndicator(
        id: id,
        direction: event.direction,
        timer: timer,
        createdAt: DateTime.now(),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        // Ripples layer — ignores all pointer events
        if (_ripples.isNotEmpty || _scrollIndicators.isNotEmpty)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TouchFeedbackPainter(
                  ripples: List.unmodifiable(_ripples),
                  scrollIndicators: List.unmodifiable(_scrollIndicators),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Internal data classes ─────────────────────────────────────────────────────

class _TapEvent {
  final Offset position;
  final String? label;
  final bool isLongPress;

  _TapEvent({
    required this.position,
    this.label,
    this.isLongPress = false,
  });
}

class _ScrollEvent {
  final String direction;
  _ScrollEvent({required this.direction});
}

class _ActiveRipple {
  final int id;
  final Offset position;
  final String? label;
  final bool isLongPress;
  final Timer timer;
  final DateTime createdAt;

  _ActiveRipple({
    required this.id,
    required this.position,
    this.label,
    this.isLongPress = false,
    required this.timer,
    required this.createdAt,
  });
}

class _ActiveScrollIndicator {
  final int id;
  final String direction;
  final Timer timer;
  final DateTime createdAt;

  _ActiveScrollIndicator({
    required this.id,
    required this.direction,
    required this.timer,
    required this.createdAt,
  });
}

// ── Custom painter for all visual feedback ────────────────────────────────────

class _TouchFeedbackPainter extends CustomPainter {
  final List<_ActiveRipple> ripples;
  final List<_ActiveScrollIndicator> scrollIndicators;

  _TouchFeedbackPainter({
    required this.ripples,
    required this.scrollIndicators,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();

    // Draw tap ripples
    for (final ripple in ripples) {
      final elapsed = now.difference(ripple.createdAt).inMilliseconds;
      final totalMs = ripple.isLongPress ? 1200.0 : 800.0;
      final progress = (elapsed / totalMs).clamp(0.0, 1.0);

      _drawTapRipple(canvas, ripple, progress);
    }

    // Draw scroll indicators
    for (final indicator in scrollIndicators) {
      final elapsed = now.difference(indicator.createdAt).inMilliseconds;
      final progress = (elapsed / 600.0).clamp(0.0, 1.0);

      _drawScrollIndicator(canvas, size, indicator, progress);
    }
  }

  void _drawTapRipple(Canvas canvas, _ActiveRipple ripple, double progress) {
    const baseColor = Color(0xFF6C5CE7); // InkPal purple
    final center = ripple.position;

    // Inner solid circle (fades out)
    final innerRadius = ripple.isLongPress ? 18.0 : 12.0;
    final innerOpacity = (1.0 - progress * 0.8).clamp(0.0, 1.0);
    final innerPaint = Paint()
      ..color = baseColor.withValues(alpha: innerOpacity * 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius, innerPaint);

    // Expanding ring
    final maxRadius = ripple.isLongPress ? 60.0 : 40.0;
    final ringRadius = innerRadius + (maxRadius - innerRadius) * progress;
    final ringOpacity = (1.0 - progress).clamp(0.0, 1.0);
    final ringPaint = Paint()
      ..color = baseColor.withValues(alpha: ringOpacity * 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, ringRadius, ringPaint);

    // Second ring (slower, thinner) for long press
    if (ripple.isLongPress) {
      final ring2Progress = (progress * 0.7).clamp(0.0, 1.0);
      final ring2Radius =
          innerRadius + (maxRadius * 1.3 - innerRadius) * ring2Progress;
      final ring2Opacity = (1.0 - ring2Progress).clamp(0.0, 1.0);
      final ring2Paint = Paint()
        ..color = baseColor.withValues(alpha: ring2Opacity * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(center, ring2Radius, ring2Paint);
    }

    // Label text
    if (ripple.label != null && progress < 0.6) {
      final textOpacity = (1.0 - progress / 0.6).clamp(0.0, 1.0);
      final textPainter = TextPainter(
        text: TextSpan(
          text: ripple.label,
          style: TextStyle(
            color: baseColor.withValues(alpha: textOpacity),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: 200);
      final textOffset = Offset(
        center.dx - textPainter.width / 2,
        center.dy - innerRadius - textPainter.height - 6,
      );
      // Background pill
      final bgRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          textOffset.dx - 6,
          textOffset.dy - 2,
          textPainter.width + 12,
          textPainter.height + 4,
        ),
        const Radius.circular(8),
      );
      canvas.drawRRect(
        bgRect,
        Paint()
          ..color = const Color(0xFF2D2D3F).withValues(alpha: textOpacity * 0.85),
      );
      textPainter.paint(canvas, textOffset);
    }
  }

  void _drawScrollIndicator(
    Canvas canvas,
    Size size,
    _ActiveScrollIndicator indicator,
    double progress,
  ) {
    const color = Color(0xFF00B894); // InkPal green
    final opacity = (1.0 - progress).clamp(0.0, 1.0);
    final paint = Paint()
      ..color = color.withValues(alpha: opacity * 0.6)
      ..style = PaintingStyle.fill;

    final arrowPaint = Paint()
      ..color = color.withValues(alpha: opacity * 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final travel = 20.0 * progress;

    switch (indicator.direction.toLowerCase()) {
      case 'up':
        _drawArrow(canvas, arrowPaint, paint,
            Offset(centerX, 40 - travel), _ArrowDir.up);
      case 'down':
        _drawArrow(canvas, arrowPaint, paint,
            Offset(centerX, size.height - 40 + travel), _ArrowDir.down);
      case 'left':
        _drawArrow(canvas, arrowPaint, paint,
            Offset(40 - travel, centerY), _ArrowDir.left);
      case 'right':
        _drawArrow(canvas, arrowPaint, paint,
            Offset(size.width - 40 + travel, centerY), _ArrowDir.right);
    }
  }

  void _drawArrow(
    Canvas canvas,
    Paint strokePaint,
    Paint fillPaint,
    Offset center,
    _ArrowDir dir,
  ) {
    // Draw a pill background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 50, height: 30),
        const Radius.circular(15),
      ),
      Paint()
        ..color = fillPaint.color.withValues(alpha: fillPaint.color.a * 0.3),
    );

    // Draw chevron arrow
    const size = 10.0;
    final path = Path();
    switch (dir) {
      case _ArrowDir.up:
        path.moveTo(center.dx - size, center.dy + size * 0.4);
        path.lineTo(center.dx, center.dy - size * 0.4);
        path.lineTo(center.dx + size, center.dy + size * 0.4);
      case _ArrowDir.down:
        path.moveTo(center.dx - size, center.dy - size * 0.4);
        path.lineTo(center.dx, center.dy + size * 0.4);
        path.lineTo(center.dx + size, center.dy - size * 0.4);
      case _ArrowDir.left:
        path.moveTo(center.dx + size * 0.4, center.dy - size);
        path.lineTo(center.dx - size * 0.4, center.dy);
        path.lineTo(center.dx + size * 0.4, center.dy + size);
      case _ArrowDir.right:
        path.moveTo(center.dx - size * 0.4, center.dy - size);
        path.lineTo(center.dx + size * 0.4, center.dy);
        path.lineTo(center.dx - size * 0.4, center.dy + size);
    }
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(_TouchFeedbackPainter oldDelegate) => true;
}

enum _ArrowDir { up, down, left, right }
