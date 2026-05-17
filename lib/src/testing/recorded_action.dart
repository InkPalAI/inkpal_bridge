/// A single recorded user/AI interaction action.
///
/// These are collected by [InteractionRecorder] and can be replayed
/// or converted into Flutter integration tests.
class RecordedAction {
  /// Incrementing ID within the recording session.
  final int id;

  /// Action type: 'tap', 'setText', 'scroll', 'navigate', 'longPress',
  /// 'goBack', 'doubleTap', 'increase', 'decrease'.
  final String type;

  /// Target label (e.g. 'Login', 'Email', 'Submit').
  final String? label;

  /// Additional parameters (e.g. text value, direction, route name).
  final Map<String, dynamic> params;

  /// Route at the time of this action.
  final String? route;

  /// ISO-8601 timestamp.
  final String timestamp;

  /// Whether the action succeeded.
  final bool success;

  /// Screen element count after the action settled.
  final int elementCountAfter;

  RecordedAction({
    required this.id,
    required this.type,
    this.label,
    this.params = const {},
    this.route,
    required this.timestamp,
    this.success = true,
    this.elementCountAfter = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        if (label != null) 'label': label,
        if (params.isNotEmpty) 'params': params,
        'route': route,
        'timestamp': timestamp,
        'success': success,
        'elementCountAfter': elementCountAfter,
      };

  factory RecordedAction.fromJson(Map<String, dynamic> json) => RecordedAction(
        id: json['id'] as int,
        type: json['type'] as String,
        label: json['label'] as String?,
        params: json['params'] != null
            ? Map<String, dynamic>.from(json['params'] as Map)
            : const {},
        route: json['route'] as String?,
        timestamp: json['timestamp'] as String,
        success: json['success'] as bool? ?? true,
        elementCountAfter: json['elementCountAfter'] as int? ?? 0,
      );

  /// Generate a Flutter integration test step for this action.
  String toTestStep() {
    switch (type) {
      case 'tap':
        return "await tester.tap(find.text('$label'));";
      case 'setText':
        final text = params['text'] ?? '';
        return "await tester.enterText(find.text('$label'), '$text');";
      case 'scroll':
        final dir = params['direction'] ?? 'down';
        final dx = dir == 'left' ? 300.0 : dir == 'right' ? -300.0 : 0.0;
        final dy = dir == 'up' ? 300.0 : dir == 'down' ? -300.0 : 0.0;
        return 'await tester.drag(find.byType(ListView), Offset($dx, $dy));';
      case 'navigate':
        final routeName = params['routeName'] ?? label ?? '/';
        return "// Navigate to '$routeName'";
      case 'longPress':
        return "await tester.longPress(find.text('$label'));";
      case 'goBack':
        return "await tester.tap(find.byTooltip('Back'));";
      default:
        return '// $type: $label ${params.isNotEmpty ? params : ""}';
    }
  }
}
