import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class SmartAssistZone extends StatelessWidget {
  const SmartAssistZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Smart Assist',
      intent:
          'An AI assistant should suggest UX, accessibility, responsive, and animation improvements.',
      tests: [
        TestTile(
          label: 'Missing semantics',
          description: 'IconButton without label.',
          builder: (_) => const _NoSemantics(),
        ),
        TestTile(
          label: 'Non-responsive layout',
          description: 'Fixed widths that break on narrow screens.',
          builder: (_) => const _NonResponsive(),
        ),
        TestTile(
          label: 'Hard transition',
          description: 'No animation between states.',
          builder: (_) => const _HardTransition(),
        ),
      ],
    );
  }
}

class _NoSemantics extends StatelessWidget {
  const _NoSemantics();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: IconButton(icon: const Icon(Icons.share), onPressed: () {}),
    );
  }
}

class _NonResponsive extends StatelessWidget {
  const _NonResponsive();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        width: 600,
        height: 200,
        color: Colors.teal,
        alignment: Alignment.center,
        child: const Text(
          '600px wide, sorry phones',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}

class _HardTransition extends StatefulWidget {
  const _HardTransition();
  @override
  State<_HardTransition> createState() => _HardTransitionState();
}

class _HardTransitionState extends State<_HardTransition> {
  bool _on = false;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: _on ? 200 : 80,
            height: 80,
            color: _on ? Colors.deepOrange : Colors.indigo,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => setState(() => _on = !_on),
            child: const Text('Toggle'),
          ),
        ],
      ),
    );
  }
}
