# Development

## Local setup

Install the current stable Flutter SDK, then fetch dependencies:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d <android-device-id>
```

Android and iOS platform shells are included. Keep signing keys, provisioning
profiles and local properties out of Git. For a local signed Android release,
copy `android/key.properties.example` to `android/key.properties` and point it
at your private upload keystore. GitHub Actions uses encrypted repository
secrets for the release key.

Use physical devices for BLE testing. The scanner intentionally filters on the
custom Battery Monitor service UUID, not only the advertised device name.

## Project layout

```text
lib/
  ble/       BLE identifiers, connection/subscription boundary and OTA transfer
  models/    Versioned, testable binary packet decoder
  screens/   App UI, connection state, controls, trends and update workflow
test/        Packet decoder and app-level behavior tests
docs/        BLE compatibility, features, platform setup and roadmap
```
