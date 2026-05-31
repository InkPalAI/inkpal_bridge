import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../inspection/semantics_walker.dart';
import '../inspection/ui_element.dart';
import 'pointer_gestures.dart';
import 'scroll_handler.dart';
import 'touch_visualizer.dart';

/// Executes actions on the live Flutter UI via the Semantics tree.
///
/// All actions are performed through [SemanticsOwner.performAction],
/// which triggers the same callbacks as real user interactions.
class ActionExecutor {
  final SemanticsWalker _walker;
  final ScrollHandler _scrollHandler;
  final TouchVisualizerController? _touchVisualizer;

  final Future<void> Function(String routeName)? onNavigateToRoute;
  final GlobalKey<NavigatorState>? navigatorKey;
  final NavigatorObserver? _navigatorObserver;
  final List<String> _knownRoutes;

  ActionExecutor({
    required SemanticsWalker walker,
    this.onNavigateToRoute,
    this.navigatorKey,
    NavigatorObserver? navigatorObserver,
    TouchVisualizerController? touchVisualizer,
    List<String> knownRoutes = const [],
  })  : _walker = walker,
        _navigatorObserver = navigatorObserver,
        _touchVisualizer = touchVisualizer,
        _knownRoutes = knownRoutes,
        _scrollHandler = ScrollHandler(walker: walker);

  NavigatorState? get _navigator =>
      navigatorKey?.currentState ?? _navigatorObserver?.navigator;

  /// Tap an element identified by its label text.
  Future<Map<String, dynamic>> tapElement(
    String label, {
    String? parentContext,
  }) async {
    final node = _findNode(label, parentContext: parentContext);
    if (node == null) {
      final scrollResult = await _scrollHandler.scrollToFind(label: label);
      if (scrollResult == null) {
        return {
          'success': false,
          'error': "Element '$label' not found on screen. "
              'Try scrolling or navigating to a different screen.',
        };
      }
      return _performTap(scrollResult, label);
    }
    return _performTap(node, label);
  }

  /// Tap at raw screen coordinates via the real gesture pipeline.
  ///
  /// Use when the widget has no Semantics handle (raw Listener, custom
  /// GestureRecognizer, CustomPaint hit regions) or when the caller
  /// already knows the exact point from a pixel-diff hotspot or Figma
  /// coordinate.
  ///
  /// Before dispatching the tap we probe the hit path and refuse to tap
  /// points that are covered by a modal barrier / IgnorePointer /
  /// AbsorbPointer, since those silently swallow the tap and look like
  /// a pipeline bug.
  Future<Map<String, dynamic>> tapAt(
    double x,
    double y, {
    bool skipHitCheck = false,
  }) async {
    final position = Offset(x, y);
    if (!skipHitCheck) {
      final probe = PointerGestureDriver.probeHit(position: position);
      if (!probe.reachable) {
        return {
          'success': false,
          'error': 'nothing at ($x, $y): ${probe.reason ?? 'no hit target'}',
          'obstructing': probe.obstructingTypes,
        };
      }
    }

    final beforeContext = _walker.captureScreenContext();
    final beforeLabels = <String>{
      for (final e in beforeContext.elements) e.label.toLowerCase(),
    };

    await PointerGestureDriver.tap(position);
    await _waitForFrame();
    await Future.delayed(const Duration(milliseconds: 300));

    final afterContext = _walker.captureScreenContext();
    final afterLabels = <String>{
      for (final e in afterContext.elements) e.label.toLowerCase(),
    };
    final addedLabels = afterLabels.difference(beforeLabels);
    final removedLabels = beforeLabels.difference(afterLabels);

    return <String, dynamic>{
      'success': true,
      'x': x,
      'y': y,
      'method': 'pointer',
      'screenChanged': addedLabels.length + removedLabels.length > 1,
      'addedLabels': addedLabels.toList(),
      'removedLabels': removedLabels.toList(),
    };
  }

