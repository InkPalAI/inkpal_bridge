import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'network_interceptor.dart';

/// Record of a single observed HTTP request.
class HttpRequestRecord {
  final String method;
  final String url;
  final int statusCode;
  final Duration duration;
  final int requestBytes;
  final int responseBytes;
  final Object? error;
  final DateTime startedAt;

  /// Headers with sensitive values redacted.
  final Map<String, String> headers;

  HttpRequestRecord({
    required this.method,
    required this.url,
    required this.statusCode,
    required this.duration,
    required this.requestBytes,
    required this.responseBytes,
    required this.error,
    required this.startedAt,
    required this.headers,
  });

  Map<String, dynamic> toJson() => {
        'method': method,
        'url': url,
        'statusCode': statusCode,
        'durationMs': duration.inMilliseconds,
        'requestBytes': requestBytes,
        'responseBytes': responseBytes,
        'error': error?.toString(),
        'startedAt': startedAt.toIso8601String(),
        'headers': headers,
      };
}

/// Read-only HTTP request monitor. Installs a pass-through [HttpOverrides]
/// that records request metadata to a ring buffer. Redacts sensitive headers.
///
/// **Coexistence with [InkPalNetworkInterceptor]:** both set
/// `HttpOverrides.global`. [install] will throw [StateError] if it detects
/// the network interceptor already installed — use one or the other.
class InkPalHttpMonitor {
  InkPalHttpMonitor({this.capacity = 100});

  /// Ring-buffer capacity.
  final int capacity;

  /// Headers whose values are replaced with `<redacted>` before storage.
  static const Set<String> _redactedHeaders = {
    'authorization',
    'cookie',
    'set-cookie',
    'proxy-authorization',
    'x-api-key',
    'x-auth-token',
  };

  final List<HttpRequestRecord> _records = [];
  final StreamController<HttpRequestRecord> _controller =
      StreamController<HttpRequestRecord>.broadcast();
  int _errorCount = 0;
  int _totalDurationMs = 0;

  HttpOverrides? _previous;
  bool _installed = false;

  /// All captured records (oldest first, up to [capacity]).
  List<HttpRequestRecord> get records => List.unmodifiable(_records);

  /// Number of records with non-null error or status >= 400.
  int get errorCount => _errorCount;

  /// Mean latency across all recorded requests, or [Duration.zero] if empty.
  Duration get averageLatency {
    if (_records.isEmpty) return Duration.zero;
    return Duration(milliseconds: _totalDurationMs ~/ _records.length);
  }

  /// Stream of new records (broadcast).
  Stream<HttpRequestRecord> get stream => _controller.stream;

  /// Whether [install] has been called.
  bool get isInstalled => _installed;

  /// Install as global [HttpOverrides]. Throws [StateError] if the
  /// [InkPalNetworkInterceptor] is already installed.
  void install() {
    if (_installed) return;
    if (kIsWeb) {
      debugPrint('[InkPal] HttpMonitor: not supported on web platform');
      return;
    }
    final current = HttpOverrides.current;
    if (current is InkPalNetworkInterceptor) {
      throw StateError(
        'InkPalHttpMonitor.install(): InkPalNetworkInterceptor is already '
        'installed on HttpOverrides.global. Use only one at a time — the '
        'network interceptor handles mocking, the monitor handles read-only '
        'observation.',
      );
    }
    _previous = current;
    HttpOverrides.global = _MonitorHttpOverrides(this, previous: _previous);
    _installed = true;
  }

  /// Restore previous overrides.
  void uninstall() {
    if (!_installed) return;
    HttpOverrides.global = _previous;
    _previous = null;
    _installed = false;
  }

  /// Clear the ring buffer.
  void clear() {
    _records.clear();
    _errorCount = 0;
    _totalDurationMs = 0;
  }

  /// Close streams. Primarily for tests.
  Future<void> dispose() async {
    uninstall();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  // ── Internal recording API (called by client wrappers) ──

  void _record(HttpRequestRecord r) {
    _records.add(r);
    _totalDurationMs += r.duration.inMilliseconds;
    if (r.error != null || r.statusCode >= 400) {
      _errorCount += 1;
    }
    while (_records.length > capacity) {
      final dropped = _records.removeAt(0);
      _totalDurationMs -= dropped.duration.inMilliseconds;
      if (dropped.error != null || dropped.statusCode >= 400) {
        _errorCount -= 1;
      }
    }
    _controller.add(r);
  }

  static Map<String, String> _redact(Map<String, List<String>> raw) {
    final out = <String, String>{};
    raw.forEach((name, values) {
      final lower = name.toLowerCase();
      if (_redactedHeaders.contains(lower)) {
        out[name] = '<redacted>';
      } else {
        out[name] = values.join(', ');
      }
    });
    return out;
  }
}

class _MonitorHttpOverrides extends HttpOverrides {
  _MonitorHttpOverrides(this._monitor, {HttpOverrides? previous})
      : _previous = previous;

