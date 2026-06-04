import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class DxZone extends StatelessWidget {
  const DxZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Developer Experience',
      intent:
          'Test how the AI loop feels: chat to debug, command palette, history, sharing reports.',
      tests: [
        TestTile(
          label: 'Chat to debug a screen',
          description: 'Ask the AI: "why is this row overflowing?"',
          builder: (_) => const _ChatTarget(),
        ),
        TestTile(
          label: 'Inline error suggestion',
          description: 'Trigger error → expect inline suggestion in IDE.',
          builder: (_) => const _InlineTarget(),
        ),
        TestTile(
          label: 'Debug history',
          description: 'After several runs, view past sessions.',
          builder: (_) => const _HistoryTarget(),
        ),
      ],
    );
  }
}

class _ChatTarget extends StatelessWidget {
  const _ChatTarget();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: const [
          SizedBox(
            width: 200,
            child: Card(child: ListTile(title: Text('Card A'))),
          ),
          SizedBox(
            width: 200,
            child: Card(child: ListTile(title: Text('Card B'))),
          ),
        ],
      ),
    );
  }
}

class _InlineTarget extends StatelessWidget {
  const _InlineTarget();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () => throw StateError('Boom from DX zone'),
        child: const Text('Trigger error'),
      ),
    );
  }
}

class _HistoryTarget extends StatelessWidget {
  const _HistoryTarget();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Run the debug flow a few times, then check session history.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
