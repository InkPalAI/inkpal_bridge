import 'dart:async';

import 'state_differ.dart';
import 'state_snapshot.dart';

/// Ring-buffer journal that records app state at every meaningful mutation.
///
/// The AI can:
/// - List all checkpoints (`list`)
/// - Get a specific snapshot (`get(id)`)
/// - Diff any two snapshots (`diff(fromId, toId)`)
/// - Rewind to see what the state looked like at any point
///
/// The journal auto-captures when the state provider is set and a trigger
/// fires (tap, scroll, navigation, manual). Capacity is bounded to avoid
/// memory bloat.
class StateJournal {
  final int _maxSnapshots;
  final List<StateSnapshot> _snapshots = [];
  int _nextId = 0;
  bool _disposed = false;
  bool _capturing = false;

  /// Async function that returns the current app state.
  /// Provided by the host app via InkPalBridge.init(globalStateProvider:).
  Future<Map<String, dynamic>> Function()? stateProvider;

  /// Sync function that returns the current route.
  String? Function()? routeProvider;

  /// Sync function that returns current screen element count.
  int Function()? elementCountProvider;

  /// Stream of new snapshots for subscribers (e.g. telemetry).
  Stream<StateSnapshot> get onSnapshot => _snapshotController.stream;
  final _snapshotController = StreamController<StateSnapshot>.broadcast();

  StateJournal({int maxSnapshots = 100}) : _maxSnapshots = maxSnapshots;

  /// All snapshots in chronological order.
  List<StateSnapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Number of snapshots currently stored.
  int get length => _snapshots.length;

  /// Capture a new snapshot with the given trigger label.
  ///
  /// Returns the snapshot, or null if no state provider is configured.
  Future<StateSnapshot?> capture(String trigger) async {
    if (_disposed || _capturing) return null;
    _capturing = true;
    try {
      final provider = stateProvider;
      if (provider == null) return null;

      final state = await provider();
      final snapshot = StateSnapshot(
        id: _nextId++,
        timestamp: DateTime.now().toIso8601String(),
        trigger: trigger,
        route: routeProvider?.call(),
        state: state,
        elementCount: elementCountProvider?.call() ?? 0,
      );

      _snapshots.add(snapshot);

      // Evict oldest if over capacity
      while (_snapshots.length > _maxSnapshots) {
        _snapshots.removeAt(0);
      }

      _snapshotController.add(snapshot);
      return snapshot;
    } finally {
      _capturing = false;
    }
  }

  /// Get a snapshot by ID.
  StateSnapshot? get(int id) {
    for (final s in _snapshots) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Get the most recent snapshot.
  StateSnapshot? get latest => _snapshots.isEmpty ? null : _snapshots.last;

  /// Diff two snapshots by their IDs.
  Map<String, dynamic>? diff(int fromId, int toId) {
    final from = get(fromId);
    final to = get(toId);
    if (from == null || to == null) return null;
    return StateDiffer.diff(from, to);
  }

  /// Get a human-readable summary of changes between two snapshots.
  String? diffSummary(int fromId, int toId) {
    final result = diff(fromId, toId);
    if (result == null) return null;
    return StateDiffer.summarize(result);
  }

  /// List snapshots as JSON (for MCP responses).
  List<Map<String, dynamic>> listSnapshots({int? last}) {
    final source = last != null && last < _snapshots.length
        ? _snapshots.sublist(_snapshots.length - last)
        : _snapshots;
    return source.map((s) => s.toJson()).toList();
  }

  /// Clear all snapshots.
  void clear() {
    _snapshots.clear();
    _nextId = 0;
  }

  void dispose() {
    _disposed = true;
    _snapshotController.close();
  }
}
