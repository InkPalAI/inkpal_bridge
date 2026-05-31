/// A single point-in-time capture of app state.
///
/// Snapshots are lightweight — they store serialized state as a Map
/// plus metadata (route, timestamp, trigger). The journal keeps a
/// ring buffer of these so AI can rewind and diff.
class StateSnapshot {
  /// Unique incrementing ID within the journal.
  final int id;

  /// ISO-8601 timestamp of capture.
  final String timestamp;

  /// What triggered this snapshot (e.g. 'tap:Login', 'scroll:down', 'route:/home', 'manual').
  final String trigger;

  /// The route active when this snapshot was taken.
  final String? route;

  /// Serialized app state — whatever the app's globalStateProvider returns.
  final Map<String, dynamic> state;

  /// Screen element count at capture time (lightweight proxy for "what's visible").
  final int elementCount;

  StateSnapshot({
    required this.id,
    required this.timestamp,
    required this.trigger,
    this.route,
    required this.state,
    this.elementCount = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp,
        'trigger': trigger,
        'route': route,
        'state': state,
        'elementCount': elementCount,
      };

  factory StateSnapshot.fromJson(Map<String, dynamic> json) => StateSnapshot(
        id: json['id'] as int,
        timestamp: json['timestamp'] as String,
        trigger: json['trigger'] as String,
        route: json['route'] as String?,
        state: Map<String, dynamic>.from(json['state'] as Map),
        elementCount: json['elementCount'] as int? ?? 0,
      );
}
