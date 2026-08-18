# Features

## Current milestone

The current app version is `0.3.15+24`. It provides a focused, foreground BLE
companion for one monitor at a time:

1. Service-filtered scan, connection lifecycle and an active disconnect action.
2. Binary Telemetry v1 with fresh/stale state, live values and session energy.
3. Rotating dashboard data for extrema, directional energy, calibration,
   sensor configuration, persistent alarms, Wi-Fi station status and battery
   state of charge.
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
9. Battery fuel gauge on firmware 0.5.3+ (`soc1`): coulomb-counted state of
   charge and time-to-empty, persisted on the monitor across reboots (unlike
   the session Ah/Wh counters above), with battery-capacity/charged-voltage
   settings and a manual full-charge sync, plus deepest-discharge,
   full-charge-cycle-count and average-discharge-depth history (firmware
   0.5.4+) that resets independently of the current charge level.
10. A full capacity test report generated from a finished test session's own
    local log: a voltage-vs-discharged-Ah curve, observed capacity against
    the rated capacity, an optional Peukert-law adjustment to a reference
    discharge rate, a pass/fail verdict against a configurable threshold, and
    a shareable plain-text summary. Entirely app-local and firmware-version
    independent — it's computed from data the session log already captures.
11. Load-protection relay control on firmware 0.5.10+ (`protection1`): enable
    a low-voltage/low-SoC cutoff, reconnect after a trip (rejected while the
    trigger condition is still active), and bench-test force-connect/
    force-disconnect controls that bypass every threshold to verify the
    relay wiring itself. Mirrors the Web Dashboard's card exactly, so either
    transport can configure or test it.
12. A stable per-monitor identity on firmware 0.5.15+: the app compares each
    connection's `ID` (from Device Information) against the last monitor it
    connected to and warns if they differ, since the OS-assigned BLE address
    used to scan/connect isn't a reliable "same device" signal on its own —
    iOS in particular can rotate it for the same physical monitor.
13. Opt-in session Ah/Wh persistence on firmware 0.5.15+ (`energyp1`): a
    checkbox on the Session energy card lets these totals survive a reboot
    instead of resetting every power cycle. Off by default; enabling it
    starts persisting the totals already accumulating, it does not restore
    an old saved value over live progress.
14. A remembered list of saved monitors (up to 10, most-recent first),
    keyed by the same stable per-chip `ID` used for the mismatch warning
    above: each successful connection is recorded with a default name
    (editable) and its last-known BLE address, shown above live scan
    results with its own Connect button, a rename dialog and a "Forget"
    action. Still one connection at a time by design — this is a quick way
    to switch between a house bank, a starter battery or a friend's boat
    monitor, not simultaneous multi-monitor dashboards. If a saved
    address is stale (a new random BLE address, or the unit out of range),
    the connection attempt fails like any other and a normal scan finds it
    again. A live scan result already saved is hidden from the plain scan
    list instead of showing twice, and any not-yet-saved result shows a
    distinguishing default name (a fragment of its BLE address) instead of
    the generic name every monitor advertises.
15. A device-side name on firmware 0.5.18+ (`name1`), shared with the Web
    Dashboard rather than a phone-only label: connecting reads the
    monitor's actual name from Device Information and syncs it into the
    saved-monitor entry, and renaming while connected pushes the change to
    the monitor (control command `17`) so the Web Dashboard picks it up
    too, instead of only relabeling it on this phone. Older firmware
    without `name1` keeps the previous purely local, phone-only naming.

The firmware/app compatibility contract is
[BLE_PROTOCOL.md](BLE_PROTOCOL.md). Treat a protocol change as a
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

## Temperature unit

A "Show °F"/"Show °C" button in the app bar toggles the displayed
temperature unit everywhere it appears: the live value, min/max, the
capacity test report's temperature range, and the alarm temperature
threshold field. The preference persists locally (`shared_preferences`)
across app restarts. This is purely a display choice — the BLE protocol,
the monitor's stored alarm threshold and the app's local `AlarmSettings`
model all stay in Celsius; the app converts to Celsius before sending an
alarm save and back to the display unit when showing a stored value.

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

