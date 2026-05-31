import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import '../inspection/semantics_walker.dart';

/// Handles scrolling to find off-screen elements.
class ScrollHandler {
  final SemanticsWalker _walker;

  /// Default cap on attempts per-scrollable, per-direction. Raised from the
  /// previous 20 because real lists often need 30+ jumps before the target
  /// scrolls into view. Stall detection still breaks the loop early when
  /// the label set stops changing, so the higher cap doesn't translate into
  /// slower scans on short lists.
  static const int _defaultMaxScrollAttempts = 50;
  static const Duration _scrollSettleDelay = Duration(milliseconds: 200);

  ScrollHandler({required SemanticsWalker walker}) : _walker = walker;

  /// Scroll to find an element with the given label.
  ///
  /// Walks every scrollable currently on screen — deepest first, outer
  /// fallback — and does a full-budget sweep down, then a full-budget
  /// sweep up on each. Innermost-first matters because list-of-cards UIs
  /// usually have the interesting scrollable nested several layers below
  /// a page-level scrollable; scrolling the outer one doesn't move the
  /// inner content at all.
  Future<SemanticsNode?> scrollToFind({
    required String label,
    int maxScrolls = _defaultMaxScrollAttempts,
  }) async {
    final scrollables = _orderedScrollables();
    if (scrollables.isEmpty) return null;

    for (final scrollableNodeId in scrollables) {
      final down = await _scrollAndSearch(
        label: label,
        scrollableNodeId: scrollableNodeId,
        action: SemanticsAction.scrollDown,
        maxScrolls: maxScrolls,
      );
      if (down != null) return down;

      final up = await _scrollAndSearch(
        label: label,
        scrollableNodeId: scrollableNodeId,
        action: SemanticsAction.scrollUp,
        maxScrolls: maxScrolls,
      );
      if (up != null) return up;
    }
    return null;
  }

  /// Return the IDs of currently-on-screen scrollables, ordered
  /// inner-most first. The walker's elements list is produced by a
  /// DFS of the semantics tree so deeper nodes appear later; we reverse
  /// to get deepest-first. De-duped because the same logical scrollable
  /// can surface twice after a semantics-tree reshuffle.
  List<int> _orderedScrollables() {
    final context = _walker.captureScreenContext();
    final seen = <int>{};
    final out = <int>[];
    for (final element in context.elements.reversed) {
      if (element.availableActions.contains('scrollDown') ||
          element.availableActions.contains('scrollUp')) {
        if (seen.add(element.nodeId)) out.add(element.nodeId);
      }
    }
    return out;
  }

  Future<SemanticsNode?> _scrollAndSearch({
    required String label,
    required int scrollableNodeId,
    required SemanticsAction action,
    required int maxScrolls,
  }) async {
    final normalizedLabel = label.toLowerCase();
    Set<String>? previousLabels;

    for (int i = 0; i < maxScrolls; i++) {
      final node = _findInCurrentTree(normalizedLabel);
      if (node != null) return node;

      var scrollableNode = _walker.findNodeById(scrollableNodeId);
      scrollableNode ??= _resolveFirstScrollableNode();
      if (scrollableNode == null) break;

      final data = scrollableNode.getSemanticsData();
      if (!_hasAction(data.actions, action)) break;

      _performAction(scrollableNode.id, action);
      await _waitForFrame();
      await Future.delayed(_scrollSettleDelay);

      final context = _walker.captureScreenContext();
      final currentLabels = <String>{
        for (final e in context.elements) e.label.toLowerCase(),
      };
      if (previousLabels != null &&
          currentLabels.length == previousLabels.length &&
          currentLabels.containsAll(previousLabels)) {
        break;
      }
      previousLabels = currentLabels;
    }

    return null;
  }

  SemanticsNode? _resolveFirstScrollableNode() {
    final context = _walker.captureScreenContext();
    final scrollable = context.firstScrollable;
    if (scrollable == null) return null;
    return _walker.findNodeById(scrollable.nodeId);
  }

  SemanticsNode? _findInCurrentTree(String normalizedLabel) {
    final context = _walker.captureScreenContext();
    for (final element in context.elements) {
      if (element.label.toLowerCase().contains(normalizedLabel)) {
        return _walker.findNodeById(element.nodeId);
      }
      if (element.hint?.toLowerCase().contains(normalizedLabel) ?? false) {
        return _walker.findNodeById(element.nodeId);
      }
    }
    return null;
  }

  bool _hasAction(int actions, SemanticsAction action) {
    return actions & action.index != 0;
  }

  void _performAction(int nodeId, SemanticsAction action) {
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) return;
    final owner = views.first.owner?.semanticsOwner;
    owner?.performAction(nodeId, action);
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
}
