import 'feature_tier.dart';
import 'license_validator.dart';

/// Guards feature access based on the current license grant.
///
/// Usage in command handlers:
/// ```dart
/// _router.register('tap_element', (params) async {
///   final gate = FeatureGate.check(InkPalFeature.interaction);
///   if (!gate.allowed) return gate.denied();
///   // ... proceed with tap
/// });
/// ```
class FeatureGate {
  final InkPalFeature feature;
  final bool allowed;

  FeatureGate._(this.feature, this.allowed);

  /// Check if a feature is unlocked by the current license.
  static FeatureGate check(InkPalFeature feature) {
    final allowed = InkPalLicense.instance.hasFeature(feature);
    return FeatureGate._(feature, allowed);
  }

  /// Convenience: returns an error map for denied features.
  /// Use as the return value of a command handler when gated.
  Map<String, dynamic> denied() {
    final tier = InkPalLicense.instance.tier;
    final requiredTier = _minimumTier(feature);
    return {
      'success': false,
      'error': 'feature_locked',
      'feature': feature.name,
      'currentTier': tier.name,
      'requiredTier': requiredTier.name,
      'message': '${feature.name} requires ${requiredTier.name} tier. '
          'Current tier: ${tier.name}. '
          'Upgrade at https://inkpal.ai/pricing',
    };
  }

  /// Find the minimum tier that unlocks a feature.
  static InkPalTier _minimumTier(InkPalFeature feature) {
    for (final tier in InkPalTier.values) {
      if (tier.features.contains(feature)) return tier;
    }
    return InkPalTier.studio;
  }
}
