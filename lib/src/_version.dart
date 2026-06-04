/// The published version of `inkpal_bridge`.
///
/// **Maintenance contract:** This constant must be bumped in lockstep with
/// the `version:` field in `pubspec.yaml`. When you bump the pubspec, also
/// bump this file in the same commit. The `ext.flutter.inkpal.ping` VM
/// extension reports this value, so a stale value here misleads tooling.
///
/// We avoid `package_info_plus` (third-party dep — banned in this package)
/// and a build-time codegen step (we want the package usable as a path dep
/// without `build_runner`). Manual sync is the cost of zero-deps.
const String inkpalBridgeVersion = '1.5.0';
