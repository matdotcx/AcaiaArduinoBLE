# ShotStopper Telemetry App

Read-only brew-data capture, graphing, and export client for the ShotStopper
firmware. See [`../docs/TELEMETRY_PLAN.md`](../docs/TELEMETRY_PLAN.md) and
[`../docs/GATT_DESIGN.md`](../docs/GATT_DESIGN.md).

## Layout

```
app/
├── ShotStopperTelemetry.xcodeproj   iOS app project (builds; open this in Xcode)
├── ShotStopperTelemetry/        iOS app target — SwiftUI
│   ├── ShotStopperTelemetryApp.swift   @main, ModelContainer wiring
│   ├── AppModel.swift                  owns client + recorder, wires onFrame
│   ├── ContentView.swift               Live / History tabs
│   ├── LiveShotView.swift              live weight chart + readouts
│   ├── ShotHistoryView.swift           @Query list of saved shots
│   └── ShotDetailView.swift            saved-shot chart + CSV/JSON export
├── ShotTelemetryKit/            Swift package — the pure, testable core
│   ├── Sources/ShotTelemetryKit/
│   │   ├── TelemetryGATT.swift      BLE UUIDs (service 0x0FFE, telemetry 0xFF25)
│   │   ├── TelemetryFrame.swift     16-byte LE frame decode/encode
│   │   ├── ShotSegmenter.swift      pure state machine → shot boundaries
│   │   ├── ShotStopperClient.swift  CoreBluetooth central (read-only, auto-reconnect)
│   │   └── ShotExport.swift         CSV/JSON serializers
│   ├── Smoke/main.swift             assertion smoke test (no Xcode needed)
│   └── Tests/                       XCTest suite (needs full Xcode)
└── AppShared/                Xcode-only sources (SwiftData @Model macro)
    ├── Models.swift                 Shot / ShotSample @Model
    ├── ShotRecorder.swift           frames → persisted shots
    └── ShotExport+Shot.swift        bridge Shot → ShotExport
```

The `.xcodeproj` already references the package as a local dependency and pulls in
the `AppShared/` files. Open it in Xcode and it builds as-is. (The app target is
unsigned and intended for the Simulator until a Developer team is set.)

### Why the split

SwiftData's `@Model` macro plugin only loads under Xcode's build system, so the
SwiftData layer (`AppShared/`) cannot be compiled by a plain `swift build`. The
package therefore holds only SwiftData-free code, which keeps it buildable and
runnable on any toolchain. When you create the Xcode project, add both the
package (as a local dependency) **and** the `AppShared/` files (to the app and
watch targets).

## Validate the core

```sh
cd ShotTelemetryKit
swift run smoke     # assertion smoke test — runs anywhere
swift test          # full XCTest suite — requires full Xcode (XCTest SDK)
```

## Wiring (in the app target)

```swift
let client = ShotStopperClient()
let recorder = ShotRecorder(context: modelContext)   // SwiftData ModelContext
client.onFrame = { recorder.ingest($0) }
client.start()
// Live chart binds to recorder.liveFrames; history is a @Query on Shot.
```

## Done

- iOS app target: live Swift Charts view, shot history, CSV/JSON export — builds for
  the Simulator (`** BUILD SUCCEEDED **`).

## Still to build (Xcode)

- watchOS target: kiosk chart + extended runtime session (shares the package +
  `AppShared/`).
- SwiftData + CloudKit container for phone↔watch sync (swap the `ModelConfiguration`
  in `ShotStopperTelemetryApp.swift`).
- Set a Developer team for on-device runs (signing + iCloud/CloudKit entitlements).
  `NSBluetoothAlwaysUsageDescription` is already set via build settings.
- Hardware validation: flash the firmware, confirm `0xFF25` frames decode live.
