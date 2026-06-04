import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'screen_context.dart';
import 'ui_element.dart';
import 'walker_hooks.dart';

/// Walks the Flutter Semantics tree to extract structured UI descriptions.
///
/// The Semantics tree is Flutter's accessibility layer — it describes what
/// is on screen in terms of labels, values, actions, and element types.
/// This class reads that tree and produces [ScreenContext] snapshots.
class SemanticsWalker {
  SemanticsHandle? _semanticsHandle;

  /// Optional host-app hooks for the Element-tree pass. When null, the
  /// walker runs entirely on built-in rules (keyed widgets only).
  final InkPalWalkerHooks? hooks;

  SemanticsWalker({this.hooks});

  /// Enable the semantics tree. Must be called once at startup.
  void ensureSemantics() {
    if (_semanticsHandle == null) {
      debugPrint('[InkPal] Enabling semantics tree');
    }
    _semanticsHandle ??= WidgetsBinding.instance.ensureSemantics();
  }

  /// Release the semantics handle.
  void dispose() {
    _semanticsHandle?.dispose();
    _semanticsHandle = null;
  }

  /// B5 fix: re-acquire semantics handle if it was detached during
  /// navigation cycles. Cheap (reference-counted inside framework).
  void _reensureSemantics() {
    // Dispose + re-acquire to force the framework to attach a fresh
    // handle to the current PipelineOwner's semantics tree.
    _semanticsHandle?.dispose();
    _semanticsHandle = WidgetsBinding.instance.ensureSemantics();
  }

  /// Capture a snapshot of the current screen's UI elements.
  ///
  /// The capture has two stages:
  /// 1. Walk the Semantics tree — picks up labels, values, actions, etc.
  /// 2. Walk the Element tree for `ValueKey<String>`-tagged widgets — picks
  ///    up structural anchors like `Scaffold(key: ValueKey('fig-2-5'))`
  ///    that don't surface as a unique SemanticsNode but matter for
  ///    AI tooling that addresses widgets by their design-system key.
  ScreenContext captureScreenContext() {
    // Re-ensure semantics ONLY if the handle was lost. The previous
    // every-call dispose+re-acquire pattern triggered Flutter's
    // `debugFrameWasSentToEngine` assertion when the capture ran outside
    // a build phase (typical for VM-service callbacks), which the bridge
    // then caught and surfaced as a Flutter error — masking real failures
    // and activating the error overlay on every tap.
    if (_semanticsHandle == null) {
      _reensureSemantics();
    }

    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) {
      debugPrint('[InkPal] captureScreenContext: no renderViews');
      return ScreenContext.empty();
    }

    // B5 fix: try all render views, not just the first — after navigation
    // cycles the active view may have shifted position in the list.
    SemanticsOwner? owner;
    for (final view in views) {
      owner = view.owner?.semanticsOwner;
      if (owner != null) break;
    }

    if (owner == null) {
      debugPrint('[InkPal] captureScreenContext: semanticsOwner is null '
          'across all ${views.length} renderViews '
          '(handle=${_semanticsHandle != null})');
    }
    final root = owner?.rootSemanticsNode;

    final elements = <UiElement>[];
    if (root != null) {
      _walkNode(root, elements, depth: 0, parentLabels: []);
    } else {
      debugPrint('[InkPal] captureScreenContext: rootSemanticsNode is null');
    }

    // Always run the keyed-element pass — it works even when the semantics
    // tree is empty (e.g. before a frame has rendered with semantics).
    _collectKeyedElements(elements);

