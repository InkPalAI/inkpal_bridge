// Licensed under the MIT License — see the LICENSE file for details.
//
// Synthetic pointer-event dispatch for widgets whose interaction can't be
// driven through the Semantics tree.
//
// The bridge's default tap path goes through SemanticsAction.tap because
// that is accessibility-correct and exercises the same codepath a screen
// reader triggers. But plenty of widgets never emit a tap Semantics node:
//   • raw `Listener` / `RawGestureDetector`
//   • custom `GestureRecognizer` sub-classes
//   • `CustomPaint` hit regions (canvas games, charts)
//   • overlay / HUD layers that intentionally skip semantics
//
// For those cases this module dispatches synthetic PointerAdded / Down /
// Up / Removed events through GestureBinding.handlePointerEvent. A
// real-user-equivalent path — frame-scheduled, hit-tested, normal gesture
// arena arbitration.
//
// Also provides a hit-test probe so callers can ask "would a tap at this
// point actually reach this RenderObject?" before dispatching, which
// catches modal barriers, IgnorePointer / AbsorbPointer, and widgets
// covered by overlays.

import 'dart:async';
import 'dart:ui' as ui show PointerChange, PointerDeviceKind;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Result of a hit-test probe.
class HitTestOutcome {
  final bool reachable;
  /// When not reachable, the chain of hit objects — top first — so callers
  /// can report "blocked by ModalBarrier" or "covered by overlay".
  final List<String> obstructingTypes;
  final String? reason;

  const HitTestOutcome({
    required this.reachable,
    this.obstructingTypes = const [],
    this.reason,
  });
}

/// Dispatches synthetic pointer events through the real gesture pipeline.
class PointerGestureDriver {
  /// Maximum interpolation step for drags in logical pixels. Smaller means
  /// smoother drags at the cost of more frames.
  static const double _kMaxDelta = 40;

  /// Probe whether a point can actually receive a tap right now. Accepts
  /// either a concrete [RenderObject] the caller expected to hit (then
  /// returns `reachable: true` only if that object is in the hit path),
  /// or no target at all (then returns `reachable` when *any* hit is
  /// registered — useful for "is the screen clickable at all").
  static HitTestOutcome probeHit({
    required Offset position,
    RenderObject? expected,
    int? viewId,
  }) {
    final result = BoxHitTestResult();
    final effectiveViewId = viewId ??
        WidgetsBinding.instance.renderViews.firstOrNull?.flutterView.viewId ??
        0;
    try {
      WidgetsBinding.instance.hitTestInView(result, position, effectiveViewId);
    } catch (e) {
      return HitTestOutcome(
        reachable: false,
        reason: 'hitTestInView threw: $e',
      );
    }
    if (result.path.isEmpty) {
      return const HitTestOutcome(
        reachable: false,
        reason: 'no hit target at the given point',
      );
    }
    final obstructing = <String>[];
    if (expected == null) {
      return HitTestOutcome(
        reachable: true,
        obstructingTypes: result.path
            .map((e) => e.target.runtimeType.toString())
            .toList(),
      );
    }
    var sawExpected = false;
    for (final entry in result.path) {
      final target = entry.target;
      if (identical(target, expected)) {
        sawExpected = true;
        break;
      }
      obstructing.add(target.runtimeType.toString());
    }
    return HitTestOutcome(
      reachable: sawExpected,
      obstructingTypes: sawExpected ? const [] : obstructing,
      reason: sawExpected
          ? null
          : 'expected RenderObject was not in the hit path — blocked by '
              '${obstructing.isNotEmpty ? obstructing.first : 'unknown'}',
    );
  }

  /// Dispatch a single-tap (down → up) at [position]. Completes once
  /// the up event has propagated.
  static Future<void> tap(Offset position, {int? viewId}) async {
    final v = viewId ??
        WidgetsBinding.instance.renderViews.firstOrNull?.flutterView.viewId ??
        0;
    _dispatch(ui.PointerChange.add, position, v);
    _dispatch(ui.PointerChange.down, position, v);
    await _nextFrame();
    _dispatch(ui.PointerChange.up, position, v);
    _dispatch(ui.PointerChange.remove, position, v);
    await _nextFrame();
  }

  /// Drag from [from] to [to] with interpolated moves every [_kMaxDelta].
  static Future<void> drag(Offset from, Offset to, {int? viewId}) async {
    final v = viewId ??
        WidgetsBinding.instance.renderViews.firstOrNull?.flutterView.viewId ??
        0;
    _dispatch(ui.PointerChange.add, from, v);
    _dispatch(ui.PointerChange.down, from, v);
    await _nextFrame();

    final delta = to - from;
    final distance = delta.distance;
    final steps = (distance / _kMaxDelta).ceil().clamp(1, 200);
    for (var i = 1; i <= steps; i++) {
      final t = i / steps;
      final point = from + delta * t;
      _dispatch(ui.PointerChange.move, point, v);
      await _nextFrame();
    }
    _dispatch(ui.PointerChange.up, to, v);
    _dispatch(ui.PointerChange.remove, to, v);
    await _nextFrame();
  }

  static void _dispatch(ui.PointerChange change, Offset p, int viewId) {
    final now = Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    GestureBinding.instance.handlePointerEvent(
      _syntheticEvent(change, p, now, viewId),
    );
  }

  static PointerEvent _syntheticEvent(
    ui.PointerChange change,
    Offset pos,
    Duration ts,
    int viewId,
  ) {
    switch (change) {
      case ui.PointerChange.add:
        return PointerAddedEvent(
          timeStamp: ts,
          position: pos,
          viewId: viewId,
          kind: ui.PointerDeviceKind.touch,
        );
      case ui.PointerChange.down:
        return PointerDownEvent(
          timeStamp: ts,
          position: pos,
          viewId: viewId,
          kind: ui.PointerDeviceKind.touch,
          pressure: 1.0,
        );
      case ui.PointerChange.move:
        return PointerMoveEvent(
          timeStamp: ts,
          position: pos,
          viewId: viewId,
          kind: ui.PointerDeviceKind.touch,
          pressure: 1.0,
        );
      case ui.PointerChange.up:
        return PointerUpEvent(
          timeStamp: ts,
          position: pos,
          viewId: viewId,
          kind: ui.PointerDeviceKind.touch,
        );
      case ui.PointerChange.remove:
        return PointerRemovedEvent(
          timeStamp: ts,
          position: pos,
          viewId: viewId,
          kind: ui.PointerDeviceKind.touch,
        );
      default:
        // Other changes (cancel, signal, panZoom*) aren't emitted by this
        // driver; fall back to a cancel event at the point.
        return PointerCancelEvent(
          timeStamp: ts,
          position: pos,
          viewId: viewId,
          kind: ui.PointerDeviceKind.touch,
        );
    }
  }

  static Future<void> _nextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => completer.complete());
    SchedulerBinding.instance.scheduleFrame();
    return completer.future;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
