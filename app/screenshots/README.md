# ShotStopper Telemetry — UI screenshots

**Visual System v1 is implemented** (the `design_handoff_shotstopper` spec): cohesive
light/dark color system, expanded precision-gauge numerals (SF Pro expanded + SF Mono),
recipe identity (color + icon), styled Swift Charts, and a state language. Captured in
the iOS 26.5 / watchOS 26.5 Simulators (no Bluetooth there, so connection shows
"Not connected"). Shot data is from the built-in demo simulator.

| File | Screen | Notes |
| --- | --- | --- |
| `ios-1-live-idle.png` | iPhone · Live (idle) | Hero `0.0` in disabled grey, stats card, dashed empty card + orange Simulate pill. |
| `ios-2-live-pour.png` | iPhone · Live (brewing) | REC pulse, big ink hero numeral, orange progress + curve with leading dot, neutral dashed target. |
| `ios-3-history.png` | iPhone · History | Filter chips (recipe-colored), sparkline rows, recipe tags, ON TARGET status. |
| `ios-4-detail-export.png` | iPhone · Shot detail | Green chart, summary card (recipe token), Export CSV/JSON pills, bottom Back pill. |
| `ios-5-settings.png` | iPhone · Settings | Connection card, recipe rows (token chip + APPLIED), orange stepper/toggles, Device/OTA. |
| `ios-6-ota.png` | iPhone · Firmware OTA | WiFi/Device cards, dark uploading card, Choose-firmware pill, Back + Done. |
| `ios-7-dark-live.png` | iPhone · Live (dark) | Dark-mode Live: near-black canvas, cream hero, brighter orange. |
| `ios-8-dark-history.png` | iPhone · History (dark) | Dark-mode History: recipe-tag dark variants, dark cards. |
| `watch-1-idle.png` | Watch · Kiosk (idle) | True black, grey dash, WAITING FOR SHOT, orange Start pill. |
| `watch-2-pour.png` | Watch · Kiosk (brewing) | True black, cream giant numeral, mono stats, mini chart + leading dot. |

## Design intent / brand
- It's a brew-by-weight espresso companion. Glanceable, calm, used wet-handed at the machine.
- Existing brand cue (from the firmware's web UI and the app icon): warm cream `#E9E7E0`
  background, espresso orange accent `#E84B29`, near-black text `#111110`.
- The chart's dashed line is the **target weight**; the solid line is **live weight vs time**.
- Two surfaces: a glanceable **phone** (live + history + export) and a **watch kiosk**
  (live only, large type, readable from across the counter).

## Implementation notes
- The visual system lives in `AppShared/DesignSystem.swift` (tokens, fonts, components,
  the `ExtractionChart`). Fonts use SF Pro `.expanded` + SF Mono (the spec's sanctioned
  substitute for Archivo / Space Mono — no bundled font files).
- Recipe identity (color + icon) carries across Settings, History chips/tags, and detail.
- Light **and** dark modes are intentional via adaptive tokens; the watch is true-black
  with an Always-On dimmed treatment (`isLuminanceReduced`).

## Recipes — focused brief
The **recipe** feature (save a dial-in, tag each shot with it, filter History by it)
spans three surfaces and is the main way shots get organised. It has its own design
brief — including the highest-leverage opportunity (per-recipe colour/icon identity) and
a terminology inconsistency to resolve ("Presets" vs "Recipe"):

→ see **[RECIPES.md](./RECIPES.md)**

Relevant screenshots: `ios-5-settings.png` (preset list), `ios-3-history.png` (tags +
filter).
