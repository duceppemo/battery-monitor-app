# Platform setup

Generate the Android and iOS wrappers with Flutter before running the app:

```powershell
flutter create --platforms=android,ios .
flutter pub get
```

This repository intentionally does not contain signing material. Review the
generated files and use the following settings before testing on hardware.

## Android

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
   every 500 ms.
4. Turn the monitor and phone Bluetooth off/on once each; verify the UI shows
   the disconnected/stale state rather than frozen values.
5. Repeat on an Android phone and an iPhone before relying on the app during a
   measurement session.
