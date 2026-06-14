# ShotStopper Telemetry App

Read-only brew-data capture, graphing, and export client for the ShotStopper
firmware. See [`../docs/TELEMETRY_PLAN.md`](../docs/TELEMETRY_PLAN.md) and
[`../docs/GATT_DESIGN.md`](../docs/GATT_DESIGN.md).

## Layout

```
app/
├── ShotStopperTelemetry.xcodeproj   iOS + watchOS project (both build; open in Xcode)
├── ShotStopperTelemetry/        iOS app target — SwiftUI
│   ├── ShotStopperTelemetryApp.swift   @main, ModelContainer via SharedStore
│   ├── ContentView.swift               Live / History tabs
│   ├── LiveShotView.swift              live weight chart + readouts
│   ├── ShotHistoryView.swift           @Query list of saved shots
│   ├── ShotDetailView.swift            saved-shot chart + CSV/JSON export
│   └── ShotStopperTelemetry.entitlements   iCloud/CloudKit container
├── ShotStopperTelemetryWatch/   watchOS kiosk target — SwiftUI
│   ├── WatchApp.swift                  @main (shares SharedStore + AppModel)
│   ├── WatchKioskView.swift            full-screen live readout + curve
│   ├── KioskKeepAwake.swift            WKExtendedRuntimeSession (screen stays on)
│   ├── Info.plist                      WKApplication + WKBackgroundModes (self-care)
│   └── ShotStopperTelemetryWatch.entitlements   same iCloud container (sync)
├── ShotTelemetryKit/            Swift package — the pure, testable core
│   ├── Sources/ShotTelemetryKit/
│   │   ├── TelemetryGATT.swift      BLE UUIDs (service 0x0FFE, telemetry 0xFF25)
│   │   ├── TelemetryFrame.swift     16-byte LE frame decode/encode
│   │   ├── ShotSegmenter.swift      pure state machine → shot boundaries
│   │   ├── ShotStopperClient.swift  CoreBluetooth central (read-only, auto-reconnect)
│   │   └── ShotExport.swift         CSV/JSON serializers
│   ├── Smoke/main.swift             assertion smoke test (no Xcode needed)
│   └── Tests/                       XCTest suite (needs full Xcode)
└── AppShared/                Xcode-only sources, compiled into BOTH app targets
    ├── Models.swift                 Shot / ShotSample @Model
    ├── ShotRecorder.swift           frames → persisted shots
    ├── ShotExport+Shot.swift        bridge Shot → ShotExport
    ├── AppModel.swift               owns client + recorder, wires onFrame
    └── SharedStore.swift            CloudKit-or-local ModelContainer factory
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

## CloudKit sync (phone ↔ watch)

Already wired in code:
- `ShotStopperTelemetryApp.swift` opens the store with
  `ModelConfiguration(cloudKitDatabase: .automatic)` — syncs to the user's **private**
  CloudKit DB when the iCloud entitlement is active, and falls back to a local store
  otherwise (so the unsigned Simulator build still runs).
- `ShotStopperTelemetry.entitlements` declares the container
  `iCloud.org.iaconelli.ShotStopperTelemetry`, the CloudKit service, and `aps-environment`.
- The `Shot` / `ShotSample` models are CloudKit-compatible (all attributes defaulted,
  the relationship optional with an inverse, no `.unique`).

To activate it (one-time, needs a paid Apple Developer team):
1. In Xcode → target → **Signing & Capabilities**, select your Team (enables signing).
2. Confirm the **iCloud** capability shows **CloudKit** ticked with the container above
   (Xcode creates the container on first use; rename it to match your team's prefix if
   needed, and update the entitlement + the `.automatic` container resolves it).
3. Run on two devices signed into the same iCloud account — shots reconcile automatically.

Still TODO for background push sync: add **Background Modes → Remote notifications**
(`UIBackgroundModes = remote-notification`). Foreground/launch sync works without it.

## watchOS kiosk

The `ShotStopperTelemetryWatch` target is a standalone watch app for the unit mounted
(strapless) on the machine. It reuses the package, `AppShared/`, and the same recorder;
`WatchKioskView` shows a big live weight readout, compact stats, and the pour curve.
`KioskKeepAwake` starts a `WKExtendedRuntimeSession` (Info.plist `WKBackgroundModes =
self-care`) so the screen stays on through a pour instead of dimming to the clock.
It declares the **same** iCloud container as the phone, so history syncs via CloudKit.
Both targets build for their simulators (`** BUILD SUCCEEDED **`).

## Still to build / verify (Xcode + hardware)

- App icons / asset catalogs (cosmetic; not required to build or run).
- Run each app in its Simulator once runtimes are installed.
- Hardware validation: flash the firmware, confirm `0xFF25` frames decode live.
