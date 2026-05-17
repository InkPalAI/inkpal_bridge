import 'protocol.dart';

/// Routes incoming JSON-RPC 2.0 commands to handler functions.
///
/// Supports an optional [isAppReady] gate — when set, in-app commands
/// (anything not in [_lifecycleCommands]) are rejected until the app's
/// widget tree has rendered its first frame.
class CommandRouter {
  final Map<
      String,
      Future<Map<String, dynamic>> Function(
        Map<String, dynamic> params,
      )> _handlers = {};

  /// Commands that work even before the app is fully rendered.
  static const _lifecycleCommands = {'ping', 'get_log_history', 'get_error_history'};

  /// Optional readiness check — set by [InkPalBridge] after first frame.
  bool Function()? isAppReady;

  void register(
    String method,
    Future<Map<String, dynamic>> Function(Map<String, dynamic> params) handler,
  ) {
    _handlers[method] = handler;
  }

  /// Process an incoming JSON-RPC request and return the response.
  Future<Map<String, dynamic>> handle(Map<String, dynamic> request) async {
    final method = request['method'] as String?;
    final id = request['id'];
    final params =
        (request['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    if (method == null) {
      if (id != null) {
        return JsonRpc.error(id as int, -32600, 'Invalid request: no method');
      }
      return {};
    }

    // Gate: reject in-app commands before the widget tree is ready
    if (!_lifecycleCommands.contains(method) &&
        isAppReady != null &&
        !isAppReady!()) {
      if (id != null) {
        return JsonRpc.error(
          id as int,
          -32002,
          'App not ready — widget tree has not rendered yet. '
              'Wait for the app to finish launching before using in-app features.',
        );
      }
      return {};
    }

    final handler = _handlers[method];
    if (handler == null) {
      if (id != null) {
        return JsonRpc.error(
          id as int,
          -32601,
          'Method not found: $method',
        );
      }
      return {};
    }

    try {
      final result = await handler(params);
      if (id != null) {
        return JsonRpc.response(id as int, result);
      }
      return {};
    } catch (e) {
      if (id != null) {
        return JsonRpc.error(id as int, -32603, 'Internal error: $e');
      }
      return {};
    }
  }
}
