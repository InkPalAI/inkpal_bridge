import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InkPalBridge.dispose', () {
    test('instance is null before init (dispose is a null-safe no-op)', () {
      // Pre-init, instance is null — users should not need a guard beyond
      // `?.`. The nullable API keeps dispose side-effect-free here.
      InkPalBridge.instance?.dispose();
      // no-throw == pass
    });

    test('init() → dispose() does not throw', () {
      InkPalBridge.init(
        serverUrl: 'ws://localhost:0',
        appRunner: () {},
      );
      final bridge = InkPalBridge.instance;
      expect(bridge, isNotNull);
      expect(() => bridge!.dispose(), returnsNormally);
    });

    test('init → dispose → init → dispose loop is safe', () {
      for (var i = 0; i < 3; i++) {
        InkPalBridge.init(
          serverUrl: 'ws://localhost:0',
          appRunner: () {},
        );
        final bridge = InkPalBridge.instance;
        expect(bridge, isNotNull, reason: 'iteration $i: instance should exist');
        expect(() => bridge!.dispose(), returnsNormally,
            reason: 'iteration $i: dispose should not throw');
      }
    });

    test('double dispose() on same instance is safe', () {
      InkPalBridge.init(
        serverUrl: 'ws://localhost:0',
        appRunner: () {},
      );
      final bridge = InkPalBridge.instance!;
      bridge.dispose();
      expect(() => bridge.dispose(), returnsNormally);
    });

    test('dispose() releases the SemanticsHandle', () {
      InkPalBridge.init(
        serverUrl: 'ws://localhost:0',
        appRunner: () {},
      );
      final bridge = InkPalBridge.instance!;
      // Walker was created + ensureSemantics() called → handle acquired.
      final walker = bridge.semanticsWalker;
      expect(walker, isNotNull);
      bridge.dispose();
      // After dispose the walker field is nulled out; acquiring another
      // instance must not throw (handle was released cleanly).
      InkPalBridge.init(
        serverUrl: 'ws://localhost:0',
        appRunner: () {},
      );
      final bridge2 = InkPalBridge.instance!;
      expect(bridge2.semanticsWalker, isNotNull);
      expect(() => bridge2.dispose(), returnsNormally);
    });
  });
}
