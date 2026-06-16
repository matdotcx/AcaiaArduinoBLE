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

## W1: Stop the OTA-upload crash  —  est. S  —  ✅ done (23ae2c4)
Fixes: F-001 (fixed)
Rationale: A definite runtime trap on the headline OTA path; smallest, highest-value change.
The fix is local to `FirmwareUploader` and unit-testable in the package.
Approach: replace `MainActor.assumeIsolated` in the `didSendBodyData` delegate with a real hop
(`Task { @MainActor in … }`) or give the uploader a dedicated `URLSession(delegateQueue: .main)`.
Add a package test that drives `urlSession(_:task:didSendBodyData:…)` off the main actor and
asserts no trap + correct `.uploading(fraction)` progression.
Verification: `swift test --package-path app/ShotTelemetryKit` (new progress test) + the two
build commands above.

## W2: Honest persistence + safe store open  —  est. S/M  —  ✅ done (F-004 2765044 · F-003 cd5424c)
Fixes: F-003 (fixed), F-004 (fixed)
Note: depends on W4 (uses the new test target for the recorder regression test). Touched view
files retain pre-existing F-013 lint debt; each W2-added line is swiftlint --strict clean.
Rationale: Both are error-handling correctness in the SwiftData layer; touch the same area and
ship together. F-003 prevents silent shot loss; F-004 removes a launch-crash path.
Approach:
- Replace `try? context.save()` with a helper that logs (and, for `ShotRecorder.finalize`,
  surfaces a recoverable "not saved" state instead of setting `lastCompletedShot` on failure).
- Wrap the `SharedStore` fallback `try!` in a `do/catch` that degrades to an in-memory container
  (or a clearly-reported failure) rather than trapping.
Verification: app builds; manual Simulator pass — pull a simulated shot, confirm it still lands
in History; both build commands above.

## W3: Watch kiosk reliability  —  est. S  —  ✅ done (F-002 4cd7a61 · F-005 ac4b703)
Fixes: F-002 (fixed), F-005 (fixed)
Rationale: Both are watch-target behaviour; small and isolated.
Approach:
- In `KioskKeepAwake.extendedRuntimeSessionWillExpire` (and/or `didInvalidateWith` for the
  timed-out reason), start a fresh session so the kiosk stays awake — matching the doc comment.
- Make the Release "Start" pill either perform a real action or render as non-interactive status
  (remove the tappable affordance outside DEBUG).
Verification: `xcodebuild -scheme ShotStopperTelemetryWatch -destination 'generic/platform=watchOS' build`;
watch Simulator smoke (`-demo`).

## W4: Restore the documented test gate  —  est. M  —  ✅ done (237aafd)
Fixes: F-006 (fixed; and unblocks the CLAUDE.md `build test` command)
Outcome: hosted `ShotStopperTelemetryTests` target + scheme Test action; `build test` exits 0
with 4 passing tests. SwiftLint installed during this waypoint surfaced F-013 (259 pre-existing
repo-wide violations — separate decision, see Out of scope).
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

- **F-007 (SwiftLint not installed):** ✅ resolved — installed via MacPorts during W4.
- **F-013 (259 pre-existing `swiftlint --strict` violations):** project-style decision. Either add a
  `.swiftlint.yml` encoding the established swift-format style (disable `trailing_comma`, allow the
  `DS`/`R` token type names, set `line_length`) or schedule a bulk style-fix pass. Until then the
  repo-wide `swiftlint --strict` gate fails on pre-existing debt; each waypoint's own changed code is
  kept lint-clean. Question: config-to-match-style, or bulk-reformat to SwiftLint defaults?
- **F-012 (`momentary` / `reedSwitch` / `dripDelay` UI):** product decision — are these meant to be
  user-facing in Settings, or intentionally hidden? Answer determines whether to add UI or remove the
  unused setters. Question: which device toggles should the app expose vs. leave to the firmware/recipe?
- **OTA protocol / ATS cleartext HTTP:** the uploader POSTs over plain HTTP to a LAN device via an ATS
  exception. Not a bug, but any change to the transport is a protocol decision, not an automated fix.
- **CloudKit schema:** verifying/altering the synced schema needs a signed build + iCloud account and a
  human in the loop; not automatable here.
