# CLAUDE.md

> Tip: run `/init` to generate a fuller hierarchical baseline from a repo scan, then keep
> the sections below. The blocks here are the project-specific quality bar that the
> `/audit` and `/fix` commands rely on.

## Project shape
- The Xcode project and Swift package live under `app/` (not the repo root):
  `app/ShotStopperTelemetry.xcodeproj`, `app/ShotTelemetryKit`.
- Schemes: `ShotStopperTelemetry` (iOS), `ShotStopperTelemetryWatch` (watchOS).
- `app/ShotTelemetryKit/` builds with plain `swift build`/`swift test` — prefer this for logic tests.
- `app/AppShared/` and the app targets require `xcodebuild` (SwiftData `@Model` macro).
- `#if DEBUG` enables a pour simulator — UI tests in Simulator do NOT need the espresso machine.
- BLE frame: 16 bytes, little-endian, service `0x0FFE`, telemetry char `0xFF25`. Decode lives in `app/ShotTelemetryKit`.
- CloudKit sync requires every `@Model` property to be optional or defaulted; local-store fallback when unsigned.

## Quality bar (applies to every change)
- Swift Testing unit test for any logic touched in `app/ShotTelemetryKit`.
- `swiftlint --strict` clean. Functions <~50 lines, files <400 lines.
- Match existing `swift-format` style — do not reformat unrelated code.
- Both schemes build; iOS scheme tests pass; app installs on attached device.
- Update this file and `app/README.md` if behaviour or setup changes.

## Verification commands (canonical — do not alter)
    swift test --package-path app/ShotTelemetryKit
    xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' build test
    xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetryWatch -destination 'generic/platform=watchOS' build
    swiftlint --strict

## Anti-reward-hacking (non-negotiable)
Never disable, relax, skip, stub, or comment out tests or lint rules to achieve a passing state. Never catch-and-ignore. Never edit `.swiftlint.yml` or scheme test plans to exclude failures. If something cannot be fixed honestly, report it as unfixed with the reason. A reported failure is success; a hidden failure is the only true failure.
