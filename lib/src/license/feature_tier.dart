/// Feature categories gated by license tier.
///
/// Each feature maps to a capability set. The license server returns
/// which features are unlocked for a given key.
enum InkPalFeature {
  /// Read UI semantics tree (get_screen_content, get_widget_tree, find_widget)
  inspection,

  /// Route tracking (get_current_route, get_app_state, manifest)
  navigation,

  /// Tap, scroll, setText, navigate, goBack, longPress, slider
  interaction,

  /// Log streaming, error capture, log correlation
  telemetry,

  /// Screenshot capture
  screenshot,

  /// Performance monitoring (FPS, jank)
  performance,

  /// Network mocking, offline mode, latency simulation
  networkControl,

  /// VM Service extensions (ext.flutter.inkpal.*)
  vmExtensions,

  /// App manifest and flow definitions
  manifest,
}

/// License tiers — each unlocks a set of features.
enum InkPalTier {
  /// Free: inspection + navigation only
  free,

  /// Pro: all features except networkControl
  pro,

  /// Studio: everything
  studio;

  /// Features unlocked at this tier.
  Set<InkPalFeature> get features {
    switch (this) {
      case InkPalTier.free:
        return const {
          InkPalFeature.inspection,
          InkPalFeature.navigation,
          InkPalFeature.screenshot, // BIZ-1: trial conversion
        };
      case InkPalTier.pro:
        return const {
          InkPalFeature.inspection,
          InkPalFeature.navigation,
          InkPalFeature.interaction,
          InkPalFeature.telemetry,
          InkPalFeature.screenshot,
          InkPalFeature.performance,
          InkPalFeature.vmExtensions,
          InkPalFeature.manifest,
        };
      case InkPalTier.studio:
        return InkPalFeature.values.toSet();
    }
  }
}