  Future<Map<String, dynamic>> _performTap(
    SemanticsNode node,
    String label,
  ) async {
    var data = node.getSemanticsData();
    if (!data.actions.containsAction(SemanticsAction.tap)) {
      SemanticsNode? current = node.parent;
      SemanticsNode? tappableAncestor;
      for (int depth = 0; depth < 5 && current != null; depth++) {
        final parentData = current.getSemanticsData();
        if (parentData.actions.containsAction(SemanticsAction.tap)) {
          tappableAncestor = current;
          break;
        }
        current = current.parent;
      }
      if (tappableAncestor == null) {
        return {'success': false, 'error': "Element '$label' is not tappable."};
      }
      node = tappableAncestor;
    }

    // Visual touch feedback — show ripple at element center
    _showTapFeedback(node, label);

    final beforeContext = _walker.captureScreenContext();
    final beforeLabels = <String>{
      for (final e in beforeContext.elements) e.label.toLowerCase(),
    };

    _performAction(node.id, SemanticsAction.tap);
    await _waitForFrame();

    // Flash capture for transient feedback (snackbars/toasts).
    final flashContext = _walker.captureScreenContext();

    await Future.delayed(const Duration(milliseconds: 300));

    final afterContext = _walker.captureScreenContext();
    final afterLabels = <String>{
      for (final e in afterContext.elements) e.label.toLowerCase(),
    };
    final addedLabels = afterLabels.difference(beforeLabels);
    final removedLabels = beforeLabels.difference(afterLabels);
    final screenChanged = addedLabels.length + removedLabels.length > 1;

    final transientFeedback = _extractTransientFeedback(
      flashContext,
      beforeContext,
      afterContext,
    );

    final result = <String, dynamic>{
      'success': true,
      'tapped': label,
      'screenChanged': screenChanged,
    };
    if (!screenChanged) {
      result['hint'] =
          'Screen appears unchanged — element may be disabled or the action had no visible effect.';
    }
    if (transientFeedback != null) {
      result['feedback'] = transientFeedback;
    }
    return result;
  }

  String? _extractTransientFeedback(
    dynamic flashContext,
    dynamic beforeContext, [
    dynamic settledContext,
  ]) {
    try {
      final beforeLabels = <String>{};
      for (final e in (beforeContext as dynamic).elements) {
        beforeLabels.add((e.label as String).toLowerCase());
      }

      const transientKeywords = [
        'added',
        'removed',
        'success',
        'error',
        'failed',
        'deleted',
        'updated',
        'saved',
        'confirmed',
        'cancelled',
        'cart',
      ];

      final snapshots = [
        flashContext,
        if (settledContext != null) settledContext
      ];
      for (final snapshot in snapshots) {
        for (final e in (snapshot as dynamic).elements) {
          final label = e.label as String;
          final lower = label.toLowerCase();
          if (beforeLabels.contains(lower)) continue;
          if (transientKeywords.any((k) => lower.contains(k))) {
            return label;
          }
        }
      }
    } catch (_) {
      // Transient feedback extraction is best-effort.
    }
    return null;
  }

