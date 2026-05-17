import 'package:flutter_test/flutter_test.dart';
import 'package:inkpal_bridge/src/license/license_validator.dart';
import 'package:inkpal_bridge/src/license/feature_tier.dart';

/// Valid 64-char hex sig for testing (SHA-256 format).
const _validSig = 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2';

/// Future expiry (24h from now).
int _futureExp() =>
    DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;

/// Past expiry (N days ago).
int _pastExp(int daysAgo) =>
    DateTime.now().subtract(Duration(days: daysAgo)).millisecondsSinceEpoch;

void main() {
  late InkPalLicense license;

  setUp(() {
    license = InkPalLicense.instance;
    license.reset();
  });

  group('InkPalLicense', () {
    group('defaults', () {
      test('defaults to free tier', () {
        expect(license.tier, InkPalTier.free);
        expect(license.isValidated, false);
      });

      test('free tier has inspection feature', () {
        expect(license.hasFeature(InkPalFeature.inspection), true);
      });

      test('free tier has navigation feature', () {
        expect(license.hasFeature(InkPalFeature.navigation), true);
      });

      test('free tier has screenshot feature (BIZ-1)', () {
        expect(license.hasFeature(InkPalFeature.screenshot), true);
      });

      test('free tier does NOT have interaction', () {
        expect(license.hasFeature(InkPalFeature.interaction), false);
      });

      test('free tier does NOT have telemetry', () {
        expect(license.hasFeature(InkPalFeature.telemetry), false);
      });

      test('free tier does NOT have networkControl', () {
        expect(license.hasFeature(InkPalFeature.networkControl), false);
      });
    });

    group('singleton', () {
      test('instance returns same object', () {
        final a = InkPalLicense.instance;
        final b = InkPalLicense.instance;
        expect(identical(a, b), true);
      });
    });

    group('applyGrant', () {
      test('valid pro grant unlocks pro features', () {
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _futureExp(),
        });
        expect(result, true);
        expect(license.tier, InkPalTier.pro);
        expect(license.isValidated, true);
        expect(license.hasFeature(InkPalFeature.interaction), true);
        expect(license.hasFeature(InkPalFeature.telemetry), true);
        expect(license.hasFeature(InkPalFeature.performance), true);
      });

      test('valid studio grant unlocks all features', () {
        final result = license.applyGrantForTesting({
          'tier': 'studio',
          'sig': _validSig,
          'exp': _futureExp(),
        });
        expect(result, true);
        expect(license.tier, InkPalTier.studio);
        expect(license.isValidated, true);
        expect(license.hasFeature(InkPalFeature.networkControl), true);
        expect(license.hasFeature(InkPalFeature.vmExtensions), true);
        expect(license.hasFeature(InkPalFeature.manifest), true);
      });

      test('rejects grant without sig', () {
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'exp': _futureExp(),
        });
        expect(result, false);
        expect(license.tier, InkPalTier.free);
        expect(license.isValidated, false);
      });

      test('rejects grant with empty sig', () {
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'sig': '',
          'exp': _futureExp(),
        });
        expect(result, false);
        expect(license.tier, InkPalTier.free);
      });

      test('rejects grant with invalid sig format (too short)', () {
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'sig': 'abc123',
          'exp': _futureExp(),
        });
        expect(result, false);
        expect(license.tier, InkPalTier.free);
      });

      test('rejects grant with invalid sig format (non-hex)', () {
        // 64 chars but contains uppercase/non-hex
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'sig': 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
          'exp': _futureExp(),
        });
        expect(result, false);
        expect(license.tier, InkPalTier.free);
      });

      test('rejects grant without tier', () {
        final result = license.applyGrantForTesting({
          'sig': _validSig,
          'exp': _futureExp(),
        });
        expect(result, false);
        expect(license.tier, InkPalTier.free);
      });

      test('rejects grant with error key', () {
        final result = license.applyGrantForTesting({
          'error': 'Invalid license key',
          'tier': 'pro',
          'sig': _validSig,
        });
        expect(result, false);
        expect(license.tier, InkPalTier.free);
      });

      test('unknown tier falls back to free', () {
        final result = license.applyGrantForTesting({
          'tier': 'enterprise',
          'sig': _validSig,
          'exp': _futureExp(),
        });
        expect(result, true);
        expect(license.tier, InkPalTier.free);
        // Still validated — server said OK, just unknown tier
        expect(license.isValidated, true);
      });

      test('custom features override tier defaults', () {
        final result = license.applyGrantForTesting({
          'tier': 'free',
          'sig': _validSig,
          'exp': _futureExp(),
          'features': ['inspection', 'interaction', 'telemetry'],
        });
        expect(result, true);
        expect(license.tier, InkPalTier.free);
        expect(license.hasFeature(InkPalFeature.interaction), true);
        expect(license.hasFeature(InkPalFeature.telemetry), true);
        // Not in custom list — should be missing
        expect(license.hasFeature(InkPalFeature.performance), false);
      });

      test('empty features list uses tier defaults', () {
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _futureExp(),
          'features': <String>[],
        });
        expect(result, true);
        // Empty features → falls back to tier defaults
        expect(license.hasFeature(InkPalFeature.interaction), true);
      });

      test('missing exp defaults to 24h from now', () {
        final result = license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
        });
        expect(result, true);
        // Grace period should be null (not expired — default 24h)
        expect(license.gracePeriodStatus, isNull);
        // Feature should work (not in grace period)
        expect(license.hasFeature(InkPalFeature.interaction), true);
      });
    });

    group('grace period', () {
      test('gracePeriodStatus is null when no expiry', () {
        expect(license.gracePeriodStatus, isNull);
      });

      test('gracePeriodStatus is null before expiry', () {
        license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _futureExp(),
        });
        expect(license.gracePeriodStatus, isNull);
      });

      test('grace period active when expired 1 day ago', () {
        license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _pastExp(1),
        });
        final status = license.gracePeriodStatus;
        expect(status, isNotNull);
        expect(status!['active'], true);
        expect(status['days_remaining'], 6);
      });

      test('features still work during grace period', () {
        license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _pastExp(3),
        });
        // Grace period: 4 days remaining
        expect(license.hasFeature(InkPalFeature.interaction), true);
        expect(license.hasFeature(InkPalFeature.telemetry), true);
      });

      test('grace period expires after 7 days', () {
        license.applyGrantForTesting({
          'tier': 'studio',
          'sig': _validSig,
          'exp': _pastExp(8),
        });
        // Past grace period — null status
        expect(license.gracePeriodStatus, isNull);
      });

      test('hard downgrade to free after grace period', () {
        license.applyGrantForTesting({
          'tier': 'studio',
          'sig': _validSig,
          'exp': _pastExp(8),
        });
        // hasFeature triggers the hard downgrade
        expect(license.hasFeature(InkPalFeature.networkControl), false);
        expect(license.tier, InkPalTier.free);
        expect(license.isValidated, false);
      });

      test('grace period at exactly 7 days still active', () {
        license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _pastExp(7),
        });
        final status = license.gracePeriodStatus;
        expect(status, isNotNull);
        expect(status!['days_remaining'], 0);
      });
    });

    group('reset', () {
      test('reset returns to free tier after pro grant', () {
        license.applyGrantForTesting({
          'tier': 'pro',
          'sig': _validSig,
          'exp': _futureExp(),
        });
        expect(license.tier, InkPalTier.pro);

        license.reset();
        expect(license.tier, InkPalTier.free);
        expect(license.isValidated, false);
        expect(license.hasFeature(InkPalFeature.interaction), false);
        expect(license.gracePeriodStatus, isNull);
      });
    });

    group('tier features exhaustive', () {
      test('pro tier has all features except networkControl', () {
        final proFeatures = InkPalTier.pro.features;
        expect(proFeatures, contains(InkPalFeature.inspection));
        expect(proFeatures, contains(InkPalFeature.navigation));
        expect(proFeatures, contains(InkPalFeature.interaction));
        expect(proFeatures, contains(InkPalFeature.telemetry));
        expect(proFeatures, contains(InkPalFeature.screenshot));
        expect(proFeatures, contains(InkPalFeature.performance));
        expect(proFeatures, contains(InkPalFeature.vmExtensions));
        expect(proFeatures, contains(InkPalFeature.manifest));
        expect(proFeatures, isNot(contains(InkPalFeature.networkControl)));
      });

      test('studio tier has all features', () {
        final studioFeatures = InkPalTier.studio.features;
        for (final feature in InkPalFeature.values) {
          expect(studioFeatures, contains(feature),
              reason: '${feature.name} should be in studio tier');
        }
      });
    });

    group('throttle', () {
      test('validate is throttled within 60 seconds', () async {
        final result1 = await license.validate(
          apiUrl: 'http://localhost:0',
          licenseKey: 'test_key',
        );
        expect(result1, false); // No server running

        final result2 = await license.validate(
          apiUrl: 'http://localhost:0',
          licenseKey: 'test_key',
        );
        expect(result2, false); // Returns cached _validated
      });
    });
  });
}
