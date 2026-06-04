import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class AutoFixZone extends StatelessWidget {
  const AutoFixZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Auto-Fix',
      intent:
          'An AI assistant should produce a safe patch, show a diff preview, rank by confidence, and apply on click.',
      tests: [
        TestTile(
          label: 'Refactor deeply nested widgets',
          description: 'Extract method / widget candidate.',
          builder: (_) => const _DeepNesting(),
        ),
        TestTile(
          label: 'Promote to const everywhere',
          description: 'Sweep for non-const literals.',
          builder: (_) => const _ConstSweep(),
        ),
        TestTile(
          label: 'Replace setState with ValueNotifier',
          description: 'Pattern upgrade fix.',
          builder: (_) => const _SetStateUpgrade(),
        ),
        TestTile(
          label: 'Batch-fix overflow rows',
          description: 'Multiple Row overflows on one screen.',
          builder: (_) => const _BatchOverflow(),
        ),
      ],
    );
  }
}

class _DeepNesting extends StatelessWidget {
  const _DeepNesting();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              child: const Center(child: Text('Hello from the depths')),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConstSweep extends StatelessWidget {
  const _ConstSweep();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Padding(padding: EdgeInsets.all(8), child: Text('Line 1')),
        Padding(padding: EdgeInsets.all(8), child: Text('Line 2')),
        Padding(padding: EdgeInsets.all(8), child: Text('Line 3')),
        SizedBox(height: 8),
        Icon(Icons.star),
      ],
    );
  }
}

class _SetStateUpgrade extends StatefulWidget {
  const _SetStateUpgrade();
  @override
  State<_SetStateUpgrade> createState() => _SetStateUpgradeState();
}

class _SetStateUpgradeState extends State<_SetStateUpgrade> {
  int _n = 0;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$_n', style: const TextStyle(fontSize: 48)),
          ElevatedButton(
            onPressed: () => setState(() => _n++),
            child: const Text('inc'),
          ),
        ],
      ),
    );
  }
}

class _BatchOverflow extends StatelessWidget {
  const _BatchOverflow();
  @override
  Widget build(BuildContext context) {
    Widget bad() => const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 250,
            child: Card(child: ListTile(title: Text('Wide A'))),
          ),
          SizedBox(
            width: 250,
            child: Card(child: ListTile(title: Text('Wide B'))),
          ),
        ],
      ),
    );
    return Column(children: [bad(), bad(), bad(), bad()]);
  }
}
