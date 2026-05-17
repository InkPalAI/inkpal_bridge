// Licensed under the MIT License — see the LICENSE file for details.

import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  setUp(InkPalAppExtensions.resetForTests);
  tearDown(InkPalAppExtensions.resetForTests);

  test('rejects empty or invalid names', () {
    expect(
      () => InkPalAppExtensions.register(
        name: '',
        description: 'anything',
        handler: (_) async => {},
      ),
      throwsArgumentError,
    );
    expect(
      () => InkPalAppExtensions.register(
        name: '123start',
        description: 'anything',
        handler: (_) async => {},
      ),
      throwsArgumentError,
    );
    expect(
      () => InkPalAppExtensions.register(
        name: 'with spaces',
        description: 'anything',
        handler: (_) async => {},
      ),
      throwsArgumentError,
    );
    expect(
      () => InkPalAppExtensions.register(
        name: 'has.dot',
        description: 'anything',
        handler: (_) async => {},
      ),
      throwsArgumentError,
    );
  });

  test('rejects duplicate registration', () {
    InkPalAppExtensions.register(
      name: 'resetOnboarding',
      description: 'one',
      handler: (_) async => {'ok': true},
    );
    expect(
      () => InkPalAppExtensions.register(
        name: 'resetOnboarding',
        description: 'two',
        handler: (_) async => {},
      ),
      throwsArgumentError,
    );
  });

  test('register/unregister round trip', () {
    expect(InkPalAppExtensions.registeredCount, 0);
    InkPalAppExtensions.register(
      name: 'ping',
      description: 'test ping',
      handler: (_) async => {'pong': true},
    );
    expect(InkPalAppExtensions.registeredCount, 1);
    expect(InkPalAppExtensions.unregister('ping'), isTrue);
    expect(InkPalAppExtensions.unregister('ping'), isFalse);
    expect(InkPalAppExtensions.registeredCount, 0);
  });

  test('accepts a-zA-Z0-9_ names', () {
    InkPalAppExtensions.register(
      name: 'validName_withUnderscores2',
      description: 'ok',
      handler: (_) async => {},
    );
    expect(InkPalAppExtensions.registeredCount, 1);
  });

  test('meta install is idempotent', () {
    InkPalAppExtensions.installMetaExtensions();
    // Second call should not throw even though the first registered the
    // meta extensions with the VM.
    InkPalAppExtensions.installMetaExtensions();
  });
}