    return ScreenContext(elements: elements, capturedAt: DateTime.now());
  }

  /// Walk the live Element tree and emit a [UiElement] for every element
  /// whose widget carries a `ValueKey<String>`.
  ///
  /// This is the only reliable way to surface structural anchors like
  /// `Scaffold(key: ValueKey('fig-2-5'))` — Scaffold itself doesn't emit
  /// a uniquely identifiable SemanticsNode, so the semantics walker can
  /// not see it.
  void _collectKeyedElements(List<UiElement> elements) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return;

    final seen = <String>{};
    final seenHook = <int>{};
    final hookIsInteractive = hooks?.isInteractiveWidget;
    final hookStop = hooks?.shouldStopTraversal;
    final hookExtract = hooks?.extractTextFrom;
    void visit(Element element) {
      final widget = element.widget;
      final key = widget.key;
      if (key is ValueKey && key.value is String) {
        final keyValue = key.value as String;
        // De-dupe — the same Element can appear if multiple visit passes
        // overlap during reassembly.
        if (seen.add(keyValue)) {
          final renderObject = element.renderObject;
          final bounds = _renderBounds(renderObject);
          elements.add(
            UiElement(
              nodeId: identityHashCode(element),
              label: keyValue,
              key: keyValue,
              type: UiElementType.keyed,
              availableActions: const [],
              bounds: bounds,
            ),
          );
        }
      }

      // Host-app hooks — surface app-specific design-system widgets that
      // don't carry a ValueKey or a unique SemanticsNode.
      if (hookIsInteractive != null && hookIsInteractive(widget)) {
        final id = identityHashCode(element);
        if (seenHook.add(id)) {
          final label = hookExtract?.call(widget) ?? widget.runtimeType.toString();
          elements.add(
            UiElement(
              nodeId: id,
              label: label,
              type: UiElementType.button,
              availableActions: const [],
              bounds: _renderBounds(element.renderObject),
            ),
          );
        }
      }

      if (hookStop != null && hookStop(widget)) return;
      element.visitChildren(visit);
    }

    try {
      visit(root);
    } catch (e) {
      debugPrint('[InkPal] keyed-element walk failed: $e');
    }
  }

  Rect _renderBounds(RenderObject? renderObject) {
    if (renderObject is RenderBox && renderObject.hasSize) {
      try {
        final topLeft = renderObject.localToGlobal(Offset.zero);
        return topLeft & renderObject.size;
      } catch (_) {
        // localToGlobal can throw if not attached to a pipeline owner.
        return Rect.zero;
      }
    }
    return Rect.zero;
  }

  /// Capture after waiting for the current frame to finish rendering.
  /// More reliable than [captureScreenContext] after navigation or state changes.
  Future<ScreenContext> captureScreenContextAsync() async {
    // Wait for the current frame to finish rendering + semantics flush.
    await SchedulerBinding.instance.endOfFrame;
    final result = captureScreenContext();
    if (result.elements.isEmpty) {
      // Retry once after another frame — semantics may lag one frame behind.
      await SchedulerBinding.instance.endOfFrame;
      return captureScreenContext();
    }
    return result;
  }

  /// Find a specific SemanticsNode by its ID.
  SemanticsNode? findNodeById(int nodeId) {
    final views = WidgetsBinding.instance.renderViews;
    if (views.isEmpty) return null;
    final owner = views.first.owner?.semanticsOwner;
    final root = owner?.rootSemanticsNode;
    if (root == null) return null;
    return _searchById(root, nodeId);
  }

  SemanticsNode? _searchById(SemanticsNode node, int targetId) {
    if (node.id == targetId) return node;
    SemanticsNode? result;
    node.visitChildren((child) {
      result ??= _searchById(child, targetId);
      return result == null;
    });
    return result;
  }

  void _walkNode(
    SemanticsNode node,
    List<UiElement> elements, {
    required int depth,
    required List<String> parentLabels,
  }) {
    final data = node.getSemanticsData();

    final label = data.label;
    final value = data.value;
    final hint = data.hint;
    final actions = data.actions;
    // ignore: deprecated_member_use
    final flags = data.flags;

    final type = _detectType(flags, actions);
    final availableActions = _extractActions(actions);

    final hasContent = label.isNotEmpty || value.isNotEmpty;
    final hasActions = availableActions.isNotEmpty;
    final isInteractive = hasActions && type != UiElementType.unknown;

    if (hasContent || isInteractive) {
      final isEnabled = !flags.containsFlag(SemanticsFlag.hasEnabledState) ||
          flags.containsFlag(SemanticsFlag.isEnabled);
      final isFocused = flags.containsFlag(SemanticsFlag.isFocused);

      bool? isChecked;
      if (flags.containsFlag(SemanticsFlag.hasCheckedState)) {
        isChecked = flags.containsFlag(SemanticsFlag.isChecked);
      } else if (flags.containsFlag(SemanticsFlag.hasToggledState)) {
        isChecked = flags.containsFlag(SemanticsFlag.isToggled);
      }

      elements.add(
        UiElement(
          nodeId: node.id,
          label: label,
          value: value.isNotEmpty ? value : null,
          hint: hint.isNotEmpty ? hint : null,
          type: type,
          availableActions: availableActions,
          parentLabels: parentLabels.length > 5
              ? parentLabels.sublist(parentLabels.length - 5)
              : parentLabels,
          bounds: node.rect,
          isEnabled: isEnabled,
          isFocused: isFocused,
          isChecked: isChecked,
        ),
      );
    }

    final childParentLabels =
        label.isNotEmpty ? [...parentLabels, label] : parentLabels;

    List<String>? siblingLabels;
    int childCount = 0;
    node.visitChildren((_) {
      childCount++;
      return true;
    });

    if (childCount > 1) {
      siblingLabels = <String>[];
      node.visitChildren((child) {
        final childData = child.getSemanticsData();
        if (childData.label.isNotEmpty) {
          siblingLabels!.add(childData.label);
        }
        return siblingLabels!.length < 10;
      });
    }

    final childContext = siblingLabels != null && siblingLabels.isNotEmpty
        ? [...childParentLabels, ...siblingLabels]
        : childParentLabels;

    node.visitChildren((child) {
      _walkNode(child, elements, depth: depth + 1, parentLabels: childContext);
      return true;
    });
  }

  UiElementType _detectType(int flags, int actions) {
    if (flags.containsFlag(SemanticsFlag.isButton)) {
      return UiElementType.button;
    }
    if (flags.containsFlag(SemanticsFlag.isTextField)) {
      return UiElementType.textField;
    }
    if (flags.containsFlag(SemanticsFlag.isHeader)) return UiElementType.header;
    if (flags.containsFlag(SemanticsFlag.isSlider)) return UiElementType.slider;
    if (flags.containsFlag(SemanticsFlag.isLink)) return UiElementType.link;
    if (flags.containsFlag(SemanticsFlag.isImage)) return UiElementType.image;

    if (flags.containsFlag(SemanticsFlag.hasCheckedState) ||
        flags.containsFlag(SemanticsFlag.hasToggledState)) {
      return UiElementType.toggle;
    }

    // Tab: selected + tappable but not a button (TabBar items)
    if (flags.containsFlag(SemanticsFlag.isSelected) &&
        actions.containsAction(SemanticsAction.tap)) {
      return UiElementType.tab;
    }

    // Dialog / AlertDialog: scopes + names a route (modal overlays)
    if (flags.containsFlag(SemanticsFlag.scopesRoute) &&
        flags.containsFlag(SemanticsFlag.namesRoute)) {
      return UiElementType.dialog;
    }

    // BottomSheet / Snackbar: dismissible overlay without route scope
    if (actions.containsAction(SemanticsAction.dismiss) &&
        !flags.containsFlag(SemanticsFlag.scopesRoute)) {
      return UiElementType.bottomSheet;
    }

    if (actions.containsAction(SemanticsAction.scrollUp) ||
        actions.containsAction(SemanticsAction.scrollDown) ||
        actions.containsAction(SemanticsAction.scrollLeft) ||
        actions.containsAction(SemanticsAction.scrollRight)) {
      return UiElementType.scrollable;
    }

    if (actions.containsAction(SemanticsAction.tap)) {
      return UiElementType.button;
    }

    return UiElementType.text;
  }

  List<String> _extractActions(int actions) {
    final result = <String>[];
    if (actions.containsAction(SemanticsAction.tap)) result.add('tap');
    if (actions.containsAction(SemanticsAction.longPress)) {
      result.add('longPress');
    }
    if (actions.containsAction(SemanticsAction.setText)) result.add('setText');
    if (actions.containsAction(SemanticsAction.scrollUp)) {
      result.add('scrollUp');
    }
    if (actions.containsAction(SemanticsAction.scrollDown)) {
      result.add('scrollDown');
    }
    if (actions.containsAction(SemanticsAction.scrollLeft)) {
      result.add('scrollLeft');
    }
    if (actions.containsAction(SemanticsAction.scrollRight)) {
      result.add('scrollRight');
    }
    if (actions.containsAction(SemanticsAction.increase)) {
      result.add('increase');
    }
    if (actions.containsAction(SemanticsAction.decrease)) {
      result.add('decrease');
    }
    if (actions.containsAction(SemanticsAction.copy)) result.add('copy');
    if (actions.containsAction(SemanticsAction.cut)) result.add('cut');
    if (actions.containsAction(SemanticsAction.paste)) result.add('paste');
    if (actions.containsAction(SemanticsAction.dismiss)) result.add('dismiss');
    if (actions.containsAction(SemanticsAction.focus)) result.add('focus');
    return result;
  }
}

/// Extension to check flags in the bitmask.
extension on int {
  bool containsFlag(SemanticsFlag flag) => this & flag.index != 0;
  bool containsAction(SemanticsAction action) => this & action.index != 0;
}
