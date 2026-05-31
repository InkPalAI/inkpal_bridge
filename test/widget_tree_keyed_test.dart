import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

/// Regression coverage for B3 — `getWidgetTree` failed to surface
/// `Scaffold(key: ValueKey('fig-*'))` widgets because the semantics walker
/// only sees SemanticsNodes and Scaffold doesn't emit a unique one. The
/// fix adds an Element-tree pass that emits a [UiElementType.keyed] entry
/// for any `ValueKey<String>`-tagged widget.
void main() {
  testWidgets('walker surfaces ValueKey-tagged Scaffold by its key',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          key: ValueKey('fig-test'),
          body: Center(child: Text('hello')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final walker = SemanticsWalker()..ensureSemantics();
    final context = walker.captureScreenContext();

    final hit = context.elements.where((e) => e.key == 'fig-test').toList();
    expect(hit, isNotEmpty,
        reason: 'expected a UiElement with key "fig-test"');
    expect(hit.single.type, UiElementType.keyed);
    expect(hit.single.label, 'fig-test');

    walker.dispose();
  });

  testWidgets('multiple keyed widgets are all surfaced and de-duped',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          key: ValueKey('fig-screen'),
          body: Column(
            children: [
              SizedBox(key: ValueKey('fig-2-5'), height: 10),
              SizedBox(key: ValueKey('fig-2-6'), height: 10),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final walker = SemanticsWalker()..ensureSemantics();
    final context = walker.captureScreenContext();

    final keys = context.elements
        .where((e) => e.key != null)
        .map((e) => e.key)
        .toSet();
    expect(keys, containsAll(<String>{'fig-screen', 'fig-2-5', 'fig-2-6'}));
    walker.dispose();
  });

  testWidgets('non-string ValueKeys are ignored', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          key: const ValueKey<int>(42),
          body: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final walker = SemanticsWalker()..ensureSemantics();
    final context = walker.captureScreenContext();

    expect(
      context.elements.any((e) => e.key != null),
      isFalse,
      reason: 'only ValueKey<String> should surface as a keyed element',
    );
    walker.dispose();
  });

  testWidgets('keyed elements round-trip through toJson', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          key: ValueKey('fig-json'),
          body: SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final walker = SemanticsWalker()..ensureSemantics();
    final context = walker.captureScreenContext();

    final hit = context.elements.firstWhere((e) => e.key == 'fig-json');
    final json = hit.toJson();
    expect(json['key'], 'fig-json');
    expect(json['type'], 'keyed');
    walker.dispose();
  });
}
