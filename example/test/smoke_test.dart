import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge_example/main.dart';

void main() {
  testWidgets('ExampleApp boots and renders the counter zone',
      (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    expect(find.text('inkpal_bridge example'), findsOneWidget);
    expect(find.text('Counter: 0'), findsOneWidget);
    expect(find.text('Increment'), findsOneWidget);
    expect(find.text('Decrement'), findsOneWidget);
  });

  testWidgets('Increment button updates the counter', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Increment'));
    await tester.pump();

    expect(find.text('Counter: 1'), findsOneWidget);
  });

  testWidgets('Zone tiles navigate to the right route', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forms'));
    await tester.pumpAndSettle();
    expect(find.text('Forms'), findsWidgets);
    expect(find.byType(TextFormField), findsOneWidget);
  });
}
