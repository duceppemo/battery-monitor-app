# BLE protocol

The app supports the firmware's Binary Telemetry v1, Dashboard Data v1 and
Dashboard Control v1 contracts below. Firmware 0.5.0+ advertises `ota1` in
Device Information; firmware 0.5.1+ additionally advertises `control1` for
acknowledged controls; firmware 0.5.3+ additionally advertises `wifi1` for
setting home Wi-Fi station credentials over BLE.

## Firmware Transfer v1

- Write-with-response: `7d9f000d-9c65-4d3d-bdd5-8f4c6b2e1000`
- Read/notify status: `7d9f000e-9c65-4d3d-bdd5-8f4c6b2e1000`

The app starts with `0xA0 + u32 image size + u32 IEEE CRC-32`, sends `0xA1 +
u32 offset + data` frames in order, and finishes with `0xA2`. `0xA3` aborts.
The status packet is 12 bytes: protocol version, state, received/expected byte
counts, error code and reserved byte. State `2` means the monitor verified the
complete image and the monitor waits two seconds before rebooting. This transfer checks integrity, not the
publisher's identity; use only a trusted GitHub Release asset.

The monitor is a BLE GATT peripheral named `BatteryMonitor`. It exposes the
custom service:

```text
7d9f0000-9c65-4d3d-bdd5-8f4c6b2e1000
```

The existing readable text characteristics remain supported for diagnostics and
generic tools such as nRF Connect. The mobile app subscribes to the Binary
Telemetry characteristic:

```text
7d9f0009-9c65-4d3d-bdd5-8f4c6b2e1000
```

It supports `Read` and `Notify`. Firmware publishes it on the one-second BLE
cadence after completed measurements. It is a fixed 20-byte little-endian
packet, deliberately small enough to fit in the initial BLE ATT notification
payload. The app must not rely on MTU negotiation for live telemetry.

## Binary Telemetry v1

| Offset | Size | Type | Field | Meaning |
| --- | ---: | --- | --- | --- |
| 0 | 1 | `uint8` | version and flags | High nibble is protocol version (`1`). Low nibble: bit 0 voltage valid, bit 1 current valid, bit 2 power valid, bit 3 temperature valid. Ignore other bits. |
| 1 | 2 | `uint16` | sequence | Little-endian measurement sequence, modulo 65,536. It increases for each completed sample. |
| 3 | 2 | `uint16` | voltage | Millivolts. Valid only when the voltage flag is set. |
| 5 | 3 | `int24` | current | Signed milliamps. Positive is battery discharge. Valid only when the current flag is set. |
| 8 | 3 | `int24` | power | Signed milliwatts. Positive is battery discharge. Valid only when the power flag is set. |
| 11 | 1 | `int8` | temperature | Degrees Celsius, rounded to the nearest whole degree. Valid only when the temperature flag is set. |
| 12 | 4 | `int32` | net charge | Signed milliamp-hours for this power-on session. Positive is discharge. |
| 16 | 4 | `int32` | net energy | Signed milliwatt-hours for this power-on session. Positive is discharge. |

For invalid live fields, the packet transmits zero and clears the matching
flag; use the flag rather than treating zero as an error. Energy fields are
saturated only if their signed 32-bit scaled range is exceeded.

## Compatibility rules

The app accepts a packet only when it is exactly 20 bytes and its high-nibble
version is supported. A future incompatible packet uses a new characteristic
UUID and a new version number; Binary Telemetry v1 remains available for
existing app releases. Do not identify a monitor by a phone-provided BLE ID:
iOS provides a privacy-scoped identifier that can change.

## Dashboard Data and controls v1

The app dashboard uses three additional service characteristics. Dashboard data
uses fixed 20-byte little-endian pages so the initial ATT MTU is sufficient:

| UUID suffix | Access | Purpose |
| --- | --- | --- |
| `000a-9c65-4d3d-bdd5-8f4c6b2e1000` | Read, Notify | Rotating dashboard pages: extrema (`0x11`), directional energy (`0x12`), state (`0x13`), calibration (`0x14`), shunt/config (`0x15`), alarms (`0x16`) and Wi-Fi station status (`0x17`). See the firmware repository's `docs/BLE_PROTOCOL.md` for the byte layout. |
| `000b-9c65-4d3d-bdd5-8f4c6b2e1000` | Write with response | Dashboard controls. Commands: `1` reset extrema, `2` reset session energy, `3` toggle OLED, `4` save calibration, `5` restore default calibration, `6` save alarms, `7` save Wi-Fi station credentials, `8` clear Wi-Fi station credentials. The app appends a request ID. |
| `000f-9c65-4d3d-bdd5-8f4c6b2e1000` | Read, Notify | Control result: version, command, request ID and applied/rejected/failed result. |

The app subscribes to both the live telemetry and dashboard characteristics.
Dashboard pages rotate once per one-second BLE update, so a newly connected app
may take up to seven seconds to populate all secondary information. Commands
are applied by the firmware main loop and confirmed by the matching Control
Result notification; commands `7` and `8` also show up on the next Wi-Fi
station dashboard page.

Command `7`'s payload (`u8` SSID length, SSID bytes, `u8` password length,
password bytes) can reach 99 bytes before the appended request ID, well past
the guaranteed 20-byte usable payload of a default 23-byte ATT MTU. The app
requests a larger MTU (`247`) before writing it; a short SSID/password may
still work without that, but a long one will fail if negotiation didn't help.
The password must be empty (open network) or at least 8 bytes.

Control Result is a fixed six-byte packet: protocol version (`1`), command,
`u16` request ID, result (`0` idle, `1` applied, `2` rejected because another
command is pending, `3` failed to persist), and one reserved byte. A write
response only confirms receipt by GATT; the app treats the matching result as
the command outcome.

The readable device-information characteristic is
`000c-9c65-4d3d-bdd5-8f4c6b2e1000`. Its semicolon-separated UTF-8 value
contains the firmware version, hardware revision and supported BLE contracts.
