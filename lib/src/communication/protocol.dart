/// JSON-RPC 2.0 message constructors.
class JsonRpc {
  static Map<String, dynamic> request(
    int id,
    String method, [
    Map<String, dynamic>? params,
  ]) =>
      {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      };

  static Map<String, dynamic> response(
    int id,
    Map<String, dynamic> result,
  ) =>
      {
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      };

  static Map<String, dynamic> error(int id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  static Map<String, dynamic> notification(
    String method,
    Map<String, dynamic> params,
  ) =>
      {
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
      };
}