  final InkPalHttpMonitor _monitor;
  final HttpOverrides? _previous;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final inner = _previous?.createHttpClient(context) ??
        super.createHttpClient(context);
    return _MonitorHttpClient(inner, _monitor);
  }
}

class _MonitorHttpClient implements HttpClient {
  _MonitorHttpClient(this._inner, this._monitor);

  final HttpClient _inner;
  final InkPalHttpMonitor _monitor;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final started = DateTime.now();
    final stopwatch = Stopwatch()..start();
    try {
      final req = await _inner.openUrl(method, url);
      return _MonitorHttpClientRequest(
        req,
        _monitor,
        method: method,
        url: url.toString(),
        startedAt: started,
        stopwatch: stopwatch,
      );
    } catch (err) {
      stopwatch.stop();
      _monitor._record(HttpRequestRecord(
        method: method,
        url: url.toString(),
        statusCode: 0,
        duration: stopwatch.elapsed,
        requestBytes: 0,
        responseBytes: 0,
        error: err,
        startedAt: started,
        headers: const {},
      ));
      rethrow;
    }
  }

  @override
  Future<HttpClientRequest> open(
      String method, String host, int port, String path) {
    final uri = Uri(scheme: 'http', host: host, port: port, path: path);
    return openUrl(method, uri);
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      open('GET', host, port, path);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      open('POST', host, port, path);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      open('PUT', host, port, path);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);
  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      open('DELETE', host, port, path);
  @override
  Future<HttpClientRequest> headUrl(Uri url) => openUrl('HEAD', url);
  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      open('HEAD', host, port, path);
  @override
  Future<HttpClientRequest> patchUrl(Uri url) => openUrl('PATCH', url);
  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      open('PATCH', host, port, path);

  // Pass-through everything else.
  @override
  bool get autoUncompress => _inner.autoUncompress;
  @override
  set autoUncompress(bool v) => _inner.autoUncompress = v;
  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;
  @override
  set connectionTimeout(Duration? v) => _inner.connectionTimeout = v;
  @override
  Duration get idleTimeout => _inner.idleTimeout;
  @override
  set idleTimeout(Duration v) => _inner.idleTimeout = v;
  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;
  @override
  set maxConnectionsPerHost(int? v) => _inner.maxConnectionsPerHost = v;
  @override
  String? get userAgent => _inner.userAgent;
  @override
  set userAgent(String? v) => _inner.userAgent = v;
  @override
  void addCredentials(
          Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);
  @override
  void addProxyCredentials(String host, int port, String realm,
          HttpClientCredentials credentials) =>
      _inner.addProxyCredentials(host, port, realm, credentials);
  @override
  set authenticate(
          Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;
  @override
  set authenticateProxy(
          Future<bool> Function(
                  String host, int port, String scheme, String? realm)?
              f) =>
      _inner.authenticateProxy = f;
  @override
  set badCertificateCallback(
          bool Function(X509Certificate cert, String host, int port)?
              callback) =>
      _inner.badCertificateCallback = callback;
  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;
  @override
  void close({bool force = false}) => _inner.close(force: force);
  @override
  set connectionFactory(
          Future<ConnectionTask<Socket>> Function(
                  Uri url, String? proxyHost, int? proxyPort)?
              f) =>
      _inner.connectionFactory = f;
  @override
  set keyLog(Function(String line)? callback) => _inner.keyLog = callback;
}

class _MonitorHttpClientRequest implements HttpClientRequest {
  _MonitorHttpClientRequest(
    this._inner,
    this._monitor, {
    required this.method,
    required this.url,
    required this.startedAt,
    required this.stopwatch,
  });

  final HttpClientRequest _inner;
  final InkPalHttpMonitor _monitor;
  @override
  final String method;
  final String url;
  final DateTime startedAt;
  final Stopwatch stopwatch;
  int _requestBytes = 0;

