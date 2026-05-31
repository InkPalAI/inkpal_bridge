import 'package:flutter/widgets.dart';

import 'screen_context.dart';

/// NavigatorObserver that tracks the full route stack for InkPal.
///
/// Attach this to your MaterialApp's navigatorObservers list.
/// InkPal uses this to know which screen the user is on
/// and what navigation history exists.
class InkPalNavigatorObserver extends NavigatorObserver {
  static final List<String> _routeStack = [];
  static final Map<String, ScreenContext> _screenKnowledge = {};

  /// Callback fired when the route changes.
  void Function(String? newRoute)? onRouteChanged;

  InkPalNavigatorObserver({this.onRouteChanged});

  /// The name of the currently active route.
  static String? get currentRoute =>
      _routeStack.isNotEmpty ? _routeStack.last : null;

  /// Unmodifiable copy of the full navigation stack.
  static List<String> get routeStack => List.unmodifiable(_routeStack);

  /// All unique route names seen during this session.
  static Set<String>? _discoveredRoutesCache;
  static Set<String> get discoveredRoutes {
    return _discoveredRoutesCache ??= {
      ..._routeStack,
      ..._screenKnowledge.keys,
    };
  }

  /// Cached screen knowledge from previously visited routes.
  static Map<String, ScreenContext> get screenKnowledge =>
      Map.unmodifiable(_screenKnowledge);

  /// Store a screen context snapshot for a route (progressive learning).
  static void cacheScreenKnowledge(String route, ScreenContext context) {
    _screenKnowledge[route] = context;
    _discoveredRoutesCache = null;
  }

  /// Track a navigation that happened outside the Navigator (e.g. via
  /// GetX's Get.toNamed or go_router's context.go). Call this after
  /// onNavigateToRoute succeeds so getCurrentRoute stays accurate.
  static void trackExternalNavigation(String routeName) {
    _routeStack.add(routeName);
    _discoveredRoutesCache = null;
  }

  /// Reset all tracking state (e.g., on logout or hot restart).
  static void reset() {
    _routeStack.clear();
    _screenKnowledge.clear();
    _discoveredRoutesCache = null;
  }

  static void _removeLastRouteByName(String name) {
    for (int i = _routeStack.length - 1; i >= 0; i--) {
      if (_routeStack[i] == name) {
        _routeStack.removeAt(i);
        return;
      }
    }
  }

  static bool _replaceLastRouteName(String oldName, String newName) {
    for (int i = _routeStack.length - 1; i >= 0; i--) {
      if (_routeStack[i] == oldName) {
        _routeStack[i] = newName;
        return true;
      }
    }
    return false;
  }

  /// Resolve a stable identifier for a route.
  ///
  /// `Navigator.push(MaterialPageRoute(builder: ...))` creates a route with
  /// `settings.name == null`, so before this fallback the observer silently
  /// dropped builder-pushed screens — `getCurrentRoute` then returned null
  /// even though a new screen was visible.
  ///
  /// Order of preference:
  /// 1. The user-supplied `RouteSettings.name` — always preferred for
  ///    long-lived stable identifiers (e.g. `/login`, `/home/settings`).
  /// 2. A synthetic `<runtimeType>` tag — readable enough for AI tooling
  ///    to distinguish screens during a session, even if not stable across
  ///    builds.
  ///
  /// **Recommendation for callers:** for fully-functional `currentRoute`
  /// tracking, push with explicit settings:
  /// `MaterialPageRoute(builder: ..., settings: RouteSettings(name: '/foo'))`.
  @visibleForTesting
  static String routeIdentifier(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) return name;
    return '<${route.runtimeType}>';
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final id = routeIdentifier(route);
    _routeStack.add(id);
    _discoveredRoutesCache = null;
    onRouteChanged?.call(id);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final id = routeIdentifier(route);
    _removeLastRouteByName(id);
    _discoveredRoutesCache = null;
    onRouteChanged?.call(_routeStack.isNotEmpty ? _routeStack.last : null);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final oldId = oldRoute != null ? routeIdentifier(oldRoute) : null;
    final newId = newRoute != null ? routeIdentifier(newRoute) : null;

    if (oldId != null && newId != null) {
      final replaced = _replaceLastRouteName(oldId, newId);
      if (!replaced) {
        _routeStack.add(newId);
      }
      _discoveredRoutesCache = null;
    } else if (oldId != null) {
      _removeLastRouteByName(oldId);
      _discoveredRoutesCache = null;
    } else if (newId != null) {
      _routeStack.add(newId);
      _discoveredRoutesCache = null;
    }
    onRouteChanged?.call(_routeStack.isNotEmpty ? _routeStack.last : null);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    final id = routeIdentifier(route);
    _removeLastRouteByName(id);
    _discoveredRoutesCache = null;
    onRouteChanged?.call(_routeStack.isNotEmpty ? _routeStack.last : null);
  }
}
