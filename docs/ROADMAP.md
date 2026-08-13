# App roadmap

## First usable release

- [x] Define the shared Binary Telemetry v1 contract.
- [x] Add a service-filtered scan, connection boundary and packet decoder.
- [x] Add unit coverage for signed packet decoding and version rejection.
- [ ] Generate and configure Android and iOS platform shells with Flutter.
- [ ] Add Bluetooth permission declarations and runtime permission UX.
- [ ] Test scanning, reconnecting and live notifications on one Android phone
  and one iPhone.
- [ ] Add stale-packet UI treatment using the packet sequence and receipt time.

## After shunt validation

- [ ] Add min/max values and separate session-reset controls to the firmware
  contract, then expose them in the app.
- [ ] Add an in-memory chart with an explicit bounded sampling policy.
- [ ] Add CSV export from user-approved, local session data.

## Later

- [ ] Add a stable firmware-provided monitor serial-number characteristic.
- [ ] Design authenticated firmware OTA as a separate firmware/app feature.
- [ ] Consider optional on-device or cloud persistence only after the data
  lifetime, privacy and battery impact are defined.
