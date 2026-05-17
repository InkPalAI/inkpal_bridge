import 'screen_context.dart';
import 'ui_element.dart';

/// Compares two screen captures to detect layout changes.
///
/// Used by OBSERVE domain to tell the AI exactly what changed on screen
/// after an action — new elements, removed elements, moved elements,
/// text changes, and structural shifts.
class LayoutDiffer {
  /// Diff two screen contexts and return a structured change report.
  static Map<String, dynamic> diff(ScreenContext before, ScreenContext after) {
    final beforeMap = <int, UiElement>{
      for (final e in before.elements) e.nodeId: e,
    };
    final afterMap = <int, UiElement>{
      for (final e in after.elements) e.nodeId: e,
    };

    final added = <Map<String, dynamic>>[];
    final removed = <Map<String, dynamic>>[];
    final changed = <Map<String, dynamic>>[];

    // Find added and changed elements
    for (final entry in afterMap.entries) {
      final id = entry.key;
      final afterEl = entry.value;

      if (!beforeMap.containsKey(id)) {
        added.add({
          'nodeId': id,
          'label': afterEl.label,
          'type': afterEl.type.name,
          'bounds': _boundsToJson(afterEl),
        });
      } else {
        final beforeEl = beforeMap[id]!;
        final changes = _elementDiff(beforeEl, afterEl);
        if (changes.isNotEmpty) {
          changed.add({
            'nodeId': id,
            'label': afterEl.label,
            'type': afterEl.type.name,
            'changes': changes,
          });
        }
      }
    }

    // Find removed elements
    for (final entry in beforeMap.entries) {
      if (!afterMap.containsKey(entry.key)) {
        removed.add({
          'nodeId': entry.key,
          'label': entry.value.label,
          'type': entry.value.type.name,
        });
      }
    }

    return {
      'elementsBefore': before.elements.length,
      'elementsAfter': after.elements.length,
      'added': added,
      'removed': removed,
      'changed': changed,
      'addedCount': added.length,
      'removedCount': removed.length,
      'changedCount': changed.length,
      'hasChanges': added.isNotEmpty || removed.isNotEmpty || changed.isNotEmpty,
    };
  }

  /// Produce a concise human-readable summary.
  static String summarize(Map<String, dynamic> diffResult) {
    final buf = StringBuffer();

    final addedCount = diffResult['addedCount'] as int;
    final removedCount = diffResult['removedCount'] as int;
    final changedCount = diffResult['changedCount'] as int;

    if (addedCount == 0 && removedCount == 0 && changedCount == 0) {
      return 'No layout changes detected.';
    }

    if (addedCount > 0) {
      buf.writeln('+ $addedCount element(s) appeared:');
      for (final item in diffResult['added'] as List) {
        buf.writeln('  + ${item['type']}: "${item['label']}"');
      }
    }

    if (removedCount > 0) {
      buf.writeln('- $removedCount element(s) disappeared:');
      for (final item in diffResult['removed'] as List) {
        buf.writeln('  - ${item['type']}: "${item['label']}"');
      }
    }

    if (changedCount > 0) {
      buf.writeln('~ $changedCount element(s) changed:');
      for (final item in diffResult['changed'] as List) {
        final changes = item['changes'] as List;
        buf.writeln('  ~ "${item['label']}": ${changes.join(', ')}');
      }
    }

    return buf.toString().trimRight();
  }

  static List<String> _elementDiff(UiElement before, UiElement after) {
    final changes = <String>[];

    if (before.label != after.label) {
      changes.add('label: "${before.label}" → "${after.label}"');
    }

    if (before.type != after.type) {
      changes.add('type: ${before.type.name} → ${after.type.name}');
    }

    // Bounds shift detection (moved or resized)
    final bBounds = before.bounds;
    final aBounds = after.bounds;
    if ((bBounds.left - aBounds.left).abs() > 2 ||
        (bBounds.top - aBounds.top).abs() > 2) {
      changes.add('moved: (${bBounds.left.round()},${bBounds.top.round()}) → (${aBounds.left.round()},${aBounds.top.round()})');
    }
    if ((bBounds.width - aBounds.width).abs() > 2 ||
        (bBounds.height - aBounds.height).abs() > 2) {
      changes.add('resized: ${bBounds.width.round()}x${bBounds.height.round()} → ${aBounds.width.round()}x${aBounds.height.round()}');
    }

    return changes;
  }

  static Map<String, double> _boundsToJson(UiElement el) => {
        'left': el.bounds.left,
        'top': el.bounds.top,
        'width': el.bounds.width,
        'height': el.bounds.height,
      };
}
