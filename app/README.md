# ShotStopper Telemetry App

Read-only brew-data capture, graphing, and export client for the ShotStopper
firmware. See [`../docs/TELEMETRY_PLAN.md`](../docs/TELEMETRY_PLAN.md) and
[`../docs/GATT_DESIGN.md`](../docs/GATT_DESIGN.md).

## Layout

```
app/
├── ShotTelemetryKit/         Swift package — the pure, testable core
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

## Still to build (Xcode)

- iOS app target: live Swift Charts view, shot history, export to iCloud Drive.
- watchOS target: kiosk chart + extended runtime session.
- SwiftData + CloudKit container for phone↔watch sync.

These need an Xcode project + an Apple Developer team (CloudKit container,
Bluetooth + iCloud entitlements, `NSBluetoothAlwaysUsageDescription`).
