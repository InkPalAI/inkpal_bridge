import 'package:flutter/widgets.dart';

import '../manifest/ai_app_manifest.dart';

/// Configuration for InkPal Bridge.
class InkPalBridgeConfig {
  /// WebSocket URL for real-time bidirectional communication.
  /// Commands IN from MCP server, telemetry OUT to server.
  /// This is the primary channel — the moat.
  final String serverUrl;

  /// Function that runs the app (called inside the bridge wrapper).
  final void Function() appRunner;

  /// License key for feature gating. Without a valid key, only free-tier
  /// features (inspection + navigation) are available.
  final String? licenseKey;

  /// InkPal API URL for license validation.
  /// Defaults to the production Railway endpoint.
  final String? apiUrl;

  /// Optional: navigator key for route navigation.
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Optional: known route names for fuzzy resolution.
  final List<String> knownRoutes;

  /// Optional: route descriptions for LLM context.
  final Map<String, String> routeDescriptions;

  /// Optional: rich app manifest.
  final AiAppManifest? manifest;

  /// Optional: callback providing app-level state.
  final Future<Map<String, dynamic>> Function()? globalStateProvider;

  /// Screenshot target width in pixels. Default: 720.
  final int screenshotWidth;

  /// Optional: custom navigation callback.
  final Future<void> Function(String routeName)? onNavigateToRoute;

  const InkPalBridgeConfig({
    required this.serverUrl,
    required this.appRunner,
    this.licenseKey,
    this.apiUrl,
    this.navigatorKey,
    this.knownRoutes = const [],
    this.routeDescriptions = const {},
    this.manifest,
    this.globalStateProvider,
    this.screenshotWidth = 720,
    this.onNavigateToRoute,
  });
}
