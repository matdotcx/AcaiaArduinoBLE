# ShotStopperTelemetry — Audit Findings (2026-06-16, audit/2026-06-16-af5b177)

Read-only sweep. No source/test/project files were modified. Artifacts in `.audit/`
(baseline log, UI screenshots). Toolchain: Apple Swift 6.3.2 / Xcode 26.5.

## Build & Test Baseline

| Check | Result | Notes |
|---|---|---|
| `swift build` (ShotTelemetryKit) | ✅ pass | No warnings |
| `swift test` (ShotTelemetryKit) | ✅ 28/28 pass | FirmwareUploader, ShotAnalysis, ShotExport, ShotSegmenter, TelemetryFrame |
| `xcodebuild build` iOS (generic) | ✅ pass | Watch app embeds into `.app/Watch` as expected, no compiler warnings |
| `xcodebuild test` iOS (Simulator) | ❌ **exit 66** | "Scheme ShotStopperTelemetry is not currently configured for the test action" — no app-level test target. See F-006. |
| `xcodebuild build` watchOS (generic) | ✅ pass | No compiler warnings |
| `swiftlint --strict` | ⚠️ not run | swiftlint not installed on this machine. See F-007. |

UI walkthrough (DEBUG faker, iPhone 17 + Apple Watch Series 11 simulators): Live (done
state), History, Settings, Shot Detail, Recipe Editor, OTA, and the watch kiosk all
render and animate correctly. Screenshots under `.audit/ui/`. No dead controls, stuck
sheets, or non-rendering charts were observed in Simulator. iPhone 16 (the destination
named in CLAUDE.md) is not installed; iPhone 17 was used — this does not affect the
test-action failure, which is evaluated before the destination.

---

## P0 — Broken (crashes, data loss, dead controls)

### F-001: OTA upload progress callback asserts main-actor isolation on a background queue → crash
- **Status:** ✅ fixed in 23ae2c4. Replaced `MainActor.assumeIsolated` with an explicit
  `Task { @MainActor }` hop + a pure `progressFraction` helper; the off-main regression test
  SIGTRAPs on the old code and passes now.
- **Where:** `app/ShotTelemetryKit/Sources/ShotTelemetryKit/FirmwareUploader.swift:85`
- **Observed:** In `urlSession(_:task:didSendBodyData:…)` the code wraps the progress update in
  `MainActor.assumeIsolated { … }`. This delegate is invoked on `URLSession.shared`'s delegate
  queue (a private background serial queue), **not** the main actor. `assumeIsolated` does a
  hard executor-precondition check and traps ("Incorrect actor executor assumption") when the
  assumption is false — so the app crashes as soon as the device starts acknowledging uploaded
  bytes (i.e. during every real firmware upload).
- **Evidence:** Only `assumeIsolated` site not on the central manager's `queue: nil` (main) path;
  contrast with `ShotStopperClient` where `assumeIsolated` is legitimate because the CB manager
  uses the main queue. Cannot be exercised end-to-end in Simulator (needs a LAN device that
  responds), so verified by inspection.
- **Suspected cause:** Pattern copied from `ShotStopperClient` (where main-queue delivery makes
  `assumeIsolated` valid) into a URLSession delegate where delivery is on a background queue.
- **Confidence:** high (by inspection); trigger requires hardware.
- **Fix direction:** hop explicitly, e.g. `Task { @MainActor in … }`, or `await MainActor.run`,
  or give the uploader its own `URLSession` with `delegateQueue: .main`. Do not assume isolation.

---

## P1 — Wrong (incorrect behaviour, bad error handling, unsafe unwraps)

