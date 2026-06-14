# ShotStopper Telemetry — UI screenshots

Current state of the app for a UI-polish pass. The bones work; the styling is
default SwiftUI. Captured in the iOS 26.5 / watchOS 26.5 Simulators (no Bluetooth
in the Simulator, so the connection status reads "Idle" — on hardware it shows the
device name and live data). Shot data here is from the built-in demo simulator.

| File | Screen | Notes |
| --- | --- | --- |
| `ios-1-live-idle.png` | iPhone · Live (idle) | Connection status, Weight/Time/Flow/Target readouts, empty chart, Live/History tabs. |
| `ios-2-live-pour.png` | iPhone · Live (recording) | Mid-pour: live readouts, red REC indicator, weight curve building toward the dashed target line. |
| `ios-3-history.png` | iPhone · History | List of saved shots (date · final weight · duration · target). Toolbar: Export (share) + DEBUG "Add Samples". |
| `ios-4-detail-export.png` | iPhone · Shot detail | Weight-vs-time curve with dashed target line, summary grid, Export CSV / Export JSON buttons. |
| `ios-5-settings.png` | iPhone · Settings | Read/write machine config over BLE: target weight, toggles, durations. (Disabled until connected on hardware.) |
| `ios-6-ota.png` | iPhone · Firmware OTA | Send WiFi + start OTA mode, then pick a .bin from Files / iCloud Drive and upload it to the device in-app (web-uploader fallback also shown). |
| `watch-1-idle.png` | Watch · Kiosk (idle) | Big weight readout, compact time/flow/target row, chart. Strapless on the machine as an always-on display. |
| `watch-2-pour.png` | Watch · Kiosk (recording) | Live pour: big weight, stats row, curve building to the target line. |

## Design intent / brand
- It's a brew-by-weight espresso companion. Glanceable, calm, used wet-handed at the machine.
- Existing brand cue (from the firmware's web UI and the app icon): warm cream `#E9E7E0`
  background, espresso orange accent `#E84B29`, near-black text `#111110`.
- The chart's dashed line is the **target weight**; the solid line is **live weight vs time**.
- Two surfaces: a glanceable **phone** (live + history + export) and a **watch kiosk**
  (live only, large type, readable from across the counter).

## Not styled yet (fair game)
App icon is a placeholder; typography/spacing are SwiftUI defaults; no color theming,
empty states are minimal, the watch face is bare. Charts are stock Swift Charts.
