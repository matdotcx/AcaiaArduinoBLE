# /fix <waypoint-or-finding-id>

Execute exactly one waypoint (or single finding) from `PLAN.md` on the current audit branch.

## Repo layout note
Project and package live under `app/`:
- Project: `app/ShotStopperTelemetry.xcodeproj`
- Package: `app/ShotTelemetryKit`
- Schemes: `ShotStopperTelemetry` (iOS), `ShotStopperTelemetryWatch` (watchOS)

## Preconditions — abort if any fail
- `FINDINGS.md` and `PLAN.md` exist at repo root.
- You are on an `audit/*` branch with a clean working tree.
- The argument resolves to a waypoint `W<n>` or finding `F-<nnn>` present in `PLAN.md`.

## Procedure

1. **Sub-branch.** Create `fix/<waypoint-id>-<slug>` from the audit branch.
2. **Restate scope.** Print the finding IDs in this waypoint and the verification commands from `PLAN.md`. Touch nothing outside those findings' files.
3. **Test-first where possible.** For anything in `app/ShotTelemetryKit`, write a failing Swift Testing test that reproduces the finding before changing code. For UI findings, add an `XCUITest` that taps the control and asserts the expected state where feasible.
4. **Fix.** Smallest change that resolves the finding. Match existing swift-format style. Functions stay <~50 lines, files <400 (Matt Matteson quality bar).
5. **Verify — all of:**
   - `swift test --package-path app/ShotTelemetryKit`
   - `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' build`
   - `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' test`
   - `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetryWatch -destination 'generic/platform=watchOS' build`
   - `swiftlint --strict`
   - The waypoint's specific verification command from `PLAN.md`
   - Re-run the UI walkthrough step for the affected screen(s) only
6. **Device install.** `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS,id=<DEVICE_UDID>' install` must succeed (or report no device attached).
7. **Commit.** One commit per finding, message `fix(F-NNN): <title>`. Update `FINDINGS.md` to mark each as `✅ fixed in <commit-sha>` and `PLAN.md` to mark the waypoint `done`.
8. **Report.** Diff summary, test counts before/after, any finding you could NOT fix and why (goes back into `PLAN.md` under "Out of scope" with the blocker).

## Hard rules — same as /audit, plus:
- **One waypoint only.** Even if you spot an easy adjacent fix, log it as a new `F-NNN` in `FINDINGS.md` and stop.
- **A fix that makes any verification command fail is not a fix.** Revert it, record the attempt in the finding's notes, and move on. Prefer "could not fix F-012: <reason>" over a change that passes by weakening the check.
- **Never** edit a test to make it pass unless the test itself was the bug (and if so, the finding must say so explicitly with evidence).
- **No reward hacking.** You may not disable/relax SwiftLint rules, delete/skip/stub/comment out tests, add `XCTSkip`, catch-and-ignore, lower warning levels, remove `-warnings-as-errors`, or edit `.swiftlint.yml`. A reported failure is success; a hidden failure is the only true failure.