### F-002: Watch keep-awake session is not restarted on expiry (kiosk dims after one window)
- **Status:** ✅ fixed in 4cd7a61. `extendedRuntimeSessionWillExpire` now starts a fresh session
  (gated on a `wantAwake` flag so `end()` isn't respawned); error/resign invalidations don't loop.
- **Where:** `app/ShotStopperTelemetryWatch/KioskKeepAwake.swift:30` (`extendedRuntimeSessionWillExpire`)
- **Observed:** The class doc says "Sessions are time-bounded by watchOS; we restart on expiry."
  But `extendedRuntimeSessionWillExpire` only does `self.session = nil` — it never calls `begin()`
  (or starts a new session). `WKExtendedRuntimeSession` lifetimes are bounded, so once the first
  session expires the strapless kiosk stops being kept awake and the watch dims/returns to the
  clock, defeating the feature for a machine-mounted display left running.
- **Evidence:** No `begin()`/`start()` call in `willExpire` or `didInvalidateWith`. Behaviour vs.
  documented intent mismatch.
- **Suspected cause:** Handle is dropped to *allow* a restart, but the restart call was never wired.
- **Confidence:** high (by inspection); real-watch timing not verified.

### F-003: Persistence errors are silently swallowed (`try? context.save()`) — possible silent data loss
- **Status:** ✅ fixed in cd5424c (W2). Added `ModelContext.saveLogging()` (logs + returns success);
  replaced all `try? context.save()`. `ShotRecorder.finalize` now sets `lastCompletedShot` only on a
  successful save and raises a `saveFailed` flag (shown as a dismissible "Shot not saved" banner in
  LiveShotView) otherwise. Regression test against an in-memory container; iOS suite 5 tests pass.
- **Where:** 9 sites — `app/AppShared/ShotRecorder.swift:83` (finalize), `:92` (discard);
  `app/ShotStopperTelemetry/ShotDetailView.swift:201` (`save()`), `:291` (delete);
  `ShotHistoryView.swift:208` (delete); `RecipeEditorView.swift:177,182`;
  `SettingsView.swift:289` (DEBUG seed); `ShotSimulator.swift:87` (DEBUG seed).
- **Observed:** Every SwiftData write uses `try?` and discards the error. The shot-recording path
  (`finalize`) is the most consequential: if a save fails (CloudKit conflict, disk pressure,
  migration), the just-pulled shot is lost with zero user feedback, yet `lastCompletedShot` is set
  so the UI shows "saved". Note recorder finalize sets `lastCompletedShot` *after* the failed save
  — UI claims success regardless of outcome.
- **Evidence:** `grep 'try? .*save()'` → 9 hits; none surface or log the error.
- **Confidence:** high.
- **Fix direction:** at minimum log the error; for the record path, surface a non-destructive
  failure state so the user knows the shot didn't persist.

### F-004: Store-open fallback uses `try!` — hard crash if the local store also fails
- **Status:** ✅ fixed in 2765044 (W2). `makeContainer` now degrades cloud → local → in-memory,
  logging each downgrade; the only remaining `fatalError` is for an invalid schema (impossible for an
  in-memory store), so a corrupt/incompatible on-disk store no longer crashes launch.
- **Where:** `app/AppShared/SharedStore.swift:18`
- **Observed:** The CloudKit `ModelContainer` is created in a `do`, and the `catch` falls back to a
  local-only container with `try!`. The fallback opens the **same default store file**, so a failure
  caused by store corruption or an incompatible schema migration (not by CloudKit entitlement) will
  fail again in the fallback — and `try!` turns that into an unrecoverable launch crash. The catch
  only really helps the "unsigned, no iCloud" case.
- **Evidence:** Only `try!` in the codebase.
- **Confidence:** medium (depends on failure mode).
- **Fix direction:** catch the fallback too and present a recoverable error / in-memory container
  rather than trapping.

### F-005: Watch "Start" pill is a dead control in Release builds
- **Status:** ✅ fixed in ac4b703. The idle pill is now `#if DEBUG`-only (relabelled "Simulate");
  Release compiles it out, so there's no tappable-but-dead control on device.
- **Where:** `app/ShotStopperTelemetryWatch/WatchKioskView.swift:109` (`startPill`)
- **Observed:** The idle kiosk shows a tappable-looking orange "Start" pill, but its only action
  (`.onTapGesture { model.simulateShot() }`) is inside `#if DEBUG`. In a shipped (Release) build the
  pill has no action and does nothing when tapped. Either it should do something real or not look
  interactive on device. (Not visible in the captured screenshot because the faker had already moved
  the kiosk into the REC state.)
- **Confidence:** medium (Release-only; by inspection).

---

## P2 — Nits (style, dead code, naming, minor UI polish)

### F-006: iOS scheme has no test action — the documented verification command can't pass
- **Status:** ✅ fixed in 237aafd (W4). Added a hosted `ShotStopperTelemetryTests` target wired
  into the scheme's Test action; `xcodebuild … build test` now exits 0 with 4 tests passing.
- **Where:** `app/ShotStopperTelemetry.xcodeproj` scheme `ShotStopperTelemetry`; CLAUDE.md
  "Verification commands" lists `xcodebuild … -scheme ShotStopperTelemetry … build test`.
- **Observed:** There is no app-level unit/UI test target; the scheme's test action is unconfigured,
  so the canonical command fails with exit 66 every time. Logic tests live only in the
  `ShotTelemetryKit` package. The quality bar ("iOS scheme tests pass") is therefore unverifiable
  as written. This is a doc/scheme mismatch, not a regression — filed P2 because the package tests
  do cover the logic, but it undermines the stated verification flow.
- **Confidence:** high.

### F-007: SwiftLint not installed — `swiftlint --strict` quality gate unverifiable here
- **Status:** ✅ resolved (tooling) — SwiftLint 0.63.2 installed via MacPorts during W4. The gate
  now runs; see F-013 for what it surfaced.
- **Where:** environment / CLAUDE.md quality bar.
- **Observed:** `swiftlint` was not on PATH, so the required `swiftlint --strict` clean check could
  not be run. Reported, not skipped silently.
- **Confidence:** high.

### F-013: `swiftlint --strict` reveals 259 pre-existing violations across 36 files
- **Status:** ✅ fixed in f8ffa1f (W5). Added a `.swiftlint.yml` aligned to the project's swift-format
  style (disables `trailing_comma`/`opening_brace`, SwiftUI/GATT-realistic thresholds) while keeping
  `file_length` 400 and `function_body_length` at the CLAUDE.md bar; combined with the F-008 split,
  `swiftlint --strict` now reports **0 violations across 34 files**.
- **Where:** repo-wide; concentrated in `app/AppShared/DesignSystem.swift` and the iOS views.
- **Observed:** With SwiftLint now installed (F-007) and **no `.swiftlint.yml`** in the repo, the
  default ruleset flags 259 serious violations under `--strict`: `line_length`, `opening_brace`
  spacing, `trailing_comma` (swift-format *adds* these), the intentional short token type-names
  `DS`/`R` (`type_name`), and `private_over_fileprivate`. The project clearly follows swift-format
  conventions that collide with SwiftLint's defaults, so the CLAUDE.md "`swiftlint --strict` clean"
  bar cannot pass repo-wide today. Pre-existing — not introduced by any fix waypoint (each waypoint's
  *own* new/changed code is linted clean).
- **Suspected cause:** the lint gate was specified but never run (no linter installed, no config).
- **Confidence:** high.
- **Fix direction (needs a decision):** add an intentional `.swiftlint.yml` that encodes the
  project's real swift-format style (disable `trailing_comma`, allow `DS`/`R` via `type_name`
  `allowed_symbols`/min-length, set `line_length`), **or** do a dedicated bulk style-fix pass. This
  is a project-style decision, not an automated bug fix — see PLAN "Out of scope".

