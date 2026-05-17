import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Bridge testing hooks', () {
    tearDown(() {
      InkPalBridge.instance?.dispose();
    });

    test('InkPalBridge.instance.router exposes a CommandRouter', () async {
      InkPalBridge.init(
        serverUrl: 'ws://localhost:0',
        appRunner: () {},
      );
      final bridge = InkPalBridge.instance!;
      final router = bridge.router;
      expect(router, isA<CommandRouter>());

      // The router is wired with real handlers — the ping lifecycle
      // command must work without a WS server.
      final response = await router.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'ping',
      });
      expect(response['id'], 1);
      expect(response['result'], isA<Map<String, dynamic>>());
    });

    test('InkPalBridge.instance.semanticsWalker is exposed', () {
      InkPalBridge.init(
        serverUrl: 'ws://localhost:0',
        appRunner: () {},
      );
      final bridge = InkPalBridge.instance!;
      expect(bridge.semanticsWalker, isA<SemanticsWalker>());
    });

    test('SemanticsWalker is re-exported from the public barrel', () {
      // The type must be referenceable purely via the top-level library
      // import — no src/ import required.
      final walker = SemanticsWalker();
      expect(walker, isA<SemanticsWalker>());
      walker.dispose();
    });

    test('CommandRouter is re-exported from the public barrel', () {
      final router = CommandRouter();
      expect(router, isA<CommandRouter>());
    });
  });
}