## Capacity test report

Finishing a named test session (Test session card → **Finish**) offers
**View full report**, a dedicated screen built from that session's own local
log — nothing is fetched from the monitor beyond what was already captured:

- A voltage-vs-discharged-Ah discharge curve, decimated to a smooth chart
  regardless of how many raw samples the session holds.
- Observed capacity (Ah) and energy (Wh), average discharge current and rate
  expressed in C (multiples of the rated capacity), against the session's
  rated capacity.
- A **PASS**/**FAIL**/**INCONCLUSIVE** verdict against a configurable
  threshold (80% of rated capacity by default) — inconclusive only when no
  rated capacity was set for the test.
- An optional Peukert-law rate adjustment: enter the battery's Peukert
  exponent and the discharge duration its rated capacity was actually
  specified at (e.g. 20 hours for a C/20 lead-acid rating), and the report
  normalizes the observed capacity to that reference rate before comparing it
  against the rating. Both fields are blank by default and the adjustment is
  skipped unless both are filled in — there is no built-in default exponent,
  since guessing wrong for the wrong chemistry would make the verdict
  silently untrustworthy. Treat a large adjustment as an approximate
  extrapolation, most reliable when the test rate is reasonably close to the
  reference rate.
- A shareable plain-text summary via the same share sheet as CSV export.

This report has been validated against synthetic session data (see
`test/capacity_test_report_test.dart` and
`test/capacity_report_screen_test.dart`) but not yet against a real
controlled discharge test.

Platform permission and signing guidance is in
[PLATFORM_SETUP.md](PLATFORM_SETUP.md).

## Load protection relay

On firmware 0.5.10+ (`protection1`), the app has a load-protection card that
mirrors the Web Dashboard's exactly — either transport can configure or test
it, and both act on the same monitor state:

- **Disabled by default**, and a complete no-op until explicitly enabled: an
  unreviewed default threshold can never disconnect a load nobody asked to
  protect.
- Once enabled, the monitor opens its relay/SSR output the moment voltage or
  state of charge drops below the configured threshold, whichever happens
  first — SoC is only checked once the fuel gauge has been synced at least
  once. The trip **latches**: it never reconnects on its own, so a reading
  hovering at the threshold under load can't chatter the relay.
- **Reconnect load** clears the latch, but is rejected while the trigger
  condition is still active.
- **Test: force connect** / **Test: force disconnect** bypass the enabled
  flag and every threshold entirely, for bench-testing the relay/SSR wiring
  itself before trusting the automatic logic.

Verified end-to-end against real SSR hardware (an InkBird SSR-25 DA) through
this app.

## Firmware updates

The **Connection & app update** card checks only for a newer Android/iOS app
release; it does not query monitor firmware. For a monitor update, first
connect by BLE so the app can read the installed firmware version. The
**Monitor firmware update** card then checks the firmware release, compares
versions, and offers **Download** only when an update exists. The app keeps the
image in memory, so it can then transfer it over BLE without joining the
monitor Wi-Fi AP. Firmware 0.5.1+ accepts **Install via BLE** and the app waits
for its CRC-32/image-verification status before restart.

Firmware 0.5.16+ additionally requires a signature: the app also downloads the
release's `.sig` asset and sends it as part of the BLE start frame, so the
monitor can verify the image against its embedded public key before marking it
bootable. Releases published before signed OTA don't have a `.sig` asset;
**Download** reports this and the Web Dashboard remains the way to install
them.

Both repositories and release assets are public by design: a consumer app must
discover and download updates without an embedded GitHub credential. Never add
a personal access token to the app.

Web and BLE use the same firmware update writer; do not start an update in one
interface while the other is active. A verified BLE update leaves its success
status available briefly before the monitor restarts, after which the app
reconnects and reads the installed version.

The Web Dashboard can still upload the same local `.bin` file, and remains the
bootstrap/recovery route for monitor firmware that predates BLE OTA, and for
releases without a `.sig` asset. It stays CRC/format-checked only, without a
signature check; download assets only from this project's GitHub Releases.
