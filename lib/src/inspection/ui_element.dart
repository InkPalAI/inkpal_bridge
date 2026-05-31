import 'dart:ui';

/// Type of UI element detected from semantics flags.
enum UiElementType {
  button,
  textField,
  header,
  slider,
  link,
  text,
  checkbox,
  toggle,
  scrollable,
  image,
  tab,
  dialog,
  alertDialog,
  bottomSheet,
  /// A widget addressed primarily by its `ValueKey<String>` — usually a
  /// structural anchor like a Figma-derived `Scaffold(key: ValueKey('fig-2-5'))`
  /// that carries no semantics label of its own.
  keyed,
  unknown,
}

/// A parsed representation of a SemanticsNode, describing a single
/// interactive or informative UI element on screen.
class UiElement {
  /// The SemanticsNode ID, used to target this element for actions.
  final int nodeId;

  /// The accessible label (button text, field label, etc.).
  final String label;

  /// Current value (text field content, slider position, etc.).
  final String? value;

  /// Accessibility hint (e.g. "Double tap to activate").
  final String? hint;

  /// Detected element type based on semantics flags.
  final UiElementType type;

  /// List of actions this element supports (tap, longPress, setText, etc.).
  final List<String> availableActions;

  /// Labels of parent and sibling nodes, used for disambiguation when
  /// multiple elements share the same label.
  final List<String> parentLabels;

  /// Bounding rectangle of the element on screen.
  final Rect bounds;

  /// Whether this element is currently enabled.
  final bool isEnabled;

  /// Whether this element is currently focused.
  final bool isFocused;

  /// Whether this element is checked (for checkboxes/toggles).
  final bool? isChecked;

  /// The `ValueKey<String>` value attached to the underlying widget, when
  /// present. Used to address structural anchors (e.g. Figma `fig-*` keys)
  /// from AI tooling.
  final String? key;

  const UiElement({
    required this.nodeId,
    required this.label,
    this.value,
    this.hint,
    required this.type,
    required this.availableActions,
    this.parentLabels = const [],
    required this.bounds,
    this.isEnabled = true,
    this.isFocused = false,
    this.isChecked,
    this.key,
  });

  /// Format this element as a human-readable string for the LLM prompt.
  String toPromptString() {
    final buffer = StringBuffer();

    final typeStr = switch (type) {
      UiElementType.button => '[Button]',
      UiElementType.textField => '[TextField]',
      UiElementType.header => '[Header]',
      UiElementType.slider => '[Slider]',
      UiElementType.link => '[Link]',
      UiElementType.checkbox => '[Checkbox]',
      UiElementType.toggle => '[Toggle]',
      UiElementType.scrollable => '[Scrollable]',
      UiElementType.image => '[Image]',
      UiElementType.tab => '[Tab]',
      UiElementType.dialog => '[Dialog]',
      UiElementType.alertDialog => '[AlertDialog]',
      UiElementType.bottomSheet => '[BottomSheet]',
      UiElementType.text => '[Text]',
      UiElementType.keyed => '[Keyed]',
      UiElementType.unknown => '',
    };

    buffer.write('$typeStr "$label"');

    if (key != null && key!.isNotEmpty) {
      buffer.write(' (key: "$key")');
    }

    if (value != null && value!.isNotEmpty) {
      buffer.write(' (value: "$value")');
    }

    if (isChecked != null) {
      buffer.write(isChecked! ? ' [checked]' : ' [unchecked]');
    }

    if (!isEnabled) {
      buffer.write(' [disabled]');
    }

    if (availableActions.isNotEmpty) {
      buffer.write(' {${availableActions.join(', ')}}');
    }

    if (parentLabels.isNotEmpty) {
      buffer.write(' in context: [${parentLabels.join(', ')}]');
    }

    return buffer.toString();
  }

  /// Serialize to JSON for WebSocket transport.
  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'label': label,
        'value': value,
        'hint': hint,
        'type': type.name,
        'actions': availableActions,
        'bounds': {
          'x': bounds.left,
          'y': bounds.top,
          'w': bounds.width,
          'h': bounds.height,
        },
        'enabled': isEnabled,
        'focused': isFocused,
        'checked': isChecked,
        'parentLabels': parentLabels,
        if (key != null) 'key': key,
      };

  @override
  String toString() =>
      'UiElement(nodeId: $nodeId, label: "$label", type: $type)';
}