  /// Enter text into a text field identified by its label or hint.
  Future<Map<String, dynamic>> setText(
    String label,
    String text, {
    String? parentContext,
  }) async {
    final node = _findNode(
      label,
      parentContext: parentContext,
      preferType: UiElementType.textField,
    );
    if (node == null) {
      return {
        'success': false,
        'error': "Text field '$label' not found on screen.",
      };
    }

    final data = node.getSemanticsData();
    if (!data.actions.containsAction(SemanticsAction.setText)) {
      if (data.actions.containsAction(SemanticsAction.tap)) {
        _performAction(node.id, SemanticsAction.tap);
        await _waitForFrame();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final retryData = node.getSemanticsData();
      if (retryData.actions.containsAction(SemanticsAction.setText)) {
        _performSetText(node.id, text);
        await _waitForFrame();
        return {'success': true, 'setText': label, 'value': text};
      }

      final newNode = _findNode(
        label,
        parentContext: parentContext,
        preferType: UiElementType.textField,
      );
      if (newNode != null && newNode.id != node.id) {
        final newData = newNode.getSemanticsData();
        if (newData.actions.containsAction(SemanticsAction.setText)) {
          _performSetText(newNode.id, text);
          await _waitForFrame();
          return {'success': true, 'setText': label, 'value': text};
        }
      }

      final anyTextField = _findAnyTextField();
      if (anyTextField != null) {
        _performSetText(anyTextField.id, text);
        await _waitForFrame();
        return {'success': true, 'setText': label, 'value': text};
      }

      return {
        'success': false,
        'error': "Cannot enter text in '$label'. "
            'Try tapping it first with tap_element, then use set_text.',
      };
    }

    _performSetText(node.id, text);
    await _waitForFrame();
    return {'success': true, 'setText': label, 'value': text};
  }

  /// Scroll the current scrollable area in the given direction.
  Future<Map<String, dynamic>> scroll(String direction) async {
    final context = _walker.captureScreenContext();
    final scrollable = context.firstScrollable;

    if (scrollable == null) {
      return {
        'success': false,
        'error': 'No scrollable area found on the current screen.',
      };
    }

    final action = switch (direction.toLowerCase()) {
      'up' => SemanticsAction.scrollUp,
      'down' => SemanticsAction.scrollDown,
      'left' => SemanticsAction.scrollLeft,
      'right' => SemanticsAction.scrollRight,
      _ => null,
    };

    if (action == null) {
      return {
        'success': false,
        'error':
            "Invalid scroll direction: '$direction'. Use up, down, left, or right.",
      };
    }

    final node = _walker.findNodeById(scrollable.nodeId);
    if (node == null) {
      return {
        'success': false,
        'error': 'Scrollable element no longer available.',
      };
    }

    final data = node.getSemanticsData();
    if (!data.actions.containsAction(action)) {
      return {
        'success': false,
        'error': "Cannot scroll $direction — already at the edge.",
      };
    }

    // Visual scroll feedback
    _touchVisualizer?.showScroll(direction);

    _performAction(node.id, action);
    await _waitForFrame();
    await Future.delayed(const Duration(milliseconds: 250));
    return {'success': true, 'scrolled': direction};
  }

  /// Navigate to a named route.
  Future<Map<String, dynamic>> navigateToRoute(String routeName) async {
    final resolved = _resolveRouteName(routeName);

    if (_knownRoutes.isNotEmpty && !_knownRoutes.contains(resolved)) {
      final suggestion = _findClosestRoute(resolved);
      return {
        'success': false,
        'error': "Route '$resolved' is not a known route. "
            'Available routes: ${_knownRoutes.join(', ')}'
            '${suggestion != null ? '. Did you mean "$suggestion"?' : '.'}',
      };
    }

    if (onNavigateToRoute != null) {
      try {
        await onNavigateToRoute!(resolved);
        await _waitForFrame();
        await Future.delayed(const Duration(milliseconds: 500));
        return {'success': true, 'navigatedTo': resolved};
      } catch (e) {
        return {
          'success': false,
          'error': "Navigation to '$resolved' failed: $e.",
        };
      }
    }

    final navigator = _navigator;
    if (navigator != null) {
      try {
        unawaited(navigator.pushNamed(resolved));
        await _waitForFrame();
        await Future.delayed(const Duration(milliseconds: 500));
        return {'success': true, 'navigatedTo': resolved};
      } catch (e) {
        return {
          'success': false,
          'error': "Navigation to '$resolved' failed: $e.",
        };
      }
    }

    return {
      'success': false,
      'error':
          'Cannot navigate: no navigation handler or navigator key configured.',
    };
  }

  String _resolveRouteName(String input) {
    if (_knownRoutes.contains(input)) return input;
    final withSlash = input.startsWith('/') ? input : '/$input';
    if (_knownRoutes.contains(withSlash)) return withSlash;
    final lowerInput = withSlash.toLowerCase();
    for (final route in _knownRoutes) {
      if (route.toLowerCase() == lowerInput) return route;
    }
    return withSlash;
  }

  String? _findClosestRoute(String input) {
    if (_knownRoutes.isEmpty) return null;
    final lower = input.replaceAll('/', '').toLowerCase();
    String? best;
    int bestScore = 0;
    for (final route in _knownRoutes) {
      final routeLower = route.replaceAll('/', '').toLowerCase();
      int score = 0;
      for (int i = 0; i < lower.length && i < routeLower.length; i++) {
        if (lower[i] == routeLower[i]) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        best = route;
      }
    }
    return bestScore >= 3 ? best : null;
  }

  /// Pop the current route (go back).
  Future<Map<String, dynamic>> goBack() async {
    final navigator = _navigator;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      await _waitForFrame();
      return {'success': true, 'action': 'navigated back'};
    }

    final views = WidgetsBinding.instance.renderViews;
    if (views.isNotEmpty) {
      final owner = views.first.owner?.semanticsOwner;
      final root = owner?.rootSemanticsNode;
      if (root != null) {
        final dismissNode = _findDismissableNode(root);
        if (dismissNode != null) {
          owner!.performAction(dismissNode.id, SemanticsAction.dismiss);
          await _waitForFrame();
          return {'success': true, 'action': 'navigated back'};
        }
      }
    }

    return {
      'success': false,
      'error': 'Cannot go back — already at the root screen.',
    };
  }

