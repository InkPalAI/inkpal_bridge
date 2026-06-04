import 'package:flutter/material.dart';

class ZoneScaffold extends StatelessWidget {
  const ZoneScaffold({
    super.key,
    required this.title,
    required this.intent,
    required this.tests,
  });

  final String title;
  final String intent;
  final List<TestTile> tests;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What an AI assistant should do here',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(intent),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            for (final t in tests) ...[t, const SizedBox(height: 12)],
          ],
        ),
      ),
    );
  }
}

class TestTile extends StatelessWidget {
  const TestTile({
    super.key,
    required this.label,
    required this.description,
    required this.builder,
  });

  final String label;
  final String description;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(description),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => Scaffold(
              appBar: AppBar(title: Text(label)),
              body: builder(ctx),
            ),
          ),
        ),
      ),
    );
  }
}