  @override
  Future<HttpClientResponse> close() async {
    try {
      final resp = await _inner.close();
      return _MonitorHttpClientResponse(
        resp,
        _monitor,
        method: method,
        url: url,
        startedAt: startedAt,
        stopwatch: stopwatch,
        requestBytes: _requestBytes,
      );
    } catch (err) {
      stopwatch.stop();
      _monitor._record(HttpRequestRecord(
        method: method,
        url: url,
        statusCode: 0,
        duration: stopwatch.elapsed,
        requestBytes: _requestBytes,
        responseBytes: 0,
        error: err,
        startedAt: startedAt,
        headers: const {},
      ));
      rethrow;
    }
  }

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void add(List<int> data) {
    _requestBytes += data.length;
    _inner.add(data);
  }

  @override
  void write(Object? obj) {
    final s = obj.toString();
    _requestBytes += s.codeUnits.length;
    _inner.write(obj);
  }

  @override
  void writeln([Object? obj = '']) {
    final s = '$obj\n';
    _requestBytes += s.codeUnits.length;
    _inner.writeln(obj);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    final s = objects.join(separator);
    _requestBytes += s.codeUnits.length;
    _inner.writeAll(objects, separator);
  }

  @override
  void writeCharCode(int charCode) {
    _requestBytes += 1;
    _inner.writeCharCode(charCode);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    return _inner.addStream(stream.map((chunk) {
      _requestBytes += chunk.length;
      return chunk;
    }));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _inner.addError(error, stackTrace);
  @override
  Future flush() => _inner.flush();
  @override
  void abort([Object? exception, StackTrace? stackTrace]) =>
      _inner.abort(exception, stackTrace);

  @override
  bool get bufferOutput => _inner.bufferOutput;
  @override
  set bufferOutput(bool v) => _inner.bufferOutput = v;
  @override
  int get contentLength => _inner.contentLength;
  @override
  set contentLength(int v) => _inner.contentLength = v;
  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding v) => _inner.encoding = v;
  @override
  bool get followRedirects => _inner.followRedirects;
  @override
  set followRedirects(bool v) => _inner.followRedirects = v;
  @override
  int get maxRedirects => _inner.maxRedirects;
  @override
  set maxRedirects(int v) => _inner.maxRedirects = v;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  set persistentConnection(bool v) => _inner.persistentConnection = v;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  Uri get uri => _inner.uri;
}

class _MonitorHttpClientResponse implements HttpClientResponse {
  _MonitorHttpClientResponse(
    this._inner,
    this._monitor, {
    required this.method,
    required this.url,
    required this.startedAt,
    required this.stopwatch,
    required this.requestBytes,
  });

  final HttpClientResponse _inner;
  final InkPalHttpMonitor _monitor;
  final String method;
  final String url;
  final DateTime startedAt;
  final Stopwatch stopwatch;
  final int requestBytes;
  int _responseBytes = 0;
  bool _recorded = false;

  void _recordOnce({Object? error}) {
    if (_recorded) return;
    _recorded = true;
    stopwatch.stop();
    final headerMap = <String, List<String>>{};
    try {
      _inner.headers.forEach((name, values) {
        headerMap[name] = values;
      });
    } catch (_) {}
    _monitor._record(HttpRequestRecord(
      method: method,
      url: url,
      statusCode: _inner.statusCode,
      duration: stopwatch.elapsed,
      requestBytes: requestBytes,
      responseBytes: _responseBytes,
      error: error,
      startedAt: startedAt,
      headers: InkPalHttpMonitor._redact(headerMap),
    ));
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _inner.listen(
      (chunk) {
        _responseBytes += chunk.length;
        if (onData != null) onData(chunk);
      },
      onError: (Object err, StackTrace st) {
        _recordOnce(error: err);
        if (onError is void Function(Object, StackTrace)) {
          onError(err, st);
        } else if (onError is void Function(Object)) {
          onError(err);
        }
      },
      onDone: () {
        _recordOnce();
        if (onDone != null) onDone();
      },
      cancelOnError: cancelOnError,
    );
  }

  // Delegating remainder — Stream mixin would be cleaner, but implementing
  // every member keeps this zero-dep and avoids reflective tricks.
  @override
  int get statusCode => _inner.statusCode;
  @override
  String get reasonPhrase => _inner.reasonPhrase;
  @override
  int get contentLength => _inner.contentLength;
  @override
  HttpClientResponseCompressionState get compressionState =>
      _inner.compressionState;
  @override
  HttpHeaders get headers => _inner.headers;
  @override
  bool get isRedirect => _inner.isRedirect;
  @override
  List<RedirectInfo> get redirects => _inner.redirects;
  @override
  bool get persistentConnection => _inner.persistentConnection;
  @override
  List<Cookie> get cookies => _inner.cookies;
  @override
  HttpConnectionInfo? get connectionInfo => _inner.connectionInfo;
  @override
  X509Certificate? get certificate => _inner.certificate;

