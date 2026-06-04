import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class CoreDebugZone extends StatelessWidget {
  const CoreDebugZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Core Debug',
      intent:
          'Each tile is an intentional bug. An AI assistant should detect, explain, and propose a fix.',
      tests: [
        TestTile(
          label: 'Row overflow',
          description: 'Three wide buttons in a Row with no Expanded.',
          builder: (_) => const _RowOverflow(),
        ),
        TestTile(
          label: 'Column overflow',
          description: 'Fixed-height column with too many items.',
          builder: (_) => const _ColumnOverflow(),
        ),
        TestTile(
          label: 'Unbounded ListView in Column',
          description: 'Constraint mismatch — common error.',
          builder: (_) => const _UnboundedList(),
        ),
        TestTile(
          label: 'Missing const',
          description: 'Widget rebuilds that should be const.',
          builder: (_) => const _MissingConst(),
        ),
        TestTile(
          label: 'Infinite rebuild',
          description: 'setState inside build — frame loop.',
          builder: (_) => const _InfiniteRebuild(),
        ),
        TestTile(
          label: 'Async setState after dispose',
          description: 'Future completes after widget unmount.',
          builder: (_) => const _AsyncAfterDispose(),
        ),
      ],
    );
  }
}

class _RowOverflow extends StatelessWidget {
  const _RowOverflow();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: Card(child: ListTile(title: Text('One')))),
          Expanded(child: Card(child: ListTile(title: Text('Two')))),
          Expanded(child: Card(child: ListTile(title: Text('Three')))),
        ],
      ),
    );
  }
}

class _ColumnOverflow extends StatelessWidget {
  const _ColumnOverflow();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Column(
        children: List.generate(20, (i) => ListTile(title: Text('Row $i'))),
      ),
    );
  }
}

class _UnboundedList extends StatelessWidget {
  const _UnboundedList();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Header'),
        ListView(
          children: List.generate(50, (i) => ListTile(title: Text('Item $i'))),
        ),
      ],
    );
  }
}

class _MissingConst extends StatefulWidget {
  const _MissingConst();
  @override
  State<_MissingConst> createState() => _MissingConstState();
}

class _MissingConstState extends State<_MissingConst> {
  int _n = 0;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Counter: $_n'),
        SizedBox(height: 16),
        Padding(padding: EdgeInsets.all(8), child: Text('I should be const.')),
        ElevatedButton(
          onPressed: () => setState(() => _n++),
          child: Text('Tap'),
        ),
      ],
    );
  }
}

class _InfiniteRebuild extends StatefulWidget {
  const _InfiniteRebuild();
  @override
  State<_InfiniteRebuild> createState() => _InfiniteRebuildState();
}

class _InfiniteRebuildState extends State<_InfiniteRebuild> {
  int _n = 0;
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _n++);
    });
    return Center(child: Text('Rebuild #$_n'));
  }
}

class _AsyncAfterDispose extends StatefulWidget {
  const _AsyncAfterDispose();
  @override
  State<_AsyncAfterDispose> createState() => _AsyncAfterDisposeState();
}

class _AsyncAfterDisposeState extends State<_AsyncAfterDispose> {
  String _status = 'Loading...';
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 5), () {
      setState(() => _status = 'Done');
    });
  }

  @override
  Widget build(BuildContext context) => Center(child: Text(_status));
}
