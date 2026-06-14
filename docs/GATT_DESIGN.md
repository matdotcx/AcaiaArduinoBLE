# ShotStopper Telemetry — GATT Wire Contract

The single source of truth shared by the **firmware** (ArduinoBLE peripheral) and the
**telemetry app** (iOS / watchOS). Both sides must agree byte-for-byte. Changing the
frame layout or UUIDs means changing both.

## Stack context

The firmware peripheral runs on **ArduinoBLE** (controller-only on ESP32 — *not*
NimBLE or Bluedroid). It already exposes a peripheral GATT service `0x0FFE`
(`shotStopperService` in `examples/shotStopper/shotStopper.ino`) used by the existing
config app. Telemetry is added as **one new characteristic on that same service** — no
new 128-bit service, no stack migration.

> The 2026 Claude-Desktop design doc proposed a separate 128-bit service
> `C0FFEE00-7A11-4B0D-9E2A-…`. We deliberately **do not** use it: the existing service
> and all its characteristics use Bluetooth-SIG short (16-bit) UUIDs, and a single
> live-stream characteristic fits naturally alongside them. Staying 16-bit keeps the
> peripheral uniform and avoids a parallel service for no benefit.

## Connection model

During a brew the ShotStopper holds exactly two BLE links:

- **Central** → the scale (Acaia/Bookoo), owned by the `AcaiaArduinoBLE` class.
- **Peripheral** → exactly **one** viewer (iPhone *or* Apple Watch, never both).

The config app is **not** connected during a brew. This permanent single-viewer model
is well within ArduinoBLE's limits; multi-central / NimBLE is not required.

## Service & characteristics

Service UUID: **`0x0FFE`** (existing `shotStopperService`).

| Char UUID | Properties        | Name        | Payload                                   |
| --------- | ----------------- | ----------- | ----------------------------------------- |
| `0xFF25`  | Read \| Notify    | telemetry   | 16-byte frame (below). New — this feature |

Existing characteristics on the same service, for reference (already shipped):

| UUID     | Properties      | Meaning                                             |
| -------- | --------------- | --------------------------------------------------- |
| `0xFF11` | Write \| Read   | **setpoint** (goal weight, grams, uint8) — config app writes this |
| `0xFF19` | Read \| Notify  | scale status (0 disconnected, 1 connected)          |
| `0xFF20` | Read \| Notify  | shot status (0 idle, 1 brewing)                     |
| `0xFF18` | Read            | firmware version                                    |
| `0xFF10`,`0xFF12`–`0xFF17`,`0xFF21`–`0xFF24` | various | enabled / reed / momentary / autotare / durations / dripDelay / OTA / wifi |

## Telemetry frame — 16 bytes, little-endian

| Offset | Type    | Field         | Notes                                                      |
| ------ | ------- | ------------- | ---------------------------------------------------------- |
| 0      | uint32  | `t_ms`        | ms since shot start; `0` when idle                         |
| 4      | float32 | `weight_g`    | live weight from the scale (`currentWeight`)               |
| 8      | float32 | `flow_gps`    | grams/second, derived from the weight/time slope           |
| 12     | uint8   | `state`       | see enum below                                             |
| 13     | uint8   | `flags`       | bit0 `scaleConnected` · bit1 `setpointReached`             |
| 14     | uint16  | `setpoint_cg` | target grams × 100 (`goalWeight * 100`)                    |

16 bytes ≤ the 20-byte payload of the default 23-byte ATT MTU, so it streams with **no
MTU negotiation**. ESP32 and Apple silicon are both little-endian IEEE-754, so a raw
copy decodes cleanly with Swift's `Float(bitPattern:)`.

### `state` enum

| Value | Name      | Emitted by firmware?                                  |
| ----- | --------- | ----------------------------------------------------- |
| 0     | idle      | ✅ when `!shot.brewing`                                |
| 1     | preinfuse | ⛔ reserved — firmware does not track this yet          |
| 2     | brew      | ✅ when `shot.brewing`                                  |
| 3     | settle    | ⛔ reserved — firmware does not track this yet          |
| 4     | done      | ✅ briefly at shot completion (drip/end)                |

The firmware currently tracks only `shot.brewing` (bool) plus an `ENDTYPE` at
completion, so it emits **idle / brew / done**. That is sufficient for the app to
auto-delimit shots (fresh curve on `brew`, close on `done`, ignore `idle`). `preinfuse`
and `settle` are reserved values for a future firmware enhancement; the field stays a
`uint8`, so adding them is non-breaking.

### `flags` bits

| Bit | Name             | Source                                          |
| --- | ---------------- | ----------------------------------------------- |
| 0   | `scaleConnected` | `scale.isConnected()`                           |
| 1   | `setpointReached`| `currentWeight >= goalWeight - weightOffset`    |

## Emission cadence

The frame is written from inside `if (scale.newWeightAvailable())` in the main loop,
i.e. **once per fresh scale sample** (~10 Hz for an Acaia Lunar). No separate timer —
the scale's notify rate is the natural cadence; oversampling past it would only send
duplicate frames.

## Decoding (Swift sketch)

```swift
struct TelemetryFrame {
    let tMs: UInt32, weightG: Float, flowGps: Float
    let state: UInt8, flags: UInt8, setpointCg: UInt16

    init?(_ d: Data) {
        guard d.count >= 16 else { return nil }
        tMs        = d.loadLE(0)
        weightG    = Float(bitPattern: d.loadLE(4))
        flowGps    = Float(bitPattern: d.loadLE(8))
        state      = d[12]; flags = d[13]
        setpointCg = d.loadLE(14)
    }
    var scaleConnected: Bool  { flags & 0x01 != 0 }
    var setpointReached: Bool { flags & 0x02 != 0 }
    var setpointG: Float      { Float(setpointCg) / 100 }
}
```
(`loadLE` = little-endian fixed-width load; implement with `withUnsafeBytes`.)

## Versioning

If the frame ever changes, bump the firmware version (`0xFF18`) and have the app gate on
it. Prefer **append-only** changes (use reserved `state` values, spare `flags` bits)
over re-laying existing offsets.
