# App roadmap

## First usable release

- [x] Define the shared Binary Telemetry v1 contract.
- [x] Add a service-filtered scan, connection boundary and packet decoder.
- [x] Add unit coverage for signed packet decoding and version rejection.
- [x] Generate and configure Android and iOS platform shells with Flutter.
- [x] Add Bluetooth permission declarations and runtime permission UX.
- [x] Test scanning, reconnecting and live notifications on an Android device.
- [x] Add stale-packet UI treatment using the packet sequence and receipt time.
- [ ] Test scanning, reconnecting and live notifications on an iPhone.

## After shunt validation

- [x] Expose firmware min/max, directional energy and separate session-reset
  controls in the app.
- [x] Add a bounded app-local session log and compact trend views with an
  explicit 7,200-entry retention policy.
- [x] Add CSV export from user-approved, local session data.
- [x] Add local-only Raw/Fast/Stable presentation filtering and named test
  sessions with summaries. Raw telemetry remains the source for history,
  export, alarms and firmware-sourced energy.
- [x] Add a transition-only, app-local event timeline to test sessions and CSV
  exports for BLE lifecycle, alarms, telemetry errors and detected restarts.
- [x] Show rated-capacity progress and a remaining-capacity estimate from a
  net-discharge test session; validate it after final-shunt commissioning.

## Current release hardening

- [x] Add calibrated measurement controls, persistent monitor alarms and their
  acknowledgement path to the shared dashboard protocol.
- [x] Add Web and BLE OTA workflows, release discovery, image version display
  and transfer verification.
- [x] Add BLE home Wi-Fi station setup and forget, so configuring the
  monitor's network no longer requires leaving your own network to join its
  recovery AP first.
- [ ] Test scanning, reconnecting and live notifications on an iPhone.
- [ ] Validate current, energy and alarm behavior after commissioning the
  final Kelvin shunt at known loads.

## Later

- [ ] Add a stable firmware-provided monitor serial-number characteristic.
- [ ] Design authenticated firmware OTA as a separate firmware/app feature.
- [ ] Consider optional on-device or cloud persistence only after the data
  lifetime, privacy and battery impact are defined.
