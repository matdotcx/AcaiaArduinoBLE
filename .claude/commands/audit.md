# /audit — read-only sweep of ShotStopperTelemetry

You are auditing an iOS + watchOS SwiftUI app. **You will not modify any source, test, config, or project file during this command.** Your only writes are: creating the audit branch, and writing `FINDINGS.md` + `PLAN.md` at the repo root (plus artifacts under `.audit/`).

## Repo layout note
The Xcode project and Swift package live under `app/`, not the repo root:
- Project: `app/ShotStopperTelemetry.xcodeproj`
- Package: `app/ShotTelemetryKit`
- Schemes: `ShotStopperTelemetry` (iOS), `ShotStopperTelemetryWatch` (watchOS)

Run all build/test commands from the repo root using these paths.

## Scope

The app is a BLE telemetry client for an espresso machine. Architecture:
- `app/ShotTelemetryKit` — pure Swift package: BLE central, 16-byte LE frame decode (service `0x0FFE`, char `0xFF25`), shot segmenter, CSV/JSON export. Builds with `swift build` / `swift test` on any toolchain.
- `app/AppShared` — SwiftData `@Model` layer (Shot, ShotSample, presets). Only compiles under `xcodebuild` because of the macro.
- iOS app target — live shot view (Swift Charts), history list/detail, recipe/preset editor, machine config write, OTA firmware upload (cleartext HTTP POST to LAN device via ATS exception).
- watchOS kiosk target — strapless full-screen live readout, kept awake via `WKExtendedRuntimeSession`.
- `#if DEBUG` pour simulator fakes telemetry so everything runs in Simulator without hardware.
- CloudKit private DB sync via `ModelConfiguration(cloudKitDatabase: .automatic)`, falling back to local store when unsigned.

## Procedure

### Step 0 — Branch
Create and check out `audit/<yyyy-mm-dd>-<short-sha>` from the current HEAD. All output goes here. If the branch already exists, append `-2`, `-3`, etc.

### Step 1 — Build & test baseline (record, don't fix)
Run and capture exit codes + full logs for each. Do NOT retry with flags removed, tests filtered, or warnings suppressed.

1. `swift build --package-path app/ShotTelemetryKit`
2. `swift test --package-path app/ShotTelemetryKit --enable-code-coverage`
3. `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'generic/platform=iOS' build`
4. `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' test`
5. `xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetryWatch -destination 'generic/platform=watchOS' build`
6. `swiftlint --strict --reporter json > .audit/swiftlint.json` (if SwiftLint not installed, note it as a finding — do not skip silently)

Record every warning, error, and failing test verbatim in `.audit/baseline.log`.

### Step 2 — Static review
Read the codebase and identify, **without changing anything**:
- Dead code, duplication, unused imports
- Force-unwraps (`!`), `try!`, `as!` — especially in BLE decode, OTA upload, and CloudKit paths
- Retain cycles in closures (BLE delegate callbacks, `Task {}` in SwiftUI views, chart update timers)
- `@MainActor` / concurrency annotation gaps between the BLE stream and SwiftUI state
- SwiftData issues: missing migrations, `@Model` types lacking sensible defaults (CloudKit requires every property optional or defaulted), implicit relationship delete rules
- Hard-coded magic numbers that should live in the preset/config model (frame offsets, max shot duration, reconnect backoff)
- Error-path coverage: BLE disconnect mid-pour, OTA POST failure, CloudKit unavailable, watch session expiry mid-pour
- Export correctness: CSV escaping, JSON Codable round-trip of `Shot`/`ShotSample`
- watchOS-specific: `WKExtendedRuntimeSession` not invalidated, screen-on leak when pour ends

### Step 3 — UI walkthrough (Simulator, DEBUG pour faker on)
Using XcodeBuildMCP and/or computer use:
1. Launch the iOS app in Simulator.
2. Walk every reachable screen and tap every control. For each, record: control identifier/label, expected behaviour (infer from label + code), observed behaviour.
3. Specifically hunt: buttons that don't respond, navigation that dead-ends, sheets that won't dismiss, list rows that don't select, charts that don't render with the fake pour, text fields that don't commit, export buttons that produce nothing.
4. Trigger a fake pour and confirm the live curve animates and a `Shot` record appears in history.
5. Repeat a condensed pass on the watchOS kiosk in the Watch Simulator.
6. Capture a screenshot for every defect found, saved under `.audit/ui/`.

If a control's behaviour cannot be verified in Simulator (e.g. real BLE write, OTA to LAN device, CloudKit signed-in sync), record it as **"requires hardware — not verified"**, not as a pass.

### Step 4 — Write `FINDINGS.md`
Structure exactly:

    # ShotStopperTelemetry — Audit Findings (<date>, <branch>)

    ## Build & Test Baseline
    | Check | Result | Notes |

    ## P0 — Broken (crashes, data loss, dead controls)
    ### F-001: <one-line title>
    - **Where:** file:line / screen
    - **Observed:** …
    - **Evidence:** log excerpt or `.audit/ui/<screenshot>`
    - **Suspected cause:** …
    - **Confidence:** high / medium / low

    ## P1 — Wrong (incorrect behaviour, bad error handling, unsafe unwraps)
    …
    ## P2 — Nits (style, dead code, naming, minor UI polish)
    …
    ## Not Verified — Requires Hardware
    …
    ## Honest Failures
    Anything the audit itself could not complete and why. Do not omit this section even if empty.

Each finding gets a stable ID `F-NNN`. Do not inflate severity. Do not merge unrelated issues into one finding.

### Step 5 — Write `PLAN.md`
Group findings into **waypoints** — independently shippable batches, each leaving the app buildable and device-installable. Order by (risk reduced × effort⁻¹).

    # ShotStopperTelemetry — Fix Plan

    ## W1: <batch title>  —  est. <S/M/L>
    Fixes: F-001, F-004, F-007
    Rationale: why these belong together
    Verification: the exact xcodebuild / swift test commands that must pass
    Rollback: `git checkout <audit-branch>` (always true, but state it)

    ## W2: …

    ## Out of scope for automated fix
    Findings that need a human decision (UX choices, OTA protocol changes, CloudKit schema). List them with the question to answer.

### Step 6 — Prove nothing broke
Run the Step 1 baseline commands again. Diff against `.audit/baseline.log`. They must be **byte-identical or better** (you wrote two markdown files and made a branch — nothing else). If anything differs, STOP, write the diff into `## Honest Failures`, and do not claim success.

### Step 7 — Device sanity
`xcodebuild -project app/ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS,id=<DEVICE_UDID>' install` — confirm the app still installs on the attached device. If no device is attached, state that and skip; do not fake it.

### Step 8 — Report
Print a one-paragraph summary: counts by severity, top 3 P0s, first recommended waypoint. Push the audit branch. Stop.

## Hard rules — read before every step

- **Findings only.** No source edits, no test edits, no project file edits, no `Package.swift` edits, no scheme changes.
- **No reward hacking.** You may not: disable or relax SwiftLint rules; delete, skip, comment out, or stub tests; add `XCTSkip`; mark tests `@available(*, unavailable)`; catch-and-ignore to make something pass; lower warning levels; remove `-warnings-as-errors`; edit `.swiftlint.yml`; or alter the verification commands. If a check fails, **report the failure** — that is the correct output.
- **Fail loud.** If a tool is missing, a build is broken, or the simulator won't launch, write it into `## Honest Failures` and continue with what you can. A partial audit with an honest failures section is a success. A "clean" audit that silently skipped steps is a failure.
- **No scope creep.** Do not refactor, reformat, or "tidy while you're here." That's what `/fix` is for.
