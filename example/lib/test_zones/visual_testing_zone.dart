import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class VisualTestingZone extends StatelessWidget {
  const VisualTestingZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Visual Testing',
      intent:
          'An AI assistant should snapshot, diff across versions/devices, and detect regressions.',
      tests: [
        TestTile(
          label: 'Stable card (golden)',
          description: 'Use as a baseline snapshot.',
          builder: (_) => const _StableCard(),
        ),
        TestTile(
          label: 'Card v2 (color drift)',
          description: 'Same card, slightly different color.',
          builder: (_) => const _DriftedCard(),
        ),
        TestTile(
          label: 'Responsive form',
          description: 'Test layout across phone/tablet widths.',
          builder: (_) => const _ResponsiveForm(),
        ),
      ],
    );
  }
}

class _StableCard extends StatelessWidget {
  const _StableCard();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        color: const Color(0xFF1E88E5),
        child: const SizedBox(
          width: 240,
          height: 120,
          child: Center(
            child: Text(
              'Snapshot v1',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _DriftedCard extends StatelessWidget {
  const _DriftedCard();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        color: const Color(0xFF1976D2),
        child: const SizedBox(
          width: 240,
          height: 120,
          child: Center(
            child: Text(
              'Snapshot v2',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResponsiveForm extends StatelessWidget {
  const _ResponsiveForm();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) {
          final twoCol = c.maxWidth >= 600;
          final fields = [
            const TextField(decoration: InputDecoration(labelText: 'Name')),
            const TextField(decoration: InputDecoration(labelText: 'Email')),
            const TextField(decoration: InputDecoration(labelText: 'Phone')),
            const TextField(decoration: InputDecoration(labelText: 'City')),
          ];
          if (!twoCol) {
            return Column(
              children: [
                for (final f in fields)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12), child: f),
              ],
            );
          }
          return GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 5,
            children: fields,
          );
        },
      ),
    );
  }
}
