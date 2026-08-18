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
- [x] Add a battery fuel gauge card (state of charge, time-to-empty, capacity
  and charged-voltage settings, manual full-charge sync) reading the
  monitor's persisted, coulomb-counted state — distinct from the app-local,
  per-test rated-capacity progress estimate above.
- [x] Show and let the app reset the monitor's deepest-discharge,
  full-charge-cycle-count and average-discharge-depth history alongside the
  fuel gauge (firmware 0.5.4+).
- [ ] Test scanning, reconnecting and live notifications on an iPhone.
- [ ] Validate current, energy and alarm behavior after commissioning the
  final Kelvin shunt at known loads.
- [x] Add a full capacity test report (discharge curve, observed-vs-rated
  capacity, optional Peukert rate adjustment, pass/fail verdict, shareable
  summary) generated from a finished test session's own local log. Validated
  against synthetic session data only so far — not yet against a real
  controlled discharge test.
- [x] Add BLE control for the load-protection relay on firmware 0.5.10+
  (`protection1`): save thresholds/enable, reconnect after a trip, and
  bench-test force-connect/force-disconnect. Verified end-to-end against
  real SSR hardware.
- [x] Add opt-in session Ah/Wh persistence on firmware 0.5.15+
  (`energyp1`): a checkbox on the Session energy card, off by default.

## Later

- [x] Add a stable firmware-provided monitor serial-number characteristic:
  firmware 0.5.15+ includes a per-chip `ID` in Device Information; the app
  compares it against the last-connected monitor and warns on a mismatch.
- [x] Add authenticated firmware OTA (firmware 0.5.16+): the app downloads
  the release's `.sig` asset alongside the `.bin` and sends the 64-byte
  ECDSA-P256 signature in the BLE transfer start frame; the monitor verifies
  it before marking the image bootable. BLE-only by design -- the Web
  Dashboard upload path is unchanged. Verified end-to-end against the real
  v0.5.16 GitHub release: downloaded, transferred over BLE, signature
  verified, and the monitor rebooted into the new firmware.
- [ ] Consider optional on-device or cloud persistence only after the data
  lifetime, privacy and battery impact are defined.
- [x] Add a remembered list of saved monitors (`SavedMonitorStore`), keyed
  by the stable per-chip `ID` from Device Information: each connection is
  recorded with a default (renamable) name and last-known BLE address, up
  to 10 entries, most-recent first. Still one connection at a time by
  design, not simultaneous multi-monitor dashboards -- a quick way to
  switch between a house bank, a starter battery or a friend's boat.
  Verified end-to-end on a physical device: connect, saved entry appears,
  rename persists, reconnect via the saved entry succeeds, disconnect is
  clean.
- [x] Stop showing an already-saved monitor a second time as a generic
  "BatteryMonitor" in the plain scan list, and give a not-yet-saved scan
  result a distinguishing default name (a BLE-address fragment) instead of
  the name every monitor advertises identically -- the same fragment a
  freshly-saved entry's default name uses, so it doesn't change the moment
  you connect.
- [x] Add a device-side name on firmware 0.5.18+ (`name1`), shared with the
  Web Dashboard instead of a phone-only label: connecting syncs the saved
  monitor's name from the device's actual name, and renaming while
  connected pushes the change over BLE (control command `17`) rather than
  only relabeling it locally. Falls back to the previous purely-local
  naming against older firmware. Verified end-to-end: renamed via the Web
  Dashboard and confirmed over BLE, renamed via the app while connected and
  confirmed on the Web Dashboard, both directions updating immediately
  (firmware fix: Device Information's `NAME=` field was only rebuilt on
  the normal one-second publish cycle, so a client re-reading it right
  after an acknowledged rename could still catch a stale value).
