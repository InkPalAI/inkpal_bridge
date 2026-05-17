// Licensed under the MIT License — see the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkpal_bridge/src/interaction/pointer_gestures.dart';

void main() {
  testWidgets('probeHit reports reachable for a painted button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(ElevatedButton));
    final outcome = PointerGestureDriver.probeHit(position: center);
    expect(outcome.reachable, isTrue);
    expect(outcome.obstructingTypes, isNotEmpty);
  });

  testWidgets('probeHit marks expected render object unreachable when a ModalBarrier covers it', (tester) async {
    const listenerKey = Key('behind');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: Listener(
                  key: listenerKey,
                  onPointerDown: (_) {},
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox(width: 120, height: 40),
                ),
              ),
              const ModalBarrier(color: Color(0xAA000000), dismissible: false),
            ],
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byKey(listenerKey));
    final expected = tester.renderObject(find.byKey(listenerKey));
    final outcome = PointerGestureDriver.probeHit(position: center, expected: expected);
    expect(outcome.reachable, isFalse,
        reason: 'ModalBarrier should absorb hits before reaching the Listener');
    expect(outcome.obstructingTypes, isNotEmpty);
  });

  // Note: the actual tap/drag dispatch path awaits frame scheduler
  // callbacks that flutter_test's fake async can't satisfy, so the
  // round-trip is exercised on a real device in integration tests, not
  // here. probeHit() is covered above — it's the non-dispatch half of
  // the API and the one most likely to regress.
}
