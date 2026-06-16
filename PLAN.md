# ShotStopperTelemetry — Fix Plan

Waypoints are ordered by (risk reduced × effort⁻¹). Each leaves the app buildable and
device-installable. Rollback for every waypoint: `git checkout audit/2026-06-16-af5b177`
(then discard the waypoint's commits) — stated once here, true for all.

Baseline verification commands (run after every waypoint):

    swift test --package-path app/ShotTelemetryKit
    xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'generic/platform=iOS' build
    xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetryWatch -destination 'generic/platform=watchOS' build

(The CLAUDE.md `… build test` form will keep failing until W4 adds a test action; until then
use the `build` form above for the app targets.)

---

## W1: Stop the OTA-upload crash  —  est. S
Fixes: F-001
Rationale: A definite runtime trap on the headline OTA path; smallest, highest-value change.
The fix is local to `FirmwareUploader` and unit-testable in the package.
Approach: replace `MainActor.assumeIsolated` in the `didSendBodyData` delegate with a real hop
(`Task { @MainActor in … }`) or give the uploader a dedicated `URLSession(delegateQueue: .main)`.
Add a package test that drives `urlSession(_:task:didSendBodyData:…)` off the main actor and
asserts no trap + correct `.uploading(fraction)` progression.
Verification: `swift test --package-path app/ShotTelemetryKit` (new progress test) + the two
build commands above.

## W2: Honest persistence + safe store open  —  est. S/M
Fixes: F-003, F-004
Rationale: Both are error-handling correctness in the SwiftData layer; touch the same area and
ship together. F-003 prevents silent shot loss; F-004 removes a launch-crash path.
Approach:
- Replace `try? context.save()` with a helper that logs (and, for `ShotRecorder.finalize`,
  surfaces a recoverable "not saved" state instead of setting `lastCompletedShot` on failure).
- Wrap the `SharedStore` fallback `try!` in a `do/catch` that degrades to an in-memory container
  (or a clearly-reported failure) rather than trapping.
Verification: app builds; manual Simulator pass — pull a simulated shot, confirm it still lands
in History; both build commands above.

## W3: Watch kiosk reliability  —  est. S
Fixes: F-002, F-005
Rationale: Both are watch-target behaviour; small and isolated.
Approach:
- In `KioskKeepAwake.extendedRuntimeSessionWillExpire` (and/or `didInvalidateWith` for the
  timed-out reason), start a fresh session so the kiosk stays awake — matching the doc comment.
- Make the Release "Start" pill either perform a real action or render as non-interactive status
  (remove the tappable affordance outside DEBUG).
Verification: `xcodebuild -scheme ShotStopperTelemetryWatch -destination 'generic/platform=watchOS' build`;
watch Simulator smoke (`-demo`).

## W4: Restore the documented test gate  —  est. M
Fixes: F-006 (and unblocks the CLAUDE.md `build test` command)
Rationale: The canonical verification command currently fails (exit 66). Add a minimal iOS unit
test target/scheme test action so `xcodebuild … build test` runs. NOTE: this edits the Xcode
project — out of scope for a pure logic fix, do it deliberately. Do **not** "fix" it by removing
`test` from CLAUDE.md.
Approach: add an app test target (even a thin one that exercises `Shot.statusTag`,
`ShotExport(shot)` bridging, and `ShotRecorder` finalize against an in-memory `ModelContainer`),
wire it into the scheme's Test action.
Verification: `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' build test` exits 0.

## W5: Cleanups  —  est. S
Fixes: F-008, F-009, F-010, F-011
Rationale: Low-risk hygiene, batched last so they don't churn the diffs that matter.
Approach: split `DesignSystem.swift` into Tokens/Components/Charts (<400 each); either consume or
drop the `scaleStatus`/`shotStatus` subscriptions; add dedup + recipe identity to DEBUG
`seedHistory`; make export temp filenames unique (append the shot UUID/seconds).
Verification: both build commands; `swift test` for any touched package code.

---

## Out of scope for automated fix (need a human decision)

- **F-007 (SwiftLint not installed):** environment/tooling decision — install swiftlint in the dev/CI
  environment so the `swiftlint --strict` quality gate can actually run. No code change.
- **F-012 (`momentary` / `reedSwitch` / `dripDelay` UI):** product decision — are these meant to be
  user-facing in Settings, or intentionally hidden? Answer determines whether to add UI or remove the
  unused setters. Question: which device toggles should the app expose vs. leave to the firmware/recipe?
- **OTA protocol / ATS cleartext HTTP:** the uploader POSTs over plain HTTP to a LAN device via an ATS
  exception. Not a bug, but any change to the transport is a protocol decision, not an automated fix.
- **CloudKit schema:** verifying/altering the synced schema needs a signed build + iCloud account and a
  human in the loop; not automatable here.
