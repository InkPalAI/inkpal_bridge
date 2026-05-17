// Licensed under the MIT License — see the LICENSE file for details.
//
// Host-app extension points for the SemanticsWalker.
//
// The walker's Element-tree pass already surfaces widgets tagged with a
// `ValueKey<String>`, but apps often wrap Material widgets in their own
// design-system types (e.g. `AppButton`, `GlassCard`, a `GetX`-wrapped
// controller view) whose internals the walker cannot recognise as
// interactive — no ValueKey, no unique SemanticsNode label.
//
// Passing an [InkPalWalkerHooks] to [InkPalBridge.init] lets the app
// declare its own rules without forking the walker. All three callbacks
// are optional; missing callbacks fall through to the walker's built-in
// behaviour.
//
// Example:
//
//   InkPalBridge.init(
//     ...,
//     walkerHooks: InkPalWalkerHooks(
//       isInteractiveWidget: (w) => w is AppButton || w is GlassCard,
//       shouldStopTraversal: (w) => w is PaywallBoundary,
//       extractTextFrom: (w) => w is AppButton ? w.semanticLabel : null,
//     ),
//   );

import 'package:flutter/widgets.dart';

/// Returns true when the widget should be treated as interactive even if
/// its semantics don't mark it as such. Used to surface app-specific
/// design-system widgets to the agent's interaction vocabulary.
typedef InteractiveWidgetPredicate = bool Function(Widget widget);

/// Returns true when the walker should NOT descend into this widget's
/// subtree. Useful for walling off paid-tier gated areas or opaque
/// third-party render surfaces.
typedef StopTraversalPredicate = bool Function(Widget widget);

/// Returns a label to use for this widget when surfacing it to the agent.
/// Return null to fall through to the walker's default text extraction.
typedef WidgetTextExtractor = String? Function(Widget widget);

/// Bundled set of host-app hooks the walker consults during each capture.
class InkPalWalkerHooks {
  final InteractiveWidgetPredicate? isInteractiveWidget;
  final StopTraversalPredicate? shouldStopTraversal;
  final WidgetTextExtractor? extractTextFrom;

  const InkPalWalkerHooks({
    this.isInteractiveWidget,
    this.shouldStopTraversal,
    this.extractTextFrom,
  });

  /// Convenience: hooks that never claim anything — the walker runs
  /// entirely on its built-in rules. Useful as a default.
  static const InkPalWalkerHooks none = InkPalWalkerHooks();

  bool get isEmpty =>
      isInteractiveWidget == null &&
      shouldStopTraversal == null &&
      extractTextFrom == null;
}
