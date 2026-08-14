# Battery Monitor App

Private cross-platform Flutter companion app for the Battery Monitor firmware.
It connects directly to the monitor over Bluetooth Low Energy; it has no
account or cloud service. Internet is only used when the user explicitly checks
GitHub Releases or downloads a firmware-release asset before a BLE update.

## Current milestone

The current app version is `0.3.0+6`. It provides a focused, foreground BLE
companion for one monitor at a time:

1. Service-filtered scan, connection lifecycle and an active disconnect action.
2. Binary Telemetry v1 with fresh/stale state, live values and session energy.
3. Rotating dashboard data for extrema, directional energy, calibration,
   sensor configuration and persistent alarms.
4. Acknowledged reset, OLED, calibration and alarm controls on firmware
   0.5.1+ (`control1`).
5. An app-local, bounded 7,200-entry session log with trend views and
   user-approved CSV export/share.
6. GitHub Release discovery, image download and BLE OTA with transfer progress,
   verification and a post-success reboot grace period.

The firmware/app compatibility contract is
[docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md). Treat a protocol change as a
firmware-and-app release decision, not an implementation detail.

Platform permission and signing guidance is in
[docs/PLATFORM_SETUP.md](docs/PLATFORM_SETUP.md).

## Firmware updates

Use **Check for updates** while the phone has internet access. For a monitor
update, choose **Download firmware** first; the app keeps the image in memory,
so the phone can then connect to `BatteryMonitor` over BLE without needing the
monitor Wi-Fi AP. Connect to a firmware 0.5.1+ monitor and choose **Install via
BLE**. The app sends sequential, write-with-response frames and waits for the
monitor's CRC-32/image-verification status before it restarts.

Web and BLE use the same firmware update writer; do not start an update in one
interface while the other is active. A verified BLE update leaves its success
status available briefly before the monitor restarts, after which the app
reconnects and reads the installed version.

The Web Dashboard can still upload the same local `.bin` file, and remains the
bootstrap/recovery route for monitor firmware that predates BLE OTA. CRC-32
detects corruption but does not authenticate an image; download assets only
from this project's GitHub Releases.

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
docs/        BLE compatibility, platform setup and roadmap
```

## License

MIT. See [LICENSE](LICENSE).
