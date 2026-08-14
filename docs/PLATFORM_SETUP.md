# Platform setup

The Android and iOS wrappers are already checked into this repository. Fetch
packages before running the app:

```powershell
flutter pub get
```

This repository intentionally does not contain signing material. Use the
following settings before testing on hardware.

## Android

### Release signing

For a local release, copy `android/key.properties.example` to
`android/key.properties` and set its values for a private upload keystore. Both
files are intentionally ignored by Git except for the example. The GitHub
release workflow expects these repository secrets instead:

- `ANDROID_KEYSTORE_BASE64` — Base64 form of the upload `.jks` file.
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`

Back up the upload keystore and its passwords somewhere private. Losing them
prevents future Android updates from being installed over a published app.

Add these permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<!-- Android 12 / API 31 and newer -->
<uses-permission
    android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

<!-- Android 11 and older -->
<uses-permission
    android:name="android.permission.ACCESS_FINE_LOCATION"
    android:maxSdkVersion="30" />

<uses-feature
    android:name="android.hardware.bluetooth_le"
    android:required="true" />
```

Request the relevant runtime permissions before scanning. `neverForLocation`
is appropriate only because this app does not derive the user's physical
location from BLE results.

## iOS

Add a clear reason to `ios/Runner/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Battery Monitor uses Bluetooth to connect to your monitor and show live measurements.</string>
```

The first release is foreground-only. Do not enable Bluetooth background modes
until we have defined and tested their power, reconnection and user-expectation
behaviour independently on both platforms.

## Hardware test checklist

1. Confirm the phone sees `BatteryMonitor` while the firmware is advertising.
2. Confirm the app filters by the Battery Monitor service, then connects.
3. Subscribe to Binary Telemetry v1 and verify a new 20-byte packet about
   every second.
4. Turn the monitor and phone Bluetooth off/on once each; verify the UI shows
   the disconnected/stale state rather than frozen values.
5. On firmware 0.5.1+, issue a reset, OLED, calibration or alarm command and
   verify the request-ID-matched result instead of assuming that a BLE write
   response means the action was applied.
6. Verify **Check app update** reports only the public app release. After
   connecting and reading the monitor version, verify **Check for updates** in
   the monitor-firmware card compares and discovers the public firmware
   release.
7. Test a release asset by Web OTA and BLE OTA separately; a verified BLE
   update should report success before the monitor restarts and reconnects.
8. Repeat scanning, reconnecting and live notifications on an Android phone
   and an iPhone before relying on the app during a measurement session.
