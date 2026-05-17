# test_app

Integration-test harness for the `inkpal_bridge` Flutter plugin.

## Running integration tests locally

The harness contains three integration test files under `integration_test/`:

- `extension_coverage_test.dart` — 40 passing tests (VM service extensions)
- `ws_command_coverage_test.dart` — 1 passing, 41 skipped (need `flutter drive`)
- `lifecycle_test.dart` — 2 passing, 3 skipped

### Caveat: run each file separately

`flutter test integration_test/` (pointing at the directory) currently fails on
the second file's app-launch due to a flutter-tester limitation — the embedded
harness cannot relaunch the app across multiple integration test files in a
single invocation. Always run each file individually:

```bash
flutter test integration_test/extension_coverage_test.dart
flutter test integration_test/ws_command_coverage_test.dart
flutter test integration_test/lifecycle_test.dart
```

The CI workflow (`.github/workflows/bridge-e2e.yml`) does the same.

### Android (emulator)

```bash
# List available AVDs
flutter emulators

# Launch one (replace <id> with e.g. Pixel_6_API_33)
flutter emulators --launch <id>

# Then, from this directory:
flutter pub get
flutter test integration_test/extension_coverage_test.dart
flutter test integration_test/ws_command_coverage_test.dart
flutter test integration_test/lifecycle_test.dart
```

### iOS (simulator)

```bash
# List available simulators
xcrun simctl list devices available

# Boot one (example)
xcrun simctl boot "iPhone 15"
open -a Simulator

# Then, from this directory:
flutter pub get
flutter test -d <simulator-udid> integration_test/extension_coverage_test.dart
flutter test -d <simulator-udid> integration_test/ws_command_coverage_test.dart
flutter test -d <simulator-udid> integration_test/lifecycle_test.dart
```

## CI

Pushes and pull requests that touch `packages/inkpal_bridge/**` trigger the
`inkpal_bridge E2E` workflow, which runs the above suite on both an Android
emulator (API 33, x86_64, `google_apis`) and an iOS simulator (macOS 14 runner).
