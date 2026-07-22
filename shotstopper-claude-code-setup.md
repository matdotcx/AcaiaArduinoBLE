# ShotStopperTelemetry — Claude Code Audit & Fix Workflow

A two-command, branch-isolated workflow: `/audit` produces findings and a waypointed plan **without touching code**; `/fix <waypoint>` executes one batch you've chosen. Both end with a clean build and device install. Built from the Oracle thread guidance (Matt Matteson's quality-bar pattern, Cat Wu's two-phase Swift review, Vineet's `/verify-ios`, and the reward-hacking guardrails).

---

## 0. One-time setup

### 0.1 Run `/init` first
Let Claude generate the baseline `CLAUDE.md` from a repo scan, then **append** the block in §3 below. Don't replace what `/init` writes — the Oracle thread is explicit that output quality "changes drastically" with a good hierarchical `CLAUDE.md`.

### 0.2 Pick your simulator driver
You need one of these wired up via `/mcp` for the UI walkthrough step:

| Option | Notes |
|---|---|
| **XcodeBuildMCP** | Wraps AXe, private-API taps/swipes. Works headless today. |
| **Apple 1P Xcode 27 MCP** | WWDC 2026 bindings. Currently needs Xcode open; headless lands beta 3–4. |
| **Computer use in Claude Code CLI** | Enable via `/mcp`. macOS only. The "click every button, find what's broken" closed loop. |

For ShotStopper specifically, the `#if DEBUG` pour simulator means the UI walkthrough works in Simulator without the machine attached — so any of the three will do. I'd start with **XcodeBuildMCP** because it's headless now, and add **computer use** for the stuck-button / dead-tap-target sweep.

