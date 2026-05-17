/// InkPalNetworkInterceptor — Runtime HTTP mocking for Flutter apps.
///
/// Implements Dart's [HttpOverrides] to intercept all HTTP requests made
/// via [dart:io]. Supports:
///  - Per-URL mock rules (pattern matching, status code, body, delay)
///  - Offline mode (block all requests)
///  - Network condition simulation (latency + packet loss)
///
/// Usage in main():
/// ```dart
/// void main() {
///   WidgetsFlutterBinding.ensureInitialized();
///   InkPalNetworkInterceptor.install();
///   runApp(const MyApp());
/// }
/// ```
///
/// InkPal MCP tools (inkpal_mock_network, inkpal_go_offline, etc.) communicate
/// with this interceptor via VM Service extensions registered by InkPalVmExtensions.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'network_interceptor_ref.dart';

/// A mock rule applied to matching HTTP requests.
class MockRule {
  final String urlPattern;   // glob-style: "*/api/users*"
  final int responseCode;
  final String? responseBody;
  final String method;       // "ANY", "GET", "POST", …
  final int delayMs;

  const MockRule({
    required this.urlPattern,
    required this.responseCode,
    this.responseBody,
    required this.method,
    required this.delayMs,
  });

  bool matches(String url, String httpMethod) {
    final methodOk = method == 'ANY' || method == httpMethod.toUpperCase();
    if (!methodOk) return false;
    return _globMatch(urlPattern, url);
  }

  static bool _globMatch(String pattern, String str) {
    // Convert glob (*) to regex
    final regexStr = RegExp.escape(pattern).replaceAll(r'\*', '.*');
    return RegExp('^$regexStr\$').hasMatch(str);
  }
}

/// Concrete implementation of [InkPalNetworkInterceptorRef].
///
/// Installed as [HttpOverrides.global], intercepts all dart:io HTTP requests.
class InkPalNetworkInterceptor extends HttpOverrides
    implements InkPalNetworkInterceptorRef {
  InkPalNetworkInterceptor._();

  /// Installs the interceptor as [HttpOverrides.global], registers itself
  /// with [InkPalNetworkInterceptorRef.instance], and registers the 6
  /// network VM Service extensions so InkPal MCP tools work immediately
  /// without needing the full InkPalBridge WebSocket setup.
  static InkPalNetworkInterceptor install() {
    // dart:io HttpOverrides is not available on web — skip installation.
    if (kIsWeb) {
      debugPrint('[InkPal] NetworkInterceptor: not supported on web platform');
      return InkPalNetworkInterceptor._();
    }
    final interceptor = InkPalNetworkInterceptor._();
    HttpOverrides.global = interceptor;
    InkPalNetworkInterceptorRef.instance = interceptor;
    interceptor._registerNetworkVmExtensions();
    return interceptor;
  }

  static developer.ServiceExtensionResponse _ok(Map<String, dynamic> data) =>
      developer.ServiceExtensionResponse.result(jsonEncode(data));

  void _registerNetworkVmExtensions() {
    developer.registerExtension('ext.flutter.inkpal.mockNetwork', (_, params) async {
      addMockRule(
        urlPattern:   params['url_pattern']   ?? '*',
        responseCode: int.tryParse(params['response_code'] ?? '200') ?? 200,
        responseBody: params['response_body'],
        method:       params['method']        ?? 'ANY',
        delayMs:      int.tryParse(params['delay_ms'] ?? '0') ?? 0,
      );
      return _ok({'success': true, 'rule_added': params['url_pattern'], 'source': 'vm_extension'});
    });

    developer.registerExtension('ext.flutter.inkpal.clearNetworkMocks', (_, params) async {
      clearRules();
      return _ok({'success': true, 'source': 'vm_extension'});
    });

    developer.registerExtension('ext.flutter.inkpal.goOffline', (_, params) async {
      setOffline(true);
      return _ok({'success': true, 'message': 'Network blocked in-app', 'source': 'vm_extension'});
    });

    developer.registerExtension('ext.flutter.inkpal.goOnline', (_, params) async {
      setOffline(false);
      return _ok({'success': true, 'message': 'Network restored in-app', 'source': 'vm_extension'});
    });

    developer.registerExtension('ext.flutter.inkpal.networkConditions', (_, params) async {
      final delayMs     = int.tryParse(params['delay_ms']     ?? '0') ?? 0;
      final lossPercent = int.tryParse(params['loss_percent'] ?? '0') ?? 0;
      setConditions(delayMs, lossPercent);
      return _ok({'success': true, 'delay_ms': delayMs, 'loss_percent': lossPercent, 'source': 'vm_extension'});
    });

    developer.registerExtension('ext.flutter.inkpal.networkStatus', (_, params) async {
      return _ok({
        'success':       true,
        'offline':       _offline,
        'delay_ms':      _delayMs,
        'loss_percent':  _lossPercent,
        'mock_rules':    _rules.length,
        'source':        'vm_extension',
      });
    });
  }

  final List<MockRule> _rules = [];
  bool _offline = false;
  int _delayMs = 0;
  int _lossPercent = 0;
  final _random = Random();

  // ── InkPalNetworkInterceptorRef API ────────────────────────────────────────

  @override
  void addMockRule({
    required String urlPattern,
    required int responseCode,
    String? responseBody,
    required String method,
    required int delayMs,
  }) {
    _rules.add(MockRule(
      urlPattern:   urlPattern,
      responseCode: responseCode,
      responseBody: responseBody,
      method:       method,
      delayMs:      delayMs,
    ));
  }

  @override
  void clearRules() => _rules.clear();

  @override
  void setOffline(bool offline) => _offline = offline;

  @override
  void setConditions(int delayMs, int lossPercent) {
    _delayMs     = delayMs;
    _lossPercent = lossPercent.clamp(0, 100);
  }

  // ── HttpOverrides ──────────────────────────────────────────────────────────

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = super.createHttpClient(context);
    return _InterceptingHttpClient(inner, this);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  MockRule? _findRule(String url, String method) {
    for (final rule in _rules.reversed) {
      if (rule.matches(url, method)) return rule;
    }
    return null;
  }

  Future<HttpClientRequest> _intercept(
    HttpClientRequest realRequest,
    String url,
    String method,
  ) async {
    // Offline: block all
    if (_offline) {
      realRequest.close();
      throw const SocketException('InkPal: network offline (blocked by inkpal_go_offline)');
    }

    // Packet loss simulation
    if (_lossPercent > 0 && _random.nextInt(100) < _lossPercent) {
      realRequest.close();
      throw const SocketException('InkPal: simulated packet loss');
    }

    // Latency simulation (apply before rule check so it stacks with rule delay)
    if (_delayMs > 0) {
      await Future.delayed(Duration(milliseconds: _delayMs));
    }

    // Mock rule
    final rule = _findRule(url, method);
    if (rule != null) {
      if (rule.delayMs > 0) {
        await Future.delayed(Duration(milliseconds: rule.delayMs));
      }
      return _MockedHttpClientRequest(realRequest, rule);
    }

    return realRequest;
  }
}

