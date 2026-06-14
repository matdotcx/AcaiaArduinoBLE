# ShotStopper Telemetry — Implementation Plan

Live shot-telemetry streaming from the ShotStopper firmware to a new **read-only**
brew-data app on **iPhone or Apple Watch**. Goal: capture each shot's weight/flow/time
curve, graph it, persist it, and **export to iCloud Drive on demand**.

See [`GATT_DESIGN.md`](./GATT_DESIGN.md) for the byte-level wire contract.

## Goal & non-goals

**Goal:** get brew data out of the machine, graph it, keep it, export it.

- Live weight-vs-time curve during the pour (~10 Hz).
- Numeric readouts: weight, elapsed time, flow, setpoint, state.
- Per-shot history, persisted on device.
- Export selected shots as CSV / JSON to iCloud Drive, as and when the user likes.
- Sync history between the user's iPhone and Apple Watch.

**Non-goals:**

- Not a machine-control remote. Setpoint/config stays in the existing
  `icapurro/shotStopperCompanionApp` (config-only, not connected during a brew).
- No simultaneous phone + watch viewing — one viewer at a time, by design.
- No firmware-side history storage — the app reconstructs shots from the live stream.

## Connection model (settled)

During a brew: scale (central) + **one** viewer (peripheral). The config app is not
connected. This permanent single-viewer model fits **ArduinoBLE** — **NimBLE migration
is not needed and is out of scope.**

## Apple Watch rationale

A spare watch mounted (no strap) on the machine as an **always-on kiosk display**. This
is the only reason for the watchOS target. It implies designing for watchOS's
Always-On / sleep behaviour (see Phase 4).

---

## Phase 1 — Firmware delta (small, OTA-safe)

All hook points are in `examples/shotStopper/shotStopper.ino`.

1. **Declare** the characteristic near the others (~line 161):
   ```cpp
   BLECharacteristic telemetryCharacteristic("0xFF25", BLERead | BLENotify, 16);
   ```
2. **Register** it in `initializeBLE()` (~line 282), alongside the other
   `shotStopperService.addCharacteristic(...)` calls.
3. **Pack & notify** inside `if (scale.newWeightAvailable())` (~line 457), right after
   `currentWeight = scale.getWeight();`. Build the 16-byte little-endian frame and
   `telemetryCharacteristic.writeValue(buf, 16)`. Also emit one final `state = done`
   frame at shot completion so the app can close the curve.

   Field sources:
   | Frame field   | Source                                             |
   | ------------- | -------------------------------------------------- |
   | `t_ms`        | `shot.shotTimer * 1000` (0 when `!shot.brewing`)    |
   | `weight_g`    | `currentWeight`                                    |
   | `flow_gps`    | weight/time slope (same `M` used in `calculateEndTime`) |
   | `state`       | `shot.brewing` → 2 brew / 0 idle; 4 done at end     |
   | `flags`       | bit0 `scale.isConnected()`, bit1 `currentWeight >= goalWeight - weightOffset` |
   | `setpoint_cg` | `goalWeight * 100`                                 |
4. **Re-advertise on disconnect** — already handled (`BLE.advertise()`, lines 299/305).

**Open firmware item:** decide how `flow_gps` is surfaced. `calculateEndTime()` already
computes a slope; either reuse it or compute a short-window delta-weight/delta-time in
the loop. Pick whichever gives a stable curve (the end-time slope may be smoothed).

**Cost / fit:** low-single-digit KB flash, a few hundred bytes RAM. Current binary
≈ 1.21 MB of the 1.25 MB app slot (~92%); this still fits. **No repartition required**
for this feature. (`min_spiffs` remains available as optional headroom, unrelated.)

**State mapping caveat:** firmware emits idle/brew/done only. `preinfuse`/`settle` are
reserved in the frame for later; not blocking.

## Phase 2 — Shared Swift core

A small package reused by both app targets:

- **Wire layer:** UUIDs (`0x0FFE` / `0xFF25`), `TelemetryFrame` decoder
  (`Float(bitPattern:)`), per `GATT_DESIGN.md`.
- **BLE client:** CoreBluetooth central — auto-scan for `shotStopper`, connect,
  subscribe to `0xFF25`, auto-reconnect on drop. (Read-only; no writes.)
- **Persistence model (SwiftData):**
  - `Shot` — date, setpoint(g), peak weight, duration, machine id, optional notes.
  - `Sample` — `tMs`, `weightG`, `flowGps`, `state`; child of `Shot`.
  - The client accumulates frames into the current `Shot` using `state`: a `brew`
    frame after idle opens a new shot; `done` (or return to idle) closes it.
  - Volume is trivial: a 30 s shot ≈ 300 samples ≈ ~5 KB.

## Phase 3 — Sync & export

- **Sync (phone ↔ watch): SwiftData + CloudKit private database.** Each device persists
  locally and syncs to the user's private iCloud independently; CloudKit reconciles.
  Because the devices never run simultaneously, this asynchronous model is the right
  fit (no WatchConnectivity peer session needed). Configure via a CloudKit-backed
  `ModelConfiguration`. Requires a CloudKit container in the Apple Developer account and
  the iCloud capability on both targets.
- **Export to iCloud Drive (on demand):**
  - **CSV** per shot (`t_ms,weight_g,flow_gps`) — opens in Numbers/Excel/Python.
  - **JSON** option for full fidelity (shot metadata + samples).
  - Surface via the Files document picker (or the app's iCloud Drive container so
    exports appear in Files automatically). User-initiated, "as and when."

## Phase 4 — App targets

- **iOS (iOS 16+, Swift Charts):** live chart (weight vs time, dashed setpoint
  reference line), numeric readouts, shot-history list, export action.
  `NSBluetoothAlwaysUsageDescription` **required** in Info.plist or the first scan fails
  silently.
- **watchOS (kiosk):** same core; full-screen live chart. Needs an **extended runtime
  session** (and/or Always-On dimmed-state design) so the curve stays visible through a
  ~30 s pour without the screen sleeping. `NSBluetoothAlwaysUsageDescription` required
  here too. Account for power (mounted on the machine → keep a charger near it).

## Sequencing

1. Firmware delta (Phase 1) — verify it builds and fits, confirm frames on nRF Connect.
2. Shared core (Phase 2) — decode + BLE + SwiftData models against the real stream.
3. iOS app (Phase 4 iOS) + export (Phase 3 export).
4. CloudKit sync (Phase 3 sync).
5. watchOS kiosk (Phase 4 watchOS).

## Open items / risks

- **`flow_gps` derivation** — choose stable source (Phase 1 open item).
- **`ShotStopperTelemetry.h`** from the prior session is **NimBLE** — do not drop in;
  the firmware delta is ~15 lines of ArduinoBLE instead.
- **`shot.weight[1000]/time_s[1000]`** are fixed-size; pours past 1000 datapoints
  already overflow in current firmware — out of scope here but adjacent.
- **CloudKit setup** is the main non-code dependency (developer account container +
  entitlements).
- **Missed-shot capture:** the app only has data while connected. For the phone that
  means opening the app before/during the shot; the watch kiosk is always connected.
  Firmware-side "last shot" buffering for later retrieval is possible but is bulk BLE
  transfer — deliberately deferred.
