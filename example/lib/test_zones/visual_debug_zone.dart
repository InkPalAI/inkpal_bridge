import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class VisualDebugZone extends StatelessWidget {
  const VisualDebugZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Visual Debug',
      intent:
          'An AI assistant should screenshot, highlight problem areas, and suggest visual fixes.',
      tests: [
        TestTile(
          label: 'Text clipped',
          description: 'Long title in a too-narrow container.',
          builder: (_) => const _ClippedText(),
        ),
        TestTile(
          label: 'Misaligned column',
          description: 'Inconsistent left padding per row.',
          builder: (_) => const _Misaligned(),
        ),
        TestTile(
          label: 'Inconsistent fonts',
          description: 'Mixed font sizes/weights with no rhythm.',
          builder: (_) => const _InconsistentFonts(),
        ),
        TestTile(
          label: 'Bad contrast',
          description: 'Low-contrast text on background.',
          builder: (_) => const _BadContrast(),
        ),
        TestTile(
          label: 'Tiny tap target',
          description: 'Icon button below 48dp.',
          builder: (_) => const _TinyTap(),
        ),
      ],
    );
  }
}

class _ClippedText extends StatelessWidget {
  const _ClippedText();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(12),
        color: Colors.indigo.shade900,
        child: const Text(
          'A really long headline that absolutely will not fit',
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
    );
  }
}

class _Misaligned extends StatelessWidget {
  const _Misaligned();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Padding(padding: EdgeInsets.only(left: 8), child: Text('Item one')),
        Padding(padding: EdgeInsets.only(left: 14), child: Text('Item two')),
        Padding(padding: EdgeInsets.only(left: 11), child: Text('Item three')),
        Padding(padding: EdgeInsets.only(left: 17), child: Text('Item four')),
      ],
    );
  }
}

class _InconsistentFonts extends StatelessWidget {
  const _InconsistentFonts();
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text(
          'Title',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        Text(
          'Subtitle',
          style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
        ),
        Text('Body', style: TextStyle(fontSize: 17)),
        Text(
          'Footer',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w300),
        ),
      ],
    );
  }
}

class _BadContrast extends StatelessWidget {
  const _BadContrast();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF202020),
      alignment: Alignment.center,
      child: const Text(
        'Can you read me?',
        style: TextStyle(color: Color(0xFF2A2A2A), fontSize: 18),
      ),
    );
  }
}

class _TinyTap extends StatelessWidget {
  const _TinyTap();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 16,
          icon: const Icon(Icons.favorite),
          onPressed: () {},
        ),
      ),
    );
  }
}
