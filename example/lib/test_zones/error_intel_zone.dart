import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class ErrorIntelZone extends StatelessWidget {
  const ErrorIntelZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Error Intel',
      intent:
          'An AI assistant should map each thrown error to a known fix, explain it in plain English, and rank the fix.',
      tests: [
        TestTile(
          label: 'Null check on null',
          description: 'Force a null assertion failure.',
          builder: (_) => const _NullCheck(),
        ),
        TestTile(
          label: 'RangeError',
          description: 'Index past list end.',
          builder: (_) => const _RangeError(),
        ),
        TestTile(
          label: 'setState after dispose',
          description: 'Common Flutter foot-gun.',
          builder: (_) => const _SetStateAfterDispose(),
        ),
        TestTile(
          label: 'Unhandled async error',
          description: 'Future throws with no catch.',
          builder: (_) => const _UnhandledAsync(),
        ),
      ],
    );
  }
}

class _NullCheck extends StatelessWidget {
  const _NullCheck();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          String? x;
          // ignore: unused_local_variable
          final y = x!.length;
        },
        child: const Text('Throw null check'),
      ),
    );
  }
}

class _RangeError extends StatelessWidget {
  const _RangeError();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          final list = <int>[1, 2, 3];
          // ignore: unused_local_variable
          final v = list[10];
        },
        child: const Text('Throw RangeError'),
      ),
    );
  }
}

class _SetStateAfterDispose extends StatefulWidget {
  const _SetStateAfterDispose();
  @override
  State<_SetStateAfterDispose> createState() => _SetStateAfterDisposeState();
}

class _SetStateAfterDisposeState extends State<_SetStateAfterDispose> {
  bool _armed = false;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () {
          _armed = true;
          Future.delayed(const Duration(seconds: 3), () {
            if (_armed) setState(() {});
          });
          Navigator.of(context).pop();
        },
        child: const Text('Arm + leave'),
      ),
    );
  }
}

class _UnhandledAsync extends StatelessWidget {
  const _UnhandledAsync();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () async {
          await Future.delayed(const Duration(milliseconds: 200));
          throw StateError('Async kaboom');
        },
        child: const Text('Throw async'),
      ),
    );
  }
}