  @override
  Future<HttpClientResponse> redirect(
          [String? method, Uri? url, bool? followLoops]) =>
      _inner.redirect(method, url, followLoops);
  @override
  Future<Socket> detachSocket() => _inner.detachSocket();
  @override
  Future<bool> any(bool Function(List<int> element) test) =>
      asBroadcastStream().any(test);
  @override
  Stream<List<int>> asBroadcastStream(
          {void Function(StreamSubscription<List<int>> subscription)? onListen,
          void Function(StreamSubscription<List<int>> subscription)?
              onCancel}) =>
      _wrapped().asBroadcastStream(onListen: onListen, onCancel: onCancel);
  Stream<List<int>> _wrapped() {
    final controller = StreamController<List<int>>();
    listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    return controller.stream;
  }

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(List<int> event) convert) =>
      _wrapped().asyncExpand(convert);
  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(List<int> event) convert) =>
      _wrapped().asyncMap(convert);
  @override
  Stream<R> cast<R>() => _wrapped().cast<R>();
  @override
  Future<bool> contains(Object? needle) => _wrapped().contains(needle);
  @override
  Stream<List<int>> distinct(
          [bool Function(List<int> previous, List<int> next)? equals]) =>
      _wrapped().distinct(equals);
  @override
  Future<E> drain<E>([E? futureValue]) => _wrapped().drain(futureValue);
  @override
  Future<List<int>> elementAt(int index) => _wrapped().elementAt(index);
  @override
  Future<bool> every(bool Function(List<int> element) test) =>
      _wrapped().every(test);
  @override
  Stream<S> expand<S>(Iterable<S> Function(List<int> element) convert) =>
      _wrapped().expand(convert);
  @override
  Future<List<int>> get first => _wrapped().first;
  @override
  Future<List<int>> firstWhere(bool Function(List<int> element) test,
          {List<int> Function()? orElse}) =>
      _wrapped().firstWhere(test, orElse: orElse);
  @override
  Future<S> fold<S>(S initialValue,
          S Function(S previous, List<int> element) combine) =>
      _wrapped().fold(initialValue, combine);
  @override
  Future forEach(void Function(List<int> element) action) =>
      _wrapped().forEach(action);
  @override
  Stream<List<int>> handleError(Function onError,
          {bool Function(dynamic error)? test}) =>
      _wrapped().handleError(onError, test: test);
  @override
  bool get isBroadcast => false;
  @override
  Future<bool> get isEmpty => _wrapped().isEmpty;
  @override
  Future<String> join([String separator = '']) => _wrapped().join(separator);
  @override
  Future<List<int>> get last => _wrapped().last;
  @override
  Future<List<int>> lastWhere(bool Function(List<int> element) test,
          {List<int> Function()? orElse}) =>
      _wrapped().lastWhere(test, orElse: orElse);
  @override
  Future<int> get length => _wrapped().length;
  @override
  Stream<S> map<S>(S Function(List<int> event) convert) =>
      _wrapped().map(convert);
  @override
  Future pipe(StreamConsumer<List<int>> streamConsumer) =>
      _wrapped().pipe(streamConsumer);
  @override
  Future<List<int>> reduce(
          List<int> Function(List<int> previous, List<int> element) combine) =>
      _wrapped().reduce(combine);
  @override
  Future<List<int>> get single => _wrapped().single;
  @override
  Future<List<int>> singleWhere(bool Function(List<int> element) test,
          {List<int> Function()? orElse}) =>
      _wrapped().singleWhere(test, orElse: orElse);
  @override
  Stream<List<int>> skip(int count) => _wrapped().skip(count);
  @override
  Stream<List<int>> skipWhile(bool Function(List<int> element) test) =>
      _wrapped().skipWhile(test);
  @override
  Stream<List<int>> take(int count) => _wrapped().take(count);
  @override
  Stream<List<int>> takeWhile(bool Function(List<int> element) test) =>
      _wrapped().takeWhile(test);
  @override
  Stream<List<int>> timeout(Duration timeLimit,
          {void Function(EventSink<List<int>> sink)? onTimeout}) =>
      _wrapped().timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<List<List<int>>> toList() => _wrapped().toList();
  @override
  Future<Set<List<int>>> toSet() => _wrapped().toSet();
  @override
  Stream<S> transform<S>(StreamTransformer<List<int>, S> streamTransformer) =>
      _wrapped().transform(streamTransformer);
  @override
  Stream<List<int>> where(bool Function(List<int> event) test) =>
      _wrapped().where(test);
}
