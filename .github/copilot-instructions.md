# Battery Monitor Flutter app instructions

This app and the ESP32 firmware at
`https://github.com/duceppemo/battery_current_monitor` form one product. For
any BLE protocol, control or OTA change, update and cross-check both
repositories. `docs/BLE_PROTOCOL.md` is the protocol source of truth.

- Scan by the custom Battery Monitor service UUID, never by advertised local
  name alone.
- Preserve Binary Telemetry v1 decoding as a fixed 20-byte packet that works
  without MTU negotiation. It arrives on the one-second BLE cadence; retain
  fresh/stale treatment, session energy and extrema behavior.
- Keep binary decoders versioned and testable. Do not change a packet layout
  without a coordinated firmware protocol and release change.
- Dashboard commands append a request ID and wait for the matching applied,
  rejected or failed Control Result. Never infer command success from the BLE
  write response alone.
- Keep app-release and monitor-firmware checks separate. A firmware update
  check requires a BLE connection and a read installed firmware version before
  it can compare the public release; never embed a GitHub access token.
- BLE OTA downloads the release `.bin` into memory, transfers sequential
  write-with-response frames, verifies CRC-32/image status, and waits through
  the monitor's post-success reboot grace period. The monitor serializes Web
  and BLE OTA with a shared writer lock.
- Validate with `flutter analyze` and `flutter test` after relevant changes.
