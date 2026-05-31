import 'package:flutter/widgets.dart';

import '../inspection/navigator_observer.dart';

/// Global navigator key the bridge can use to push/pop without depending on
/// any specific [BuildContext].
///
/// **Wire this on your `MaterialApp` (or `CupertinoApp` / `WidgetsApp`):**
/// ```dart
/// MaterialApp(
///   navigatorKey: inkpalNavigatorKey,
///   navigatorObservers: [inkpalNavigatorObserver],
///   home: ...,
/// )
/// ```
///
/// With both wired, `ext.flutter.inkpal.goBack` and `ext.flutter.inkpal.navigate`
/// can drive navigation reliably without tap-on-back-button gymnastics.
final GlobalKey<NavigatorState> inkpalNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'inkpalNavigatorKey',
);

/// Global navigator observer the bridge uses to track the route stack.
/// See also: [InkPalNavigatorObserver].
final InkPalNavigatorObserver inkpalNavigatorObserver =
    InkPalNavigatorObserver();
