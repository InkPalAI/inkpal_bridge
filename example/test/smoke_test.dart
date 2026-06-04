import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge_example/main.dart';

// Give the SliverGrid enough room to lay out all 9 cards on screen so taps
// can dispatch to off-default-viewport tiles like Forms / Smart Assist / DX.
const Size _tallPhone = Size(420, 1400);

Future<void> _boot(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(_tallPhone);
  await tester.pumpWidget(const BridgeShowcaseApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('BridgeShowcaseApp boots with all 9 category cards',
      (tester) async {
    await _boot(tester);

    expect(find.text('InkPal Bridge Showcase'), findsOneWidget);
    for (final title in const [
      'Core Debug',
      'Visual Debug',
      'Auto-Fix',
      'Runtime Intel',
      'Error Intel',
      'Visual Testing',
      'DX',
      'Smart Assist',
      'Forms',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing card: $title');
    }
  });

  testWidgets('Tapping Forms card navigates into the Forms zone',
      (tester) async {
    await _boot(tester);

    await tester.tap(find.byKey(const ValueKey('zone_card_forms')));
    await tester.pumpAndSettle();

    expect(find.text('Forms & Input'), findsOneWidget);
    expect(find.text('Login form'), findsOneWidget);
    expect(find.text('Long scrolling list'), findsOneWidget);
  });

  testWidgets('Tapping Core Debug card navigates into the Core Debug zone',
      (tester) async {
    await _boot(tester);

    await tester.tap(find.byKey(const ValueKey('zone_card_core_debug')));
    await tester.pumpAndSettle();

    expect(find.text('Core Debug'), findsWidgets);
    expect(find.text('Row overflow'), findsOneWidget);
  });
}
