import 'package:flutter/widgets.dart';

import 'context_cache.dart';

/// WidgetsBindingObserver that triggers cache invalidation on system events.
class ContextInvalidator with WidgetsBindingObserver {
  final ContextCache cache;

  ContextInvalidator({required this.cache});

  void attach() {
    WidgetsBinding.instance.addObserver(this);
  }

  void detach() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      cache.invalidateSession();
    }
  }

  @override
  void didChangeMetrics() {
    cache.invalidateScreen();
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    cache.invalidateScreen();
    return false;
  }

  @override
  Future<bool> didPopRoute() async {
    cache.invalidateScreen();
    return false;
  }
}
