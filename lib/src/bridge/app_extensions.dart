// Licensed under the MIT License — see the LICENSE file for details.
//
// App-side extension registry.
//
// Lets the host app register its own VM service extensions and have them
// enumerated + invoked through the bridge without the core bridge shipping
// a new release for every new app-specific operation.
//
// Example:
//
//   InkPalAppExtensions.register(
//     name: 'resetOnboarding',
//     description: 'Wipe the onboarding flag and restart the app',
//     handler: (params) async {
//       await prefs.remove('onboarding_seen');
//       return {'ok': true};
//     },
//   );
//
// On the MCP side:
//   inkpal_list_app_extensions  → [{name, description, schema?}]
//   inkpal_call_app_extension { name, params? }  → whatever the handler returned
//
// Namespaced under `ext.flutter.inkpal.app.<name>` so nothing can collide
// with the core bridge extensions that live directly under
// `ext.flutter.inkpal.*`.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

/// A handler registered by the host app. Params arrive as string/string
/// (VM service extension contract); the handler returns any JSON-encodable
/// map as the result.
typedef InkPalAppExtensionHandler = FutureOr<Map<String, Object?>> Function(
  Map<String, String> params,
);

class _RegisteredExtension {
  final String name;
  final String description;
  final Map<String, Object?>? schema;
  final InkPalAppExtensionHandler handler;

  _RegisteredExtension({
    required this.name,
    required this.description,
    required this.handler,
    this.schema,
  });
}

/// Registry for app-provided VM service extensions.
///
/// The registry itself is installed once by the bridge's boot sequence and
/// exposes two meta-extensions (`list` + `call`) so the MCP side can
/// enumerate and invoke whatever the app registered.
class InkPalAppExtensions {
  InkPalAppExtensions._();

  static final Map<String, _RegisteredExtension> _extensions = {};
  static bool _metaRegistered = false;

  /// Valid name shape — reverse-DNS-friendly, keeps URL-safe, no dots so
  /// the VM service method stays one segment under `app.`.
  static final RegExp _namePattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');

  /// Register an app extension under `ext.flutter.inkpal.app.<name>`.
  ///
  /// Throws [ArgumentError] when the name is empty, collides with an
  /// already-registered extension, or uses characters outside
  /// `[a-zA-Z0-9_]`.
  static void register({
    required String name,
    required String description,
    required InkPalAppExtensionHandler handler,
    Map<String, Object?>? schema,
  }) {
    if (!_namePattern.hasMatch(name)) {
      throw ArgumentError(
        'App extension name "$name" must start with a letter and contain only '
        'letters / digits / underscores.',
      );
    }
    if (_extensions.containsKey(name)) {
      throw ArgumentError('App extension "$name" is already registered.');
    }
    final entry = _RegisteredExtension(
      name: name,
      description: description,
      handler: handler,
      schema: schema,
    );
    _extensions[name] = entry;

    final method = 'ext.flutter.inkpal.app.$name';
    try {
      developer.registerExtension(method, (_, params) async {
        try {
          final result = await handler(params);
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'ok': true,
            'result': result,
          }));
        } catch (e, st) {
          return developer.ServiceExtensionResponse.result(jsonEncode({
            'ok': false,
            'error': e.toString(),
            'stack': st.toString(),
          }));
        }
      });
    } catch (e) {
      // Swallow "already registered" — happens during hot reload when the
      // VM keeps the extension registration across restarts.
      if (!e.toString().contains('already registered')) rethrow;
    }
  }

  /// Remove a previously-registered extension. Mainly for tests — the
  /// underlying VM cannot un-register an extension, but we stop advertising
  /// it in `list` responses and stop routing `call` invocations to it.
  static bool unregister(String name) => _extensions.remove(name) != null;

  /// Install the two meta extensions that the MCP side calls.
  ///
  /// Invoked once per bridge boot. Safe to call multiple times.
  static void installMetaExtensions() {
    if (_metaRegistered) return;
    _metaRegistered = true;

    try {
      developer.registerExtension(
        'ext.flutter.inkpal.app.list',
        (_, __) async => developer.ServiceExtensionResponse.result(jsonEncode({
          'extensions': _extensions.values
              .map((e) => {
                    'name': e.name,
                    'description': e.description,
                    'method': 'ext.flutter.inkpal.app.${e.name}',
                    if (e.schema != null) 'schema': e.schema,
                  })
              .toList(),
        })),
      );
    } catch (e) {
      if (!e.toString().contains('already registered')) rethrow;
    }

    try {
      developer.registerExtension(
        'ext.flutter.inkpal.app.call',
        (_, params) async {
          final name = params['name'];
          if (name == null || name.isEmpty) {
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'ok': false,
              'error': 'missing required param: name',
            }));
          }
          final entry = _extensions[name];
          if (entry == null) {
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'ok': false,
              'error': 'unknown app extension: $name',
              'available': _extensions.keys.toList(),
            }));
          }
          // params arrive flat; caller can pass a JSON-encoded 'payload' for
          // nested structures, or individual string params.
          final callParams = <String, String>{};
          for (final entry in params.entries) {
            if (entry.key != 'name') callParams[entry.key] = entry.value;
          }
          try {
            final result = await entry.handler(callParams);
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'ok': true,
              'result': result,
            }));
          } catch (e, st) {
            return developer.ServiceExtensionResponse.result(jsonEncode({
              'ok': false,
              'error': e.toString(),
              'stack': st.toString(),
            }));
          }
        },
      );
    } catch (e) {
      if (!e.toString().contains('already registered')) rethrow;
    }
  }

  /// Visible for tests.
  static int get registeredCount => _extensions.length;

  /// Visible for tests.
  static void resetForTests() {
    _extensions.clear();
    _metaRegistered = false;
  }
}