// ── Internal wrappers ─────────────────────────────────────────────────────────

class _InterceptingHttpClient implements HttpClient {
  final HttpClient _inner;
  final InkPalNetworkInterceptor _interceptor;

  _InterceptingHttpClient(this._inner, this._interceptor);

  Future<HttpClientRequest> _open(
    Future<HttpClientRequest> Function() openFn,
    String method,
    Uri uri,
  ) async {
    final req = await openFn();
    return _interceptor._intercept(req, uri.toString(), method);
  }

  @override
  Future<HttpClientRequest> open(String method, String host, int port, String path) =>
      _open(() => _inner.open(method, host, port, path), method, Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _open(() => _inner.openUrl(method, url), method, url);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      openUrl('GET', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      openUrl('POST', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      openUrl('PUT', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      openUrl('DELETE', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      openUrl('PATCH', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      openUrl('HEAD', Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);

  // Delegate everything else to _inner
  @override bool get autoUncompress => _inner.autoUncompress;
  @override set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override Duration? get connectionTimeout => _inner.connectionTimeout;
  @override set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override Duration get idleTimeout => _inner.idleTimeout;
  @override set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override String? get userAgent => _inner.userAgent;
  @override set userAgent(String? v) => _inner.userAgent = v;
  @override void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);
  @override void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);
  @override set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;
  @override set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) =>
      _inner.authenticateProxy = f;
  @override set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) =>
      _inner.badCertificateCallback = callback;
  @override set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
  @override set connectionFactory(Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? f) =>
      _inner.connectionFactory = f;
  @override void close({bool force = false}) => _inner.close(force: force);
  @override set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
}

/// Wraps an [HttpClientRequest] and substitutes a mock response when [close] is called.
class _MockedHttpClientRequest implements HttpClientRequest {
  final HttpClientRequest _real;
  final MockRule _rule;

  _MockedHttpClientRequest(this._real, this._rule);

  @override
  Future<HttpClientResponse> close() async {
    // Abort the real request, return a synthetic response
    try { _real.abort(); } catch (_) {}
    return _MockedHttpClientResponse(_rule);
  }

  // Delegate headers/write to _real so callers don't error
  @override HttpHeaders get headers => _real.headers;
  @override String get method => _real.method;
  @override Uri get uri => _real.uri;
  @override void add(List<int> data) => _real.add(data);
  @override void addError(Object error, [StackTrace? stackTrace]) => _real.addError(error, stackTrace);
  @override Future addStream(Stream<List<int>> stream) => _real.addStream(stream);
  @override void write(Object? object) => _real.write(object);
  @override void writeln([Object? object = '']) => _real.writeln(object);
  @override void writeAll(Iterable objects, [String separator = '']) => _real.writeAll(objects, separator);
  @override void writeCharCode(int charCode) => _real.writeCharCode(charCode);
  @override Future<HttpClientResponse> get done => _real.done;
  @override Future flush() => _real.flush();
  @override void abort([Object? exception, StackTrace? stackTrace]) => _real.abort(exception, stackTrace);
  @override bool get bufferOutput => _real.bufferOutput;
  @override set bufferOutput(bool v) => _real.bufferOutput = v;
  @override int get contentLength => _real.contentLength;
  @override set contentLength(int v) => _real.contentLength = v;
  @override Encoding get encoding => _real.encoding;
  @override set encoding(Encoding v) => _real.encoding = v;
  @override bool get followRedirects => _real.followRedirects;
  @override set followRedirects(bool v) => _real.followRedirects = v;
  @override int get maxRedirects => _real.maxRedirects;
  @override set maxRedirects(int v) => _real.maxRedirects = v;
  @override bool get persistentConnection => _real.persistentConnection;
  @override set persistentConnection(bool v) => _real.persistentConnection = v;
  @override HttpConnectionInfo? get connectionInfo => _real.connectionInfo;
  @override List<Cookie> get cookies => _real.cookies;
}

/// Synthesized [HttpClientResponse] returned for matched mock rules.
class _MockedHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final MockRule _rule;

  _MockedHttpClientResponse(this._rule);

  @override
  int get statusCode => _rule.responseCode;

  @override
  String get reasonPhrase => _statusPhrase(_rule.responseCode);

  @override
  int get contentLength {
    final body = _rule.responseBody;
    return body == null ? 0 : body.length;
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final bytes = _rule.responseBody?.codeUnits ?? const <int>[];
    return Stream.value(bytes).listen(
      onData,
      onError:      onError,
      onDone:       onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override HttpHeaders get headers => _EmptyHeaders();
  @override bool get isRedirect => false;
  @override bool get persistentConnection => false;
  @override List<RedirectInfo> get redirects => [];
  @override HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override X509Certificate? get certificate => null;
  @override HttpConnectionInfo? get connectionInfo => null;
  @override List<Cookie> get cookies => [];
  @override Future<HttpClientResponse> redirect([String? method, Uri? url, bool? followLoops]) =>
      Future.error(UnsupportedError('MockedResponse does not support redirect'));
  @override Future<Socket> detachSocket() =>
      Future.error(UnsupportedError('MockedResponse does not support detachSocket'));

  static String _statusPhrase(int code) => switch (code) {
    200 => 'OK',
    201 => 'Created',
    204 => 'No Content',
    400 => 'Bad Request',
    401 => 'Unauthorized',
    403 => 'Forbidden',
    404 => 'Not Found',
    500 => 'Internal Server Error',
    503 => 'Service Unavailable',
    _ => 'Unknown',
  };
}

class _EmptyHeaders implements HttpHeaders {
  @override List<String>? operator [](String name) =>
      name.toLowerCase() == 'content-type' ? ['application/json'] : null;
  @override String? value(String name) =>
      name.toLowerCase() == 'content-type' ? 'application/json' : null;
  @override void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override void clear() {}
  @override void forEach(void Function(String name, List<String> values) action) {}
  @override void noFolding(String name) {}
  @override void remove(String name, Object value) {}
  @override void removeAll(String name) {}
  @override void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override bool get chunkedTransferEncoding => false;
  @override set chunkedTransferEncoding(bool v) {}
  @override int get contentLength => -1;
  @override set contentLength(int v) {}
  @override ContentType? get contentType => null;
  @override set contentType(ContentType? v) {}
  @override DateTime? get date => null;
  @override set date(DateTime? v) {}
  @override DateTime? get expires => null;
  @override set expires(DateTime? v) {}
  @override String? get host => null;
  @override set host(String? v) {}
  @override DateTime? get ifModifiedSince => null;
  @override set ifModifiedSince(DateTime? v) {}
  @override bool get persistentConnection => false;
  @override set persistentConnection(bool v) {}
  @override int? get port => null;
  @override set port(int? v) {}
}
