# ShotStopper firmware flow (`examples/shotStopper/shotStopper.ino`)

A map of *what* the firmware does and *when*, focused on the shot lifecycle, the
auto-tare points, and the app↔device config path. Line numbers refer to
`shotStopper.ino` at the time of writing (firmware v2 / app build v3.3.0).

Target board: **ESP32-C3** (`build/esp32.esp32.esp32c3`). Prebuilt images are baked
per switch config: `shotStopper_app_v3.3.0_mom{0,1}_reed{0,1}.bin`
(`mom` = momentary, `reed` = reed switch).

---

## Sections

| Section | Lines | What it does |
|---|---|---|
| Config & globals | 28–149 | Tunables (`autoTare`, `momentary`, `reedSwitch`, `enabled`, `minShotDurationS`, `maxShotDurationS`, `FIRST_DROP_G=1.0`); `Shot` struct; live flags (`buttonPressed`, `buttonLatched`, `firstDropTared`, `requireRelease`). |
| BLE characteristics | 151–168 | One characteristic per setting. `autoTare` = `0xFF14` (`Write|Read`), telemetry = `0xFF25` (`Read|Notify`, 16 bytes). |
| Telemetry / status | 186–238 | `sendTelemetryFrame()` packs the 16-byte frame; `updateBLEShotStatus()` notifies brew on/off. |
| EEPROM | 240–306 | `loadOrInitEEPROM()` restores config from flash at boot (writes defaults on first run). |
| `pollAndReadBLE()` | 354–425 | Each loop: apply any characteristic the app wrote, persist to EEPROM. |
| `setup()` | 427–446 | EEPROM load → GPIO → BLE. |
| `loop()` | 450–681 | The main cycle (below). |
| `setBrewingState()` | 683–744 | Brew-start tare + relay pulse/unlatch on stop. |

### Two facts that explain the "150 g cup" symptom

1. **Telemetry weight is absolute** (L191: `weight_g = currentWeight`). The firmware
   sends the raw scale reading. If it hasn't tared, the cup's 150 g streams straight
   to the app.
2. **The app's REC vs IDLE state comes from `shot.brewing`** (L544:
   `sendTelemetryFrame(shot.brewing ? TELEM_BREW : TELEM_IDLE)`). If the firmware
   never detected the brew, the app shows **IDLE** even while the weight climbs.

---

## `loop()` — each cycle

```
┌─ pollAndReadBLE()        apply app config writes (e.g. autoTare → EEPROM)
├─ updateBLEShotStatus / updateBLEWifiIp
├─ enabled==false OR OTA mode?  ──yes──► stop shot, disconnect scale, RETURN
├─ scale connected?  ──no──► scale.init(); still not connected? RETURN
├─ heartbeat the scale periodically
│
├─ NEW WEIGHT SAMPLE?  ──yes──►  currentWeight = scale.getWeight()
│        │
│        ├─ shot.brewing && !TIMER_ONLY?
│        │     └─►  ╔═ FIRST-DROP RE-TARE (L516) ═══════════════╗
│        │          ║ if buttonLatched && autoTare              ║
│        │          ║    && !firstDropTared && currentWeight>1g ║──► scale.tare(); restart t=0
│        │          ╚══════════════════════════════════════════╝
│        │          record trajectory point; calculateEndTime()
│        └─►  sendTelemetryFrame(brewing ? BREW : IDLE)   ← app REC/IDLE decided here
│
└─ BUTTON STATE MACHINE (debounced read of the `in` pin, active-low):
     ① START    newButtonState && !buttonPressed && !requireRelease
                   └─ if (!momentary || reedSwitch):
                         shot.brewing = true; setBrewingState(true) ─►╔ BREW-START TARE ╗
                                                                      ║ if(autoTare)     ║
                                                                      ║   scale.tare()   ║
                                                                      ╚══════════════════╝
     ② LATCH    !momentary && brewing && !buttonLatched && shotTimer>minShotDurationS
                   └─ buttonLatched = true; OUT = HIGH   (firmware takes over; no tare here)
     ③ RELEASE  !buttonLatched && button released → toggle brewing → setBrewingState(...)
     ④ MAX DUR  brewing && shotTimer > maxShotDurationS → end = TIME → setBrewingState(false)
     ⑤ WEIGHT   brewing && shotTimer >= expected_end_s && shotTimer>minShotDurationS
                   → end = WEIGHT → setBrewingState(false)
     ⑥ DRIP     goal reached + dripDelayS elapsed → measure final weight, learn weightOffset
```

`setBrewingState(false)` (stop): pulses `OUT` for momentary machines, or unlatches +
sets `requireRelease=true` for latching machines (so a still-raised paddle doesn't
immediately restart the next shot), and emits the final `TELEM_DONE` frame.

---

## The two auto-tare points

|  | Brew-start tare (L693) | First-drop re-tare (L516) |
|---|---|---|
| Code | `setBrewingState(true)` → `if(autoTare) scale.tare()` | weight loop, after latch |
| Gate | `autoTare` | `buttonLatched && autoTare && currentWeight>1g && !firstDropTared` |
| Reached when | shot starts via `(!momentary \|\| reedSwitch)` (state ①/③) | only after LATCH ②, which needs `!momentary` |
| Latching machine (Micra, `momentary=false`) | ✔ wired | ✔ wired (latches after `minShotDurationS`) |
| Momentary machine **without** reed | ✘ start path skipped **and** never latches → **no tare at all** | ✘ |

> Firmware gap worth noting: a **momentary** switch with **no reed** gets neither tare,
> because state ① requires `(!momentary || reedSwitch)` and the first-drop re-tare
> requires `buttonLatched` (which needs `!momentary`). Not your Micra, but a real hole.

---

## Config path: app → device → confirm

```
app writes 0xFF14 (autoTare)  ──BLE write──►  pollAndReadBLE(): autoTare = value; EEPROM.write
app reads  0xFF14 back        ◄─BLE read───  characteristic returns the stored value
```

The app (`ShotStopperClient`) now **reads every byte write back** and compares it to
what it sent (`syncState` → `.synced` / `.mismatch`). A `.mismatch` means the device
didn't accept/persist the value — surfaced as "Sent / Not applied" on Live and a
"Change didn't apply" banner in Settings.

---

## Diagnosing "auto-tare didn't fire" (Micra, `momentary=false`)

The brew-start tare path is wired for a latching machine, so narrow it with the app:

1. **App shows IDLE (not REC) while weight climbs** → the firmware never saw the brew
   (state ① didn't run). Cause: `in`-pin / `reedSwitch` / `momentary` wiring-vs-config
   mismatch — check you flashed the matching `mom?_reed?` image, and that Settings'
   read-back values agree with your wiring.
2. **App shows REC, and Auto-tare reads back as "Not applied"** → the `autoTare` flag
   isn't landing/persisting on the device. The read-back confirmation now catches this.
3. **App shows REC, Auto-tare reads back OK ("Sent"), but no zero** → `scale.tare()` was
   issued but the Acaia didn't act. Scale-link / protocol (`AcaiaArduinoBLE.cpp`).

Serial-log breadcrumbs (over USB) to confirm timing: `ButtonPressed` → `shot started`
→ (`Button Latched`) → `first drop detected - tared, measuring from here`.