### 0.3 Permissions — auto mode, not the nuclear flag
Set `/permission-modes` → **auto** for the audit runs (Boris's "20–30 mins without prompts" mode). Do **not** use `--dangerously-skip-permissions` on your dev machine — the Oracle thread links a whole incident list. Pair with the `settings.json` allowlist in §4.

### 0.4 Mobile push (optional but you'll want it)
`/remote-control` → enable "Push when Claude decides" so long audits ping your phone when `FINDINGS.md` is ready or when something genuinely blocks.

---

## 1. `.claude/commands/audit.md`

Drop this file at `.claude/commands/audit.md`. Invoke as `/audit`.

```markdown
# /audit — read-only sweep of ShotStopperTelemetry

You are auditing an iOS + watchOS SwiftUI app. **You will not modify any source, test, config, or project file during this command.** Your only writes are: creating the audit branch, and writing `FINDINGS.md` + `PLAN.md` at the repo root.

## Scope

The app is a BLE telemetry client for an espresso machine. Architecture:
- `ShotTelemetryKit` — pure Swift package: BLE central, 16-byte LE frame decode (service `0x0FFE`, char `0xFF25`), shot segmenter, CSV/JSON export. Builds with `swift build` / `swift test` on any toolchain.
- `AppShared` — SwiftData `@Model` layer (Shot, ShotSample, presets). Only compiles under `xcodebuild` because of the macro.
- iOS app target — live shot view (Swift Charts), history list/detail, recipe/preset editor, machine config write, OTA firmware upload (cleartext HTTP POST to LAN device via ATS exception).
- watchOS kiosk target — strapless full-screen live readout, kept awake via `WKExtendedRuntimeSession`.
- `#if DEBUG` pour simulator fakes telemetry so everything runs in Simulator without hardware.
- CloudKit private DB sync via `ModelConfiguration(cloudKitDatabase: .automatic)`, falling back to local store when unsigned.

## Procedure

### Step 0 — Branch
Create and check out `audit/<yyyy-mm-dd>-<short-sha>` from the current HEAD. All output goes here. If the branch already exists, append `-2`, `-3`, etc.

### Step 1 — Build & test baseline (record, don't fix)
Run and capture exit codes + full logs for each. Do NOT retry with flags removed, tests filtered, or warnings suppressed.

1. `swift build --package-path ShotTelemetryKit`
2. `swift test --package-path ShotTelemetryKit --enable-code-coverage`
3. `xcodebuild -project ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'generic/platform=iOS' build`
4. `xcodebuild -project ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' test`
5. `xcodebuild -project ShotStopperTelemetry.xcodeproj -scheme 'ShotStopperTelemetry Watch App' -destination 'generic/platform=watchOS' build`
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
`xcodebuild -scheme ShotStopperTelemetry -destination 'platform=iOS,id=<DEVICE_UDID>' install` — confirm the app still installs on the attached device. If no device is attached, state that and skip; do not fake it.

### Step 8 — Report
Print a one-paragraph summary: counts by severity, top 3 P0s, first recommended waypoint. Push the audit branch. Stop.

## Hard rules — read before every step

- **Findings only.** No source edits, no test edits, no project file edits, no `Package.swift` edits, no scheme changes.
- **No reward hacking.** You may not: disable or relax SwiftLint rules; delete, skip, comment out, or stub tests; add `XCTSkip`; mark tests `@available(*, unavailable)`; catch-and-ignore to make something pass; lower warning levels; remove `-warnings-as-errors`; edit `.swiftlint.yml`; or alter the verification commands. If a check fails, **report the failure** — that is the correct output.
- **Fail loud.** If a tool is missing, a build is broken, or the simulator won't launch, write it into `## Honest Failures` and continue with what you can. A partial audit with an honest failures section is a success. A "clean" audit that silently skipped steps is a failure.
- **No scope creep.** Do not refactor, reformat, or "tidy while you're here." That's what `/fix` is for.
```

---

## 2. `.claude/commands/fix.md`

Drop at `.claude/commands/fix.md`. Invoke as `/fix W3` (or `/fix F-012` for a single finding).

```markdown
# /fix <waypoint-or-finding-id>

Execute exactly one waypoint (or single finding) from `PLAN.md` on the current audit branch.

## Preconditions — abort if any fail
- `FINDINGS.md` and `PLAN.md` exist at repo root.
- You are on an `audit/*` branch with a clean working tree.
- The argument resolves to a waypoint `W<n>` or finding `F-<nnn>` present in `PLAN.md`.

## Procedure

1. **Sub-branch.** Create `fix/<waypoint-id>-<slug>` from the audit branch.
2. **Restate scope.** Print the finding IDs in this waypoint and the verification commands from `PLAN.md`. Touch nothing outside those findings' files.
3. **Test-first where possible.** For anything in `ShotTelemetryKit`, write a failing Swift Testing test that reproduces the finding before changing code. For UI findings, add an `XCUITest` that taps the control and asserts the expected state where feasible.
4. **Fix.** Smallest change that resolves the finding. Match existing swift-format style. Functions stay <~50 lines, files <400 (Matt Matteson quality bar).
5. **Verify — all of:**
   - `swift test --package-path ShotTelemetryKit`
   - `xcodebuild … -scheme ShotStopperTelemetry build`
   - `xcodebuild … -scheme ShotStopperTelemetry test`
   - `xcodebuild … -scheme 'ShotStopperTelemetry Watch App' build`
   - `swiftlint --strict`
   - The waypoint's specific verification command from `PLAN.md`
   - Re-run the UI walkthrough step for the affected screen(s) only
6. **Device install.** `xcodebuild … -destination 'platform=iOS,id=<DEVICE_UDID>' install` must succeed (or report no device attached).
7. **Commit.** One commit per finding, message `fix(F-NNN): <title>`. Update `FINDINGS.md` to mark each as `✅ fixed in <commit-sha>` and `PLAN.md` to mark the waypoint `done`.
8. **Report.** Diff summary, test counts before/after, any finding you could NOT fix and why (goes back into `PLAN.md` under "Out of scope" with the blocker).

## Hard rules — same as /audit, plus:
- **One waypoint only.** Even if you spot an easy adjacent fix, log it as a new `F-NNN` in `FINDINGS.md` and stop.
- **A fix that makes any verification command fail is not a fix.** Revert it, record the attempt in the finding's notes, and move on. Prefer "could not fix F-012: <reason>" over a change that passes by weakening the check.
- **Never** edit a test to make it pass unless the test itself was the bug (and if so, the finding must say so explicitly with evidence).
```

---

## 3. Append to `CLAUDE.md` (after `/init` output)

```markdown
## Project shape
- `ShotTelemetryKit/` builds with plain `swift build`/`swift test` — prefer this for logic tests.
- `AppShared/` and the app targets require `xcodebuild` (SwiftData `@Model` macro).
- `#if DEBUG` enables a pour simulator — UI tests in Simulator do NOT need the espresso machine.
- BLE frame: 16 bytes, little-endian, service `0x0FFE`, telemetry char `0xFF25`. Decode lives in `ShotTelemetryKit`.
- CloudKit sync requires every `@Model` property to be optional or defaulted; local-store fallback when unsigned.

## Quality bar (applies to every change)
- Swift Testing unit test for any logic touched in `ShotTelemetryKit`.
- `swiftlint --strict` clean. Functions <~50 lines, files <400 lines.
- Match existing `swift-format` style — do not reformat unrelated code.
- Both schemes build; iOS scheme tests pass; app installs on attached device.
- Update this file and `README.md` if behaviour or setup changes.

## Verification commands (canonical — do not alter)
    swift test --package-path ShotTelemetryKit
    xcodebuild -project ShotStopperTelemetry.xcodeproj -scheme ShotStopperTelemetry -destination 'platform=iOS Simulator,name=iPhone 16' build test
    xcodebuild -project ShotStopperTelemetry.xcodeproj -scheme 'ShotStopperTelemetry Watch App' -destination 'generic/platform=watchOS' build
    swiftlint --strict

## Anti-reward-hacking (non-negotiable)
Never disable, relax, skip, stub, or comment out tests or lint rules to achieve a passing state. Never catch-and-ignore. Never edit `.swiftlint.yml` or scheme test plans to exclude failures. If something cannot be fixed honestly, report it as unfixed with the reason. A reported failure is success; a hidden failure is the only true failure.
```

---

## 4. `.claude/settings.json` allowlist

```json
{
  "permissions": {
    "allow": [
      "Bash(swift build*)",
      "Bash(swift test*)",
      "Bash(xcodebuild*)",
      "Bash(swiftlint*)",
      "Bash(swift-format*)",
      "Bash(xcrun simctl*)",
      "Bash(git checkout*)",
      "Bash(git branch*)",
      "Bash(git add*)",
      "Bash(git commit*)",
      "Bash(git push*)",
      "Bash(git diff*)",
      "Bash(git status*)"
    ],
    "deny": [
      "Bash(rm -rf*)",
      "Bash(git push --force*)",
      "Bash(git reset --hard*)"
    ]
  },
  "hooks": {
    "PostToolUse": [
      {
        "matcher": { "tool": "Edit|Write|MultiEdit" },
        "command": "swiftlint --strict --quiet $CLAUDE_FILE_PATHS && swift-format --in-place $CLAUDE_FILE_PATHS"
      }
    ]
  }
}
```

The PostToolUse hook means style enforcement is mechanical, not prompt-dependent — Claude can't "forget" to lint because the hook runs after every edit regardless.

---

## 5. What's automated vs what isn't

| Automated | Needs you |
|---|---|
| Branch creation, baseline build/test capture | Choosing which waypoint to run next |
| SwiftLint, dead-code, force-unwrap, concurrency static sweep | Reviewing `FINDINGS.md` severity calls |
| Simulator UI walkthrough with the DEBUG pour faker | Anything flagged "requires hardware" — real BLE writes, OTA to the actual machine, CloudKit signed-in sync |
| Per-waypoint fix + test + lint + device install | UX judgement calls (`PLAN.md` → "Out of scope") |
| `FINDINGS.md` / `PLAN.md` upkeep across runs | Merging `fix/*` branches back to `main` |
| watchOS build verification | Physically checking the watch kiosk on the unit |

---

## 6. Your loop in practice

```
/audit                          # go make coffee — mobile push pings you when done
# read FINDINGS.md + PLAN.md
/fix W1                         # safest batch first
# device-test on the machine
/fix W2
# … repeat
/fix F-017                      # cherry-pick a single finding if a waypoint's too coarse
```

Re-run `/audit` after a few waypoints to regenerate the plan against the new baseline — findings IDs are stable so the diff is readable.
