import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/src/communication/command_router.dart';

void main() {
  late CommandRouter router;

  setUp(() {
    router = CommandRouter();
  });

  group('CommandRouter', () {
    test('dispatches registered handler and returns JSON-RPC response', () async {
      router.register('test_method', (params) async {
        return {'echo': params['value']};
      });

      final response = await router.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'test_method',
        'params': {'value': 'hello'},
      });

      expect(response['jsonrpc'], '2.0');
      expect(response['id'], 1);
      expect((response['result'] as Map)['echo'], 'hello');
    });

    test('returns method not found for unknown command', () async {
      final response = await router.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'unknown_method',
      });

      expect(response['error'], isNotNull);
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], -32601);
      expect(error['message'], contains('Method not found'));
    });

    test('returns invalid request when no method provided', () async {
      final response = await router.handle({
        'jsonrpc': '2.0',
        'id': 1,
      });

      expect(response['error'], isNotNull);
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], -32600);
    });

    test('returns empty map for notification without id', () async {
      final response = await router.handle({
        'jsonrpc': '2.0',
        'method': 'unknown_method',
      });

      expect(response, isEmpty);
    });

    test('returns internal error when handler throws', () async {
      router.register('throws', (params) async {
        throw Exception('boom');
      });

      final response = await router.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'throws',
      });

      expect(response['error'], isNotNull);
      final error = response['error'] as Map<String, dynamic>;
      expect(error['code'], -32603);
      expect(error['message'], contains('boom'));
    });

    group('appReady gate', () {
      test('rejects non-lifecycle commands when app not ready', () async {
        router.isAppReady = () => false;
        router.register('inspect_widgets', (params) async => {'ok': true});

        final response = await router.handle({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'inspect_widgets',
        });

        expect(response['error'], isNotNull);
        final error = response['error'] as Map<String, dynamic>;
        expect(error['code'], -32002);
        expect(error['message'], contains('App not ready'));
      });

      test('allows lifecycle commands even when app not ready', () async {
        router.isAppReady = () => false;
        router.register('ping', (params) async => {'pong': true});

        final response = await router.handle({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'ping',
        });

        expect(response['result'], isNotNull);
        expect((response['result'] as Map)['pong'], true);
      });

      test('allows get_log_history when app not ready', () async {
        router.isAppReady = () => false;
        router.register('get_log_history', (params) async => {'logs': []});

        final response = await router.handle({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'get_log_history',
        });

        expect(response['result'], isNotNull);
      });

      test('allows all commands when app is ready', () async {
        router.isAppReady = () => true;
        router.register('inspect_widgets', (params) async => {'ok': true});

        final response = await router.handle({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'inspect_widgets',
        });

        expect(response['result'], isNotNull);
      });

      test('allows all commands when isAppReady is null (no gate)', () async {
        router.register('inspect_widgets', (params) async => {'ok': true});

        final response = await router.handle({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'inspect_widgets',
        });

        expect(response['result'], isNotNull);
      });
    });

    test('handler receives empty params when none provided', () async {
      late Map<String, dynamic> receivedParams;
      router.register('no_params', (params) async {
        receivedParams = params;
        return {'ok': true};
      });

      await router.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'no_params',
      });

      expect(receivedParams, isEmpty);
    });
  });
}