### F-008: `DesignSystem.swift` is 515 lines — exceeds the <400-line file guideline
- **Status:** ✅ fixed in f8ffa1f (W5). Charts extracted to `DesignCharts.swift`; DesignSystem.swift
  is now 375 lines (under 400). `fileprivate`→`private` on the Archivo loader.
- **Where:** `app/AppShared/DesignSystem.swift` (515 lines). All other files are ≤321.
- **Observed:** Mixes color tokens, the Archivo variable-font loader, recipe palette, and ~10
  reusable components + two Swift Charts views. Splitting (Tokens / Components / Charts) would meet
  the bar. No correctness issue.
- **Confidence:** high.

### F-009: Subscribed-but-ignored BLE notifications (`scaleStatus` FF19, `shotStatus` FF20)
- **Status:** ✅ fixed in 0063dd2 (W5). Dropped `scaleStatus`/`shotStatus` from `TelemetryGATT.notifying`
  (the telemetry frame already carries that state).
- **Where:** `ShotStopperClient.applyConfig` (`:280`) vs. `TelemetryGATT.notifying` (`:53`).
- **Observed:** The client subscribes to `scaleStatus` and `shotStatus` notifications, but
  `applyConfig`'s switch has no cases for them → they hit `default: break` and are silently dropped.
  Either wire them into state or drop the subscriptions. Harmless today.
