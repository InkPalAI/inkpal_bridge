// Licensed under the MIT License — see the LICENSE file for details.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inkpal_bridge/src/inspection/semantics_walker.dart';
import 'package:inkpal_bridge/src/inspection/walker_hooks.dart';

class _FakeAppButton extends StatelessWidget {
  final String label;
  const _FakeAppButton({required this.label});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: 120, height: 40, child: Text(label));
}

void main() {
  testWidgets('hooks surface an app-specific widget the walker would otherwise ignore',
      (tester) async {
    final walker = SemanticsWalker(
      hooks: InkPalWalkerHooks(
        isInteractiveWidget: (w) => w is _FakeAppButton,
        extractTextFrom: (w) => w is _FakeAppButton ? w.label : null,
      ),
    );
    walker.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: _FakeAppButton(label: 'Pay now'))),
      ),
    );
    final ctx = walker.captureScreenContext();
    final labels = ctx.elements.map((e) => e.label).toList();
    walker.dispose();
    expect(labels, contains('Pay now'),
        reason: 'hooks should surface _FakeAppButton by its custom label');
  });

  testWidgets('shouldStopTraversal prevents descent into a subtree',
      (tester) async {
    var sawInner = false;
    final walker = SemanticsWalker(
      hooks: InkPalWalkerHooks(
        isInteractiveWidget: (w) {
          if (w is _FakeAppButton) sawInner = true;
          return w is _FakeAppButton;
        },
        shouldStopTraversal: (w) => w is Opacity,
      ),
    );
    walker.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Opacity(
            opacity: 0.5,
            child: _FakeAppButton(label: 'hidden'),
          ),
        ),
      ),
    );
    walker.captureScreenContext();
    walker.dispose();
    expect(sawInner, isFalse,
        reason: 'walker should stop at Opacity and never reach _FakeAppButton');
  });

  test('InkPalWalkerHooks.none has all callbacks null', () {
    expect(InkPalWalkerHooks.none.isInteractiveWidget, isNull);
    expect(InkPalWalkerHooks.none.shouldStopTraversal, isNull);
    expect(InkPalWalkerHooks.none.extractTextFrom, isNull);
    expect(InkPalWalkerHooks.none.isEmpty, isTrue);
  });
}
