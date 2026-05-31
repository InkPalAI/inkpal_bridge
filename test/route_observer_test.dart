import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

/// Regression coverage for B2 — `getCurrentRoute` returned null after a
/// `MaterialPageRoute(builder: ...)` push because the observer skipped
/// routes whose `settings.name` was null.
void main() {
  setUp(() => InkPalNavigatorObserver.reset());
  tearDown(() => InkPalNavigatorObserver.reset());

  testWidgets('records unnamed MaterialPageRoute push via runtimeType fallback',
      (tester) async {
    final observer = InkPalNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        routes: {
          '/': (_) => const _Home(),
        },
        // Set initialRoute so `/` lands on the stack with a known name.
        initialRoute: '/',
      ),
    );
    await tester.pumpAndSettle();

    expect(InkPalNavigatorObserver.currentRoute, '/');

    // Push without a `settings.name` — this is the flow that used to be
    // dropped entirely, leaving currentRoute pointed at `/` even though
    // the user was clearly on a new screen.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const _Detail()),
    );
    await tester.pumpAndSettle();

    final current = InkPalNavigatorObserver.currentRoute;
    expect(current, isNotNull,
        reason: 'unnamed builder push must not be dropped');
    expect(current, isNot('/'),
        reason: 'currentRoute must move off the home route');
    expect(current, contains('MaterialPageRoute'),
        reason: 'fallback identifier should embed the route runtimeType');

    expect(InkPalNavigatorObserver.routeStack.length, 2);
  });

  testWidgets('pop removes the matching synthetic identifier',
      (tester) async {
    final observer = InkPalNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const _Home(),
      ),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(builder: (_) => const _Detail()),
    );
    await tester.pumpAndSettle();

    expect(InkPalNavigatorObserver.routeStack.length, 2);

    navigator.pop();
    await tester.pumpAndSettle();

    expect(InkPalNavigatorObserver.routeStack.length, 1,
        reason: 'pop should remove the synthetic identifier');
  });

  testWidgets('explicit RouteSettings.name still wins over runtimeType',
      (tester) async {
    final observer = InkPalNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const _Home(),
      ),
    );
    await tester.pumpAndSettle();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const _Detail(),
        settings: const RouteSettings(name: '/detail/42'),
      ),
    );
    await tester.pumpAndSettle();

    expect(InkPalNavigatorObserver.currentRoute, '/detail/42');
  });
}

class _Home extends StatelessWidget {
  const _Home();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('home')));
}

class _Detail extends StatelessWidget {
  const _Detail();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('detail')));
}
