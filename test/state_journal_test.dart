import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/src/memory/state_journal.dart';

void main() {
  late StateJournal journal;

  setUp(() {
    journal = StateJournal(maxSnapshots: 5);
    journal.stateProvider = () async => {'counter': 42};
    journal.routeProvider = () => '/home';
    journal.elementCountProvider = () => 10;
  });

  tearDown(() {
    journal.dispose();
  });

  group('StateJournal', () {
    test('captures snapshot with correct data', () async {
      final snapshot = await journal.capture('manual');

      expect(snapshot, isNotNull);
      expect(snapshot!.id, 0);
      expect(snapshot.trigger, 'manual');
      expect(snapshot.route, '/home');
      expect(snapshot.state['counter'], 42);
      expect(snapshot.elementCount, 10);
    });

    test('increments snapshot IDs', () async {
      await journal.capture('first');
      await journal.capture('second');
      final third = await journal.capture('third');

      expect(third!.id, 2);
      expect(journal.length, 3);
    });

    test('returns null when no state provider', () async {
      journal.stateProvider = null;
      final snapshot = await journal.capture('manual');
      expect(snapshot, isNull);
    });

    test('returns null when disposed', () async {
      journal.dispose();
      final snapshot = await journal.capture('manual');
      expect(snapshot, isNull);
    });

    test('evicts oldest snapshot when over capacity', () async {
      for (var i = 0; i < 7; i++) {
        journal.stateProvider = () async => {'i': i};
        await journal.capture('capture_$i');
      }

      expect(journal.length, 5);
      // First two should be evicted (0, 1)
      expect(journal.snapshots.first.trigger, 'capture_2');
      expect(journal.snapshots.last.trigger, 'capture_6');
    });

    test('get() finds snapshot by ID', () async {
      await journal.capture('first');
      await journal.capture('second');

      expect(journal.get(0)?.trigger, 'first');
      expect(journal.get(1)?.trigger, 'second');
      expect(journal.get(999), isNull);
    });

    test('latest returns most recent snapshot', () async {
      expect(journal.latest, isNull);

      await journal.capture('first');
      await journal.capture('second');

      expect(journal.latest?.trigger, 'second');
    });

    test('diff() computes changes between snapshots', () async {
      journal.stateProvider = () async => {'counter': 1, 'name': 'alice'};
      await journal.capture('before');

      journal.stateProvider = () async => {'counter': 2, 'age': 30};
      journal.routeProvider = () => '/profile';
      await journal.capture('after');

      final result = journal.diff(0, 1);
      expect(result, isNotNull);
      expect(result!['routeChanged'], true);
      expect(result['routeFrom'], '/home');
      expect(result['routeTo'], '/profile');
      expect(result['changeCount'], greaterThan(0));

      final changes = result['changes'] as List;
      final keys = changes.map((c) => c['key']).toSet();
      expect(keys, contains('counter')); // changed
      expect(keys, contains('name')); // removed
      expect(keys, contains('age')); // added
    });

    test('diff() returns null for missing IDs', () async {
      expect(journal.diff(0, 1), isNull);
    });

    test('diffSummary() returns human-readable text', () async {
      journal.stateProvider = () async => {'count': 1};
      await journal.capture('before');

      journal.stateProvider = () async => {'count': 5};
      await journal.capture('after');

      final summary = journal.diffSummary(0, 1);
      expect(summary, isNotNull);
      expect(summary, contains('count'));
    });

    test('clear() removes all snapshots and resets ID', () async {
      await journal.capture('a');
      await journal.capture('b');
      journal.clear();

      expect(journal.length, 0);
      expect(journal.latest, isNull);

      // Next capture should start from ID 0
      final next = await journal.capture('c');
      expect(next!.id, 0);
    });

    test('listSnapshots() returns JSON with optional last param', () async {
      for (var i = 0; i < 3; i++) {
        await journal.capture('snap_$i');
      }

      final all = journal.listSnapshots();
      expect(all.length, 3);

      final lastTwo = journal.listSnapshots(last: 2);
      expect(lastTwo.length, 2);
      expect(lastTwo.first['trigger'], 'snap_1');
    });

    test('onSnapshot stream emits captured snapshots', () async {
      final snapshots = <String>[];
      final sub = journal.onSnapshot.listen((s) => snapshots.add(s.trigger));

      await journal.capture('first');
      await journal.capture('second');

      // Give stream time to deliver
      await Future<void>.delayed(Duration.zero);

      expect(snapshots, ['first', 'second']);
      await sub.cancel();
    });

    test('prevents reentrant capture', () async {
      journal.stateProvider = () async {
        // Simulate slow state capture
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return {'slow': true};
      };

      // Fire two captures simultaneously
      final results = await Future.wait([
        journal.capture('first'),
        journal.capture('second'),
      ]);

      // One should succeed, one should return null (reentrant guard)
      final nonNull = results.where((r) => r != null).length;
      expect(nonNull, 1);
    });
  });
}