  SemanticsNode? _findDismissableNode(SemanticsNode node) {
    final data = node.getSemanticsData();
    if (data.actions & SemanticsAction.dismiss.index != 0) return node;
    SemanticsNode? result;
    node.visitChildren((child) {
      result ??= _findDismissableNode(child);
      return result == null;
    });
    return result;
  }

  /// Re-capture the current screen and return a description.
  Future<Map<String, dynamic>> getScreenContent() async {
    await Future.delayed(const Duration(milliseconds: 1500));
    final context = _walker.captureScreenContext();
    return {'success': true, 'screenContent': context.toPromptString()};
  }

  /// Long press an element.
  Future<Map<String, dynamic>> longPress(
    String label, {
    String? parentContext,
  }) async {
    final node = _findNode(label, parentContext: parentContext);
    if (node == null) {
      return {
        'success': false,
        'error': "Element '$label' not found on screen.",
      };
    }

    final data = node.getSemanticsData();
    if (!data.actions.containsAction(SemanticsAction.longPress)) {
      return {
        'success': false,
        'error': "Element '$label' does not support long press.",
      };
    }

    // Visual long press feedback
    _showTapFeedback(node, label, isLongPress: true);

    _performAction(node.id, SemanticsAction.longPress);
    await _waitForFrame();
    return {'success': true, 'longPressed': label};
  }

  /// Increase the value of a slider/stepper.
  Future<Map<String, dynamic>> increaseValue(String label) async {
    final found = _findNodeWithAction(label, SemanticsAction.increase);
    if (found != null) {
      _performAction(found.id, SemanticsAction.increase);
      await _waitForFrame();
      return {'success': true, 'increased': label};
    }

    final fallback = _findStepperButton(label, isIncrease: true);
    if (fallback != null) {
      _performAction(fallback.id, SemanticsAction.tap);
      await _waitForFrame();
      await Future.delayed(const Duration(milliseconds: 300));
      return {'success': true, 'increased': label, 'via': 'tap_fallback'};
    }

    return {
      'success': false,
      'error': "Element '$label' does not support increase.",
    };
  }