- **Confidence:** high.

### F-010: DEBUG `seedHistory` has no dedup and omits recipe identity
- **Status:** ✅ fixed in 0063dd2 (W5). Seeds only an empty store; stamps recipe colour/icon identity.
- **Where:** `app/AppShared/ShotSimulator.swift:46`
- **Observed:** Each invocation inserts another 6 shots into the persistent local store (History grew
  to 18 across launches during this audit), and it sets `presetName` but not `recipeColorIndex`/
  `recipeIcon`, so seeded rows fall back to name-derived styling. DEBUG-only; cosmetic.
- **Confidence:** high.

### F-011: Export temp-file name collisions for shots in the same minute
- **Status:** ✅ fixed in 0063dd2 (W5). Detail exports now write into a per-shot temp subdirectory
  keyed by the shot UUID, keeping a clean user-facing filename without collisions.
- **Where:** `ShotExporter.suggestedName` (`ShotExport.swift:70`, format `yyyy-MM-dd-HHmm`) used by
  `ShotDetailView.generateExports` (`:299`).
- **Observed:** Two shots started in the same minute produce the same `shot-….csv`/`.json` temp path
  and overwrite each other in `temporaryDirectory`. Low impact (ShareLink uses the freshly written
  file), but the name is not unique.
- **Confidence:** medium.

### F-012: `momentary` / `reedSwitch` setters have no Settings UI; `dripDelay` only editable via a recipe
- **Where:** `ShotStopperClient` (`:89–94`) vs. `SettingsView`.
- **Observed:** The client exposes `setMomentary`, `setReedSwitch`, `setDripDelay`, but Settings only
  surfaces target weight, min/max duration, brew-by-weight, auto-tare. `dripDelay` is editable only
  inside the recipe editor; `momentary`/`reedSwitch` are not user-reachable at all. Possibly
  intentional scoping — flagged for a product decision, not a bug.
- **Confidence:** high (observation); intent unknown.

---

## Not Verified — Requires Hardware

- **Real BLE connect / scan-by-name / 16-byte frame decode** against the ShotStopper. Decode logic
  is unit-tested; on-air behaviour is not verified here.
- **Config writes** (`.withResponse`) actually landing on the device and the Sending…/Sent ack flow.
- **Full OTA flow** — WiFi credential write, firmware joining WiFi, `wifiIP` notification, and the
  multipart upload. This is also the only way to fully trigger **F-001** (the upload-progress crash).
- **CloudKit private-DB sync** on a signed build with an iCloud account (the `.automatic` path).
- **Watch `WKExtendedRuntimeSession` expiry behaviour** on a physical watch (F-002 verified by
  inspection only).
- **BLE disconnect mid-pour** inferred-new-shot path on real hardware (covered by ShotSegmenter
  unit tests, not on-air).

## Honest Failures

- **`swiftlint --strict` not run** — swiftlint is not installed (F-007). The lint quality gate is
  unverified. Not worked around.
- **iOS `test` action fails (exit 66)** — recorded as a baseline failure (F-006), not bypassed,
  filtered, or "fixed" by editing the scheme. The package tests (28) are the only automated tests
  and they pass.
- **iPhone 16 simulator absent** — the UI walkthrough used iPhone 17 (booted). The test-action
  failure is independent of the destination.
- **Live mid-pour iPhone frame not captured** — capture timing landed on the completed "done" state
  instead (still confirms chart render + coaching + Save/Discard). The watch capture did catch a
  mid-pour REC frame.
- **OTA upload not executed** — no LAN device; F-001 could not be reproduced at runtime, only by
  code inspection.
