import 'state_snapshot.dart';

/// Computes human-readable diffs between two [StateSnapshot]s.
///
/// Used by the AI to understand what changed between any two points
/// in time — "what did that tap actually do to the state?"
class StateDiffer {
  /// Diff two snapshots and return a structured change report.
  static Map<String, dynamic> diff(StateSnapshot before, StateSnapshot after) {
    final changes = <Map<String, dynamic>>[];

    final allKeys = <String>{
      ...before.state.keys,
      ...after.state.keys,
    };

    for (final key in allKeys) {
      final oldVal = before.state[key];
      final newVal = after.state[key];

      if (oldVal == null && newVal != null) {
        changes.add({'key': key, 'type': 'added', 'value': newVal});
      } else if (oldVal != null && newVal == null) {
        changes.add({'key': key, 'type': 'removed', 'previousValue': oldVal});
      } else if (_stringify(oldVal) != _stringify(newVal)) {
        changes.add({
          'key': key,
          'type': 'changed',
          'from': oldVal,
          'to': newVal,
        });
      }
    }

    return {
      'fromId': before.id,
      'toId': after.id,
      'fromTimestamp': before.timestamp,
      'toTimestamp': after.timestamp,
      'routeChanged': before.route != after.route,
      'routeFrom': before.route,
      'routeTo': after.route,
      'elementCountDelta': after.elementCount - before.elementCount,
      'changeCount': changes.length,
      'changes': changes,
    };
  }

  /// Produce a concise human-readable summary of changes.
  static String summarize(Map<String, dynamic> diffResult) {
    final buf = StringBuffer();
    final changes = diffResult['changes'] as List;

    if (diffResult['routeChanged'] == true) {
      buf.writeln(
          'Route: ${diffResult['routeFrom']} → ${diffResult['routeTo']}');
    }

    final delta = diffResult['elementCountDelta'] as int;
    if (delta != 0) {
      buf.writeln('Elements: ${delta > 0 ? "+$delta" : "$delta"}');
    }

    if (changes.isEmpty) {
      buf.writeln('State: no changes');
    } else {
      for (final change in changes) {
        final key = change['key'];
        switch (change['type']) {
          case 'added':
            buf.writeln('+ $key = ${_stringify(change['value'])}');
          case 'removed':
            buf.writeln('- $key (was ${_stringify(change['previousValue'])})');
          case 'changed':
            buf.writeln(
                '~ $key: ${_stringify(change['from'])} → ${_stringify(change['to'])}');
        }
      }
    }

    return buf.toString().trimRight();
  }

  static String _stringify(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return '"$value"';
    if (value is Map || value is List) return value.toString();
    return value.toString();
  }
}
