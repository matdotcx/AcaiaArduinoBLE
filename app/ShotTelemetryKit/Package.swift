// swift-tools-version: 5.9
import PackageDescription

// Shared core for the ShotStopper telemetry app (iOS + watchOS).
// Logic only — no SwiftUI views, no SwiftData — so it builds and runs on macOS.
//
// Two ways to validate the core:
//   • `swift run smoke`  — assertion smoke test, runs anywhere (no Xcode needed)
//   • `swift test`       — full XCTest suite, requires full Xcode (XCTest SDK)
let package = Package(
    name: "ShotTelemetryKit",
    platforms: [
        .iOS(.v17),     // SwiftData + Observation in the app targets
        .watchOS(.v10),
        .macOS(.v14),   // lets the core build/run on the dev Mac
    ],
    products: [
        .library(name: "ShotTelemetryKit", targets: ["ShotTelemetryKit"]),
    ],
    targets: [
        .target(name: "ShotTelemetryKit"),
        .executableTarget(name: "smoke", dependencies: ["ShotTelemetryKit"], path: "Smoke"),
        .testTarget(name: "ShotTelemetryKitTests", dependencies: ["ShotTelemetryKit"]),
    ]
)
