# Battery Monitor App

Public cross-platform Flutter companion app for the Battery Monitor firmware.
It connects directly to the monitor over Bluetooth Low Energy; it has no
account or cloud service. Internet is only used when the user explicitly checks
GitHub Releases or downloads a firmware-release asset before a BLE update.

## Linked firmware and shared contract

This app pairs with the public [Battery Current Monitor firmware
repository](https://github.com/duceppemo/battery_current_monitor). The
repositories stay separate but release together whenever the BLE protocol or
OTA behavior changes. [docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md) is the
canonical app-side compatibility contract; it mirrors the firmware copy.
Binary Telemetry v1 is a fixed 20-byte, one-Hz notification that works without
MTU negotiation. The app reads monitor firmware version only after BLE
connection, then compares it with the public firmware release before offering
download and install.

## Current milestone

The current app version is `0.3.5+14`. It provides a focused, foreground BLE
companion for one monitor at a time:

1. Service-filtered scan, connection lifecycle and an active disconnect action.
2. Binary Telemetry v1 with fresh/stale state, live values and session energy.
3. Rotating dashboard data for extrema, directional energy, calibration,
   sensor configuration, persistent alarms and Wi-Fi station status.
4. Acknowledged reset, OLED, calibration and alarm controls on firmware
   0.5.1+ (`control1`).
5. An app-local, bounded 7,200-entry session log with trend views and
   user-approved CSV export/share, named test metadata, summaries and an event
   timeline, plus rated-capacity progress for discharge tests.
6. Raw, fast and stable live-display filtering that never changes raw history,
   alarms, CSV exports or firmware energy accounting.
7. GitHub Release discovery, image download and BLE OTA with transfer progress,
   verification and a post-success reboot grace period.
8. Home Wi-Fi station setup and forget, over BLE, on firmware 0.5.3+
   (`wifi1`) — no need to leave your own network to join the monitor's
   recovery AP just to configure it.

The firmware/app compatibility contract is
[docs/BLE_PROTOCOL.md](docs/BLE_PROTOCOL.md). Treat a protocol change as a
firmware-and-app release decision, not an implementation detail.

## Live display filter modes

The **Live values** card has a local display filter. It does not change the
BLE packet, monitor calibration, min/max values, alarms, session log, CSV
export, or the monitor's Ah/Wh counters.

- **Raw** — shows each received one-Hz measurement immediately. Choose it for
  commissioning, calibration, troubleshooting, or observing quick changes.
- **Fast** — applies light smoothing to the displayed voltage, current, power
  and temperature. It settles quickly while making normal low-current noise
  less distracting.
- **Stable** — applies stronger smoothing for the calmest readable display.
  It deliberately reacts more slowly to a real change, so do not use it to
  judge fast transients or a safety-critical event.

Changing modes clears the previous filter state, so the first displayed sample
in the newly selected mode is always current rather than an old value.

## Test-session event timeline

Each recording test keeps a compact local event timeline alongside its raw
samples. It records session start/finish, monitor connect/disconnect, BLE data
errors, alarm activation/clear transitions, demo mode, and monitor restarts
detected from an uptime reset. The test card shows the eight most recent
events; its summary includes the total count.

CSV exports preserve the original telemetry table and append a separate
`event_at_utc,event_type,detail` table when events exist. The timeline is
app-side evidence: it does not claim the monitor enforced an action or replace
the raw measurement log.

## Capacity progress estimate

When starting a named test, enter an optional positive **Rated capacity (Ah)**.
For a net-discharge test, the app compares the captured session net Ah change
with that rating and shows discharged percentage plus estimated remaining Ah
and percentage. The estimate is not shown for net charging sessions.

This is a convenient session-progress indicator, not a voltage-based state of
charge model or a substitute for calibration. Its accuracy depends on the
monitor's current calibration, the shunt, and keeping the test session running
for the discharge being measured.

Platform permission and signing guidance is in
[docs/PLATFORM_SETUP.md](docs/PLATFORM_SETUP.md).

## Firmware updates

The **Connection & app update** card checks only for a newer Android/iOS app
release; it does not query monitor firmware. For a monitor update, first
connect by BLE so the app can read the installed firmware version. The
**Monitor firmware update** card then checks the firmware release, compares
versions, and offers **Download** only when an update exists. The app keeps the
image in memory, so it can then transfer it over BLE without joining the
monitor Wi-Fi AP. Firmware 0.5.1+ accepts **Install via BLE** and the app waits
for its CRC-32/image-verification status before restart.

Both repositories and release assets are public by design: a consumer app must
discover and download updates without an embedded GitHub credential. Never add
a personal access token to the app.

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
