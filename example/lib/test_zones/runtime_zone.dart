import 'dart:async';

import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class RuntimeZone extends StatelessWidget {
  const RuntimeZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Runtime Intel',
      intent:
          'An AI assistant should inspect the live tree, watch state, trace events, and flag heavy widgets.',
      tests: [
        TestTile(
          label: 'Heavy widget',
          description: '5000-item Column. Watch frame drops.',
          builder: (_) => const _HeavyTree(),
        ),
        TestTile(
          label: 'State inspector',
          description: 'Counter + timestamp — peek at state.',
          builder: (_) => const _LiveState(),
        ),
        TestTile(
          label: 'Memory leak',
          description: 'Timer kept alive on dispose.',
          builder: (_) => const _LeakyTimer(),
        ),
        TestTile(
          label: 'Gesture conflict',
          description: 'Nested GestureDetectors — who wins?',
          builder: (_) => const _GestureConflict(),
        ),
      ],
    );
  }
}

class _HeavyTree extends StatelessWidget {
  const _HeavyTree();
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: List.generate(
          5000,
          (i) => Container(
            padding: const EdgeInsets.all(8),
            child: Text('Row $i'),
          ),
        ),
      ),
    );
  }
}

class _LiveState extends StatefulWidget {
  const _LiveState();
  @override
  State<_LiveState> createState() => _LiveStateState();
}

class _LiveStateState extends State<_LiveState> {
  int _count = 0;
  DateTime _lastTick = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _count++;
        _lastTick = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('count: $_count', style: const TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text('lastTick: ${_lastTick.toIso8601String()}'),
        ],
      ),
    );
  }
}

class _LeakyTimer extends StatefulWidget {
  const _LeakyTimer();
  @override
  State<_LeakyTimer> createState() => _LeakyTimerState();
}

class _LeakyTimerState extends State<_LeakyTimer> {
  int _ticks = 0;
  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (mounted) setState(() => _ticks++);
    });
  }

  @override
  Widget build(BuildContext context) => Center(child: Text('ticks: $_ticks'));
}

class _GestureConflict extends StatelessWidget {
  const _GestureConflict();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () => debugPrint('outer tap'),
        child: Container(
          padding: const EdgeInsets.all(40),
          color: Colors.deepPurple,
          child: GestureDetector(
            onTap: () => debugPrint('inner tap'),
            child: Container(
              padding: const EdgeInsets.all(40),
              color: Colors.amber,
              child: const Text('Tap me'),
            ),
          ),
        ),
      ),
    );
  }
}