  /// Decrease the value of a slider/stepper.
  Future<Map<String, dynamic>> decreaseValue(String label) async {
    final found = _findNodeWithAction(label, SemanticsAction.decrease);
    if (found != null) {
      _performAction(found.id, SemanticsAction.decrease);
      await _waitForFrame();
      return {'success': true, 'decreased': label};
    }

    final fallback = _findStepperButton(label, isIncrease: false);
    if (fallback != null) {
      _performAction(fallback.id, SemanticsAction.tap);
      await _waitForFrame();
      await Future.delayed(const Duration(milliseconds: 300));
      return {'success': true, 'decreased': label, 'via': 'tap_fallback'};
    }

    return {
      'success': false,
      'error': "Element '$label' does not support decrease.",
    };
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Trigger visual feedback at the center of a semantics node.
  void _showTapFeedback(SemanticsNode node, String label, {bool isLongPress = false}) {
    if (_touchVisualizer == null) return;
    final rect = node.rect;
    final transform = node.transform;
    // Convert local rect center to global coordinates
    var center = rect.center;
    if (transform != null) {
      final global = MatrixUtils.transformPoint(transform, center);
      center = global;
    }
    if (isLongPress) {
      _touchVisualizer!.showLongPress(center, label: label);
    } else {
      _touchVisualizer!.showTap(center, label: label);
    }
  }

  SemanticsNode? _findNodeWithAction(String label, SemanticsAction action) {
    final context = _walker.captureScreenContext();
    final normalizedLabel = label.toLowerCase();

    final matches = context.elements
        .where((e) => e.label.toLowerCase().contains(normalizedLabel))
        .toList();

    for (final match in matches) {
      final node = _walker.findNodeById(match.nodeId);
      if (node == null) continue;
      final data = node.getSemanticsData();
      if (data.actions.containsAction(action)) return node;
    }

    for (final match in matches) {
      final node = _walker.findNodeById(match.nodeId);
      if (node == null) continue;
      SemanticsNode? current = node.parent;
      for (int depth = 0; depth < 3 && current != null; depth++) {
        final data = current.getSemanticsData();
        if (data.actions.containsAction(action)) return current;
        current = current.parent;
      }
    }

    for (final element in context.elements) {
      final node = _walker.findNodeById(element.nodeId);
      if (node == null) continue;
      final data = node.getSemanticsData();
      if (data.actions.containsAction(action)) return node;
    }

    return null;
  }

  SemanticsNode? _findStepperButton(String label, {required bool isIncrease}) {
    final context = _walker.captureScreenContext();

    final patterns = isIncrease
        ? const ['increase quantity', 'increase', '+', 'plus', 'add']
        : const [
            'decrease quantity',
            'decrease',
            '-',
            'minus',
            'subtract',
            'remove',
          ];

    for (final element in context.elements) {
      final lower = element.label.toLowerCase().trim();
      if (lower.isEmpty) continue;
      final matches = patterns.any((p) => lower == p || lower.contains(p));
      if (!matches) continue;
      final node = _walker.findNodeById(element.nodeId);
      if (node == null) continue;
      final data = node.getSemanticsData();
      if (data.actions.containsAction(SemanticsAction.tap)) return node;
    }

    // Pass 2: positional search for unlabeled +/- buttons near number values.
    final normalizedLabel = label.toLowerCase();
    final numberElements = <UiElement>[];
    final emptyLabelButtons = <UiElement>[];

    for (final element in context.elements) {
      final lower = element.label.toLowerCase().trim();
      if (lower.isNotEmpty && RegExp(r'^\d+$').hasMatch(lower)) {
        final isNearTarget = element.parentLabels.any(
          (p) => p.toLowerCase().contains(normalizedLabel),
        );
        if (isNearTarget) numberElements.add(element);
      }
      if (lower.isEmpty && element.availableActions.contains('tap')) {
        emptyLabelButtons.add(element);
      }
    }

    for (final numEl in numberElements) {
      final numY = numEl.bounds.center.dy;
      final numX = numEl.bounds.center.dx;

      final nearby = emptyLabelButtons.where((btn) {
        final dy = (btn.bounds.center.dy - numY).abs();
        return dy < 40;
      }).toList();

      if (nearby.isEmpty) continue;
      nearby.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

      final candidates = isIncrease
          ? nearby.where((btn) => btn.bounds.center.dx > numX)
          : nearby.where((btn) => btn.bounds.center.dx < numX);

      if (candidates.isNotEmpty) {
        final target = isIncrease ? candidates.first : candidates.last;
        final node = _walker.findNodeById(target.nodeId);
        if (node != null) return node;
      }
    }

    return null;
  }

  SemanticsNode? _findNode(
    String label, {
    String? parentContext,
    UiElementType? preferType,
  }) {
    final context = _walker.captureScreenContext();
    final normalizedLabel = label.toLowerCase();

    var matches = context.elements.where(
      (e) => e.label.toLowerCase().contains(normalizedLabel),
    );

    if (preferType != null) {
      final typed = matches.where((e) => e.type == preferType);
      if (typed.isNotEmpty) matches = typed;
    }

    final matchList = matches.toList();
    if (matchList.isEmpty) {
      final hintMatches = context.elements
          .where(
            (e) => e.hint?.toLowerCase().contains(normalizedLabel) ?? false,
          )
          .toList();
      if (hintMatches.isNotEmpty) {
        return _walker.findNodeById(hintMatches.first.nodeId);
      }

      if (label.length <= 2 && parentContext != null) {
        final normalizedParent = parentContext.toLowerCase();
        final parentMatches = context.elements.where(
          (e) => e.label.toLowerCase().contains(normalizedParent),
        );
        if (parentMatches.isNotEmpty) {
          final parentEl = parentMatches.first;
          final parentY = parentEl.bounds.center.dy;
          final nearbyButtons = context.elements.where((e) {
            if (e.label.isNotEmpty) return false;
            if (!e.availableActions.contains('tap')) return false;
            final dy = (e.bounds.center.dy - parentY).abs();
            return dy < 60;
          }).toList();

          if (nearbyButtons.isNotEmpty) {
            nearbyButtons.sort(
              (a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx),
            );
            final target = (label == '+' || label == 'plus')
                ? nearbyButtons.last
                : nearbyButtons.first;
            return _walker.findNodeById(target.nodeId);
          }
        }
      }

      return null;
    }

    if (matchList.length == 1) {
      return _walker.findNodeById(matchList.first.nodeId);
    }

    if (parentContext != null) {
      final normalizedParent = parentContext.toLowerCase();

      final exactMatch = matchList.where(
        (e) => e.parentLabels.any((p) => p.toLowerCase() == normalizedParent),
      );
      if (exactMatch.isNotEmpty) {
        return _walker.findNodeById(exactMatch.first.nodeId);
      }

      final substringMatch = matchList.where(
        (e) => e.parentLabels.any(
          (p) => p.toLowerCase().contains(normalizedParent),
        ),
      );
      if (substringMatch.isNotEmpty) {
        return _walker.findNodeById(substringMatch.first.nodeId);
      }
    }

    final interactive = matchList.where((e) => e.availableActions.isNotEmpty);
    if (interactive.isNotEmpty) {
      return _walker.findNodeById(interactive.first.nodeId);
    }

    return _walker.findNodeById(matchList.first.nodeId);
  }

  SemanticsNode? _findAnyTextField() {
    final context = _walker.captureScreenContext();
    final textFields = context.elements
        .where((e) => e.type == UiElementType.textField)
        .toList();
    if (textFields.isEmpty) return null;

    SemanticsNode? bestNode;
    for (final tf in textFields) {
      final node = _walker.findNodeById(tf.nodeId);
      if (node == null) continue;
      final data = node.getSemanticsData();
      if (!data.actions.containsAction(SemanticsAction.setText)) continue;
      // ignore: deprecated_member_use
      final isFocused = data.hasFlag(SemanticsFlag.isFocused);
      if (isFocused) return node;
      bestNode = node;
    }

    return bestNode;
  }

  void _performAction(int nodeId, SemanticsAction action) {
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) return;
    final owner = views.first.owner?.semanticsOwner;
    owner?.performAction(nodeId, action);
  }

