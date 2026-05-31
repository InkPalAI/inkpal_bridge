import 'navigator_observer.dart';

/// Information about a named route in the app.
class RouteInfo {
  final String name;
  final String? description;

  const RouteInfo({required this.name, this.description});
}

/// Discovers and maintains a list of all available routes in the app.
///
/// Routes are discovered through two sources:
/// 1. Developer-provided [knownRoutes]
/// 2. Routes observed via [InkPalNavigatorObserver]
class RouteDiscovery {
  final List<String> _knownRoutes;
  final Map<String, String> _routeDescriptions;

  RouteDiscovery({
    List<String> knownRoutes = const [],
    Map<String, String> routeDescriptions = const {},
  })  : _knownRoutes = knownRoutes,
        _routeDescriptions = routeDescriptions;

  /// Get all known routes, combining developer-provided and discovered routes.
  List<RouteInfo> getAvailableRoutes() {
    final allRouteNames = <String>{
      ..._knownRoutes,
      ...InkPalNavigatorObserver.discoveredRoutes,
    };

    return allRouteNames.map((name) {
      return RouteInfo(
        name: name,
        description: _routeDescriptions[name] ?? _inferDescription(name),
      );
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  String? _inferDescription(String routeName) {
    var name = routeName.startsWith('/') ? routeName.substring(1) : routeName;
    if (name.isEmpty) return 'Home screen';

    final words = name
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll(RegExp(r'[_-]'), ' ')
        .trim();

    if (words.isEmpty) return null;
    return words[0].toUpperCase() + words.substring(1).toLowerCase();
  }
}
