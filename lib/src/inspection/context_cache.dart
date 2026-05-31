import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'navigator_observer.dart';
import 'screen_context.dart';

class _CacheEntry<T> {
  final T value;
  final DateTime cachedAt;

  _CacheEntry(this.value) : cachedAt = DateTime.now();

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(cachedAt) > ttl;
  }
}

/// Multi-level LRU cache for app context.
///
/// Three cache levels with independent TTLs:
/// - L1 (Global): user auth state, app config — TTL 5 minutes
/// - L2 (Session): navigation stack, visited routes — TTL 30 seconds
/// - L3 (Screen): current screen semantics snapshot — TTL configurable
class ContextCache {
  final Duration screenTtl;

  static const _globalTtl = Duration(minutes: 5);
  static const _sessionTtl = Duration(seconds: 30);
  static const _maxScreenEntries = 10;

  _CacheEntry<Map<String, dynamic>>? _globalCache;
  _CacheEntry<Map<String, dynamic>>? _sessionCache;

  final LinkedHashMap<String, _CacheEntry<ScreenContext>> _screenCache =
      LinkedHashMap<String, _CacheEntry<ScreenContext>>();

  bool _screenDirty = true;
  bool _sessionDirty = true;
  bool _globalDirty = true;

  bool _wasDirty = false;
  bool get wasDirty => _wasDirty;

  final ScreenContext Function()? onCaptureScreen;
  final Future<Map<String, dynamic>> Function()? onCaptureGlobal;

  ContextCache({
    this.screenTtl = const Duration(seconds: 10),
    this.onCaptureScreen,
    this.onCaptureGlobal,
  });

  ScreenContext getScreenContext(String? currentRoute) {
    if (currentRoute != null && !_screenDirty) {
      final entry = _screenCache[currentRoute];
      if (entry != null && !entry.isExpired(screenTtl)) {
        _screenCache.remove(currentRoute);
        _screenCache[currentRoute] = entry;
        _wasDirty = false;
        return entry.value;
      }
    }

    _wasDirty = true;
    final context = onCaptureScreen?.call() ?? ScreenContext.empty();
    if (currentRoute != null) {
      _screenCache[currentRoute] = _CacheEntry(context);
      while (_screenCache.length > _maxScreenEntries) {
        final evicted = _screenCache.keys.first;
        _screenCache.remove(evicted);
        debugPrint('[InkPal] Cache evicted LRU entry "$evicted"');
      }
      InkPalNavigatorObserver.cacheScreenKnowledge(currentRoute, context);
    }
    _screenDirty = false;
    return context;
  }

  Future<Map<String, dynamic>> getGlobalContext() async {
    if (!_globalDirty &&
        _globalCache != null &&
        !_globalCache!.isExpired(_globalTtl)) {
      return _globalCache!.value;
    }

    final context = await onCaptureGlobal?.call() ?? {};
    _globalCache = _CacheEntry(context);
    _globalDirty = false;
    return context;
  }

  Map<String, dynamic> getSessionContext() {
    if (!_sessionDirty &&
        _sessionCache != null &&
        !_sessionCache!.isExpired(_sessionTtl)) {
      return _sessionCache!.value;
    }

    final context = {
      'currentRoute': InkPalNavigatorObserver.currentRoute,
      'navigationStack': InkPalNavigatorObserver.routeStack,
      'discoveredRoutes': InkPalNavigatorObserver.discoveredRoutes.toList(),
    };
    _sessionCache = _CacheEntry(context);
    _sessionDirty = false;
    return context;
  }

  void invalidateScreen() => _screenDirty = true;

  void invalidateSession() {
    _sessionDirty = true;
    _screenDirty = true;
  }

  void invalidateAll() {
    _globalDirty = true;
    _sessionDirty = true;
    _screenDirty = true;
  }

  Map<String, ScreenContext> get screenKnowledge {
    return InkPalNavigatorObserver.screenKnowledge;
  }

  void clear() {
    _globalCache = null;
    _sessionCache = null;
    _screenCache.clear();
    _globalDirty = true;
    _sessionDirty = true;
    _screenDirty = true;
  }
}
