import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Zero-touch free-tier license provisioning.
///
/// Goal: a developer who runs `flutter pub add inkpal_bridge` and
/// `inkpalRunApp(MyApp())` (no explicit `licenseKey:` arg) gets a working
/// free-tier session with **zero friction** — no signup, no copy-paste,
/// no hunting for a key. The bridge:
///
///   1. Reads / generates a stable per-machine `device_id` (random UUID,
///      cached at `$HOME/.inkpal/device_id`).
///   2. Reads any cached free key at `$HOME/.inkpal/auto_license.json`.
///   3. If no cached key, asks the InkPal API for an auto-provisioned
///      free-tier key:
///        `POST $apiUrl/api/license/auto-provision`
///        body: `{ device_id, hostname, platform, client: "inkpal_bridge" }`
///        returns: `{ key, tier, features, exp, sig }`
///   4. Caches the result for next session.
///   5. If the network is unreachable AND no cache exists, falls back to
///      a locally-generated `ink_offline_$deviceShort` key tagged as
///      free-tier with no expiry. The validator's offline-grace path
///      keeps everything working until the user is online again.
///
/// Auto-provision **only runs in debug mode** (`kDebugMode`). Release
/// builds skip it entirely — release apps must ship a real key.
class InkPalAutoProvision {
  /// Returns a usable license key for this session. Never throws — falls
  /// back to a local offline key if the API is unreachable.
  static Future<String> ensureKey({required String apiUrl}) async {
    if (!kDebugMode) {
      // Release builds must ship a key explicitly. Return offline placeholder
      // so the bridge still constructs cleanly, but features stay free-tier.
      return _offlineKey(_deviceFingerprintSync());
    }

    final cacheDir = _cacheDir();
    if (cacheDir == null) {
      // Sandboxed platform with no HOME — fall back to a per-process key.
      return _offlineKey(_deviceFingerprintSync());
    }

    // 1. Cached license?
    try {
      final cacheFile = File('$cacheDir/auto_license.json');
      if (cacheFile.existsSync()) {
        final raw = jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
        final key = raw['key'] as String?;
        final exp = raw['exp'] as int?;
        if (key != null && exp != null && DateTime.now().millisecondsSinceEpoch < exp) {
          debugPrint('[InkPal License] Using cached auto-provisioned key (exp ${DateTime.fromMillisecondsSinceEpoch(exp).toIso8601String()})');
          return key;
        }
      }
    } catch (e) {
      debugPrint('[InkPal License] Cache read failed: $e');
    }

    // 2. Fresh provision from server
    final deviceId = _deviceIdSync(cacheDir);
    final key = await _requestFreeKey(apiUrl: apiUrl, deviceId: deviceId, cacheDir: cacheDir);
    if (key != null) return key;

    // 3. Offline fallback — local-only free-tier key, validator treats it
    // as a stub and the gate uses InkPalTier.free defaults.
    debugPrint(
      '[InkPal License] Offline — using local free-tier key. '
      'Reconnect to claim a server-signed key automatically next session.',
    );
    return _offlineKey(deviceId);
  }

  static Future<String?> _requestFreeKey({
    required String apiUrl,
    required String deviceId,
    required String cacheDir,
  }) async {
    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 6);
      final uri = Uri.parse('$apiUrl/api/license/auto-provision');
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      // Hostname is hashed before sending — the local hostname can carry
      // PII (e.g. "johns-macbook-pro.local"). The server uses it only as a
      // weak grouping signal for ops, never displays it. Sending an opaque
      // 8-char hash keeps the signal without leaking the cleartext.
      final hostname = Platform.localHostname;
      final hostHash = hostname.codeUnits.fold<int>(5381, (a, b) => ((a << 5) + a) ^ b);
      final hostnameOpaque = 'h_${hostHash.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';
      req.write(jsonEncode({
        'device_id': deviceId,
        'hostname': hostnameOpaque,
        'platform': defaultTargetPlatform.name,
        'client': 'inkpal_bridge',
      }));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();

      if (resp.statusCode != 200) {
        debugPrint('[InkPal License] auto-provision rejected (${resp.statusCode}) — using offline mode');
        return null;
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      final key = data['key'] as String?;
      if (key == null) return null;

      // Persist for next session
      final file = File('$cacheDir/auto_license.json');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(data));
      debugPrint('[InkPal License] Auto-provisioned free key (cached for next session). To upgrade: visit https://inkpal.ai/upgrade?device=$deviceId');
      return key;
    } catch (e) {
      debugPrint('[InkPal License] auto-provision network error: $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static String? _cacheDir() {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null || home.isEmpty) return null;
    return '$home/.inkpal';
  }

  /// Stable per-machine UUID. Generated lazily, cached.
  static String _deviceIdSync(String cacheDir) {
    try {
      final file = File('$cacheDir/device_id');
      if (file.existsSync()) {
        final s = file.readAsStringSync().trim();
        if (s.isNotEmpty) return s;
      }
      final id = _genUuid();
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(id);
      return id;
    } catch (_) {
      return _deviceFingerprintSync();
    }
  }

  /// Last-resort fingerprint when we can't write to disk.
  static String _deviceFingerprintSync() {
    final hostname = Platform.localHostname;
    final hash = hostname.codeUnits.fold<int>(5381, (a, b) => ((a << 5) + a) ^ b);
    return 'fp_${hash.toUnsigned(32).toRadixString(16).padLeft(8, '0')}';
  }

  static String _genUuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0,8)}-${hex.substring(8,12)}-${hex.substring(12,16)}-${hex.substring(16,20)}-${hex.substring(20)}';
  }

  static String _offlineKey(String fingerprint) {
    // 24-char total satisfies the InkPal "≥20 chars + ink_ prefix" gate
    // used elsewhere, so the bridge keeps validating cleanly offline.
    final pad = ('${fingerprint}0000000000000000').substring(0, 16);
    return 'ink_offline_$pad';
  }
}