  void _performSetText(int nodeId, String text) {
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) return;
    final owner = views.first.owner?.semanticsOwner;
    owner?.performAction(nodeId, SemanticsAction.setText, text);
  }

  Future<void> _waitForFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete();
      },
    );
  }

  // ── New actions (v1.14) ───────────────────────────────────────────────────

  /// Double-tap an element by performing two rapid SemanticsAction.tap calls.
  Future<Map<String, dynamic>> doubleTap(
    String label, {
    String? parentContext,
  }) async {
    final node = _findNode(label, parentContext: parentContext);
    if (node == null) {
      return {'success': false, 'error': "Element '$label' not found for double-tap"};
    }
    _performAction(node.id, SemanticsAction.tap);
    await Future.delayed(const Duration(milliseconds: 80));
    _performAction(node.id, SemanticsAction.tap);
    await _waitForFrame();
    return {'success': true, 'doubleTapped': label};
  }

  /// Check or uncheck a checkbox by tapping it if its current state differs.
  Future<Map<String, dynamic>> setCheckbox(
    String label,
    bool checked, {
    String? parentContext,
  }) async {
    final node = _findNode(label, parentContext: parentContext);
    if (node == null) {
      return {'success': false, 'error': "Checkbox '$label' not found"};
    }
    // ignore: deprecated_member_use
    final isChecked = node.hasFlag(SemanticsFlag.isChecked);
    if (isChecked == checked) {
      return {'success': true, 'label': label, 'state': checked, 'changed': false};
    }
    _performAction(node.id, SemanticsAction.tap);
    await _waitForFrame();
    return {'success': true, 'label': label, 'state': checked, 'changed': true};
  }

  /// Step a slider toward [targetValue] (0.0–1.0) using increase/decrease actions.
  Future<Map<String, dynamic>> setSliderValue(
    String label,
    double targetValue,
  ) async {
    if (targetValue < 0.0 || targetValue > 1.0) {
      return {'success': false, 'error': 'targetValue must be between 0.0 and 1.0'};
    }
    final node = _findNodeWithAction(label, SemanticsAction.increase);
    if (node == null) {
      return {'success': false, 'error': "Slider '$label' not found or not adjustable"};
    }

    // Parse current value from semantics (may be "0.5", "50%", or empty)
    double currentValue = 0.5;
    final valueStr = node.value;
    if (valueStr.isNotEmpty) {
      final isPercent = valueStr.contains('%');
      final parsed = double.tryParse(valueStr.replaceAll('%', '').trim());
      if (parsed != null) currentValue = isPercent ? parsed / 100.0 : parsed;
    }

    const maxSteps = 20;
    const stepSize = 1.0 / maxSteps;
    final diff  = targetValue - currentValue;
    final steps = (diff / stepSize).round().abs().clamp(0, maxSteps);
    final action = diff > 0 ? SemanticsAction.increase : SemanticsAction.decrease;

    for (int i = 0; i < steps; i++) {
      _performAction(node.id, action);
      await Future.delayed(const Duration(milliseconds: 50));
    }
    await _waitForFrame();
    return {'success': true, 'slider': label, 'target': targetValue, 'steps': steps};
  }

  /// Scroll until element with [label] is visible, up to [maxAttempts] scrolls.
  Future<Map<String, dynamic>> scrollToFind(
    String label, {
    String direction = 'down',
    int maxAttempts = 10,
  }) async {
    for (int i = 0; i < maxAttempts; i++) {
      final node = _findNode(label);
      if (node != null) {
        return {'success': true, 'found': true, 'swipes': i, 'label': label};
      }
      await scroll(direction);
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return {'success': false, 'found': false, 'swipes': maxAttempts, 'label': label};
  }
}

extension on int {
  bool containsAction(SemanticsAction action) => this & action.index != 0;
}
