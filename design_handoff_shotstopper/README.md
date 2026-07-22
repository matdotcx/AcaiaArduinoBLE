# Handoff: ShotStopper — Visual System v1

## Overview
ShotStopper is a brew-by-weight espresso companion. It pairs (over BLE) with the **ShotStopper module inside the espresso machine** — which reads a connected scale and controls the brew switch — and shows the pour in real time. Two surfaces:

- **iPhone** (portrait-locked): the full tool — `Live`, `History`, `Settings` tabs, plus pushed screens (Shot detail, Firmware OTA).
- **Apple Watch**: a strapless kiosk mounted on the machine — huge type, readable from across the counter, must degrade gracefully to the Always-On (dimmed) state.

This package is a **visual-system pass**. The information architecture and navigation are settled and must **not** be restructured — this is about elevating the visual layer: a cohesive color/type/spacing system, a hero numeric hierarchy, a parseable extraction chart, intentional light **and** dark modes, a state language, and a **Recipe** identity system.

## About the Design Files
The file in this bundle (`ShotStopper.dc.html`) is a **design reference created in HTML** — a single scrolling "board" that lays out every screen in iPhone/watch frames, light and dark, plus a foundations spec and the recipe system. It is a prototype of the intended look, **not production code to copy**.

Your task is to **recreate these designs in the existing SwiftUI app**, using its established patterns (SwiftUI views, SwiftData models, Swift Charts, CloudKit sync). Match the visuals precisely; implement them idiomatically. Where this doc and the HTML disagree, this doc wins.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, and layout. Recreate pixel-faithfully using native SwiftUI controls. The HTML uses web hacks (e.g. `font-stretch`, SVG curves, `position:absolute` status bars) that have native equivalents called out below — don't port the hacks, port the intent.

---

## Design Tokens

### Color — Light
| Token | Hex | Use |
|---|---|---|
| `cream` (canvas) | `#E9E7E0` | App background |
| `surface` | `#FBFAF4` | Cards, grouped lists, raised surfaces |
| `ink` | `#111110` | Primary text, headings |
| `ink-secondary` | `#4A463F` | Secondary text |
| `ink-muted` | `#6E6A62` | Tertiary text, captions |
| `ink-faint` | `#A6A299` | Disabled, placeholder, micro-labels |
| `disabled-num` | `#C9C5BC` | Idle/empty large numerals |
| `hairline` | `rgba(17,17,16,0.08–0.12)` | Dividers, card borders |

### Color — Dark
| Token | Hex | Use |
|---|---|---|
| `base` (canvas) | `#121110` | App background |
| `surface` | `#1E1C18` | Cards, grouped lists |
| `surface-2` | `#26231E` | Raised/secondary surface |
| `ink` | `#F1EFE8` | Primary text |
| `ink-muted` | `#918C82` | Secondary/caption |
| `ink-faint` | `#6E6A62` | Micro-labels |
| `hairline` | `rgba(241,239,232,0.08–0.14)` | Dividers, borders |

### Brand & State colors
The single brand accent is **espresso orange**. It means three things and **only** these: brand identity, **primary actions**, and the **brewing** state. State semantics:

| State | Light | Dark | Meaning |
|---|---|---|---|
| Idle | `#A6A299` (warm grey) | `#8A8A8E` | Disconnected, waiting, dimmed |
| **Brewing** (orange) | `#E84B29` | `#FB5A35` | Recording / pouring / primary buttons |
| **Done** (green) | `#1F6B4A` | `#43B585` (`#34C98A` on watch) | On target, shot complete |

> The dashed **target** line on charts is deliberately **neutral ink** (not orange) so orange never reads as two different things at once.

### Recipe identity palette
Each recipe carries a **color + icon** that travels across Settings, History tags, the filter chips, and Shot detail. These hues are intentionally distinct from the orange/green/grey *state* colors. Dark mode uses lightened variants for legibility on the dark surface.

| Recipe | Icon | Light hex | Dark (tag text) hex |
|---|---|---|---|
| House Espresso | coffee bean | `#7A4E2E` (umber) | `#D6A87E` / dot `#C08A5E` |
| Ethiopia Light | leaf | `#C28A1E` (amber); tag text `#8A6310` | `#E6BE64` / dot `#E0B24E` |
| Ristretto | droplet | `#A32E3C` (garnet) | `#E89AA6` / dot `#E0788A` |
| Decaf | crescent moon | `#44617F` (slate) | lightened equivalently |

Tag background = recipe color at ~12–18% opacity. Token chip (icon container) = solid recipe color, white glyph, 6–8px corner radius. "No recipe" (untagged shot) = **outlined** capsule, `ink-faint` text, no fill — calm, never an error.

### Typography
Two families. Bundle the variable fonts (both free) or substitute as noted.

- **Archivo** (variable; axes `wght` 100–900, `wdth` 62–125) — all UI text and numerals.
  - **Large numeric readouts** (live weight, watch weight, upload %): `wght ≈ 480` (Book), `wdth ≈ 118` (expanded). This is the signature "precision-gauge" look — large but *light*, never heavy. SwiftUI: load Archivo as a variable font and set the `wght`/`wdth` variations, or use the closest static cut (Archivo Expanded Regular/Medium). Always enable **tabular figures** (`.monospacedDigit()` or the `tnum` feature).
  - **Screen titles**: Archivo `wght 600`, `wdth 110`, ~32px, letter-spacing ≈ -0.9px.
  - **Section header (board)**: `wght 560`, `wdth 118`.
  - **Body / list rows**: Archivo regular/600, 14–17px.
  - **Secondary stat numbers**: `wght 560`, 22px, tabular.
- **Space Mono** (400/700) — micro telemetry labels and captions only: unit labels (`WEIGHT`, `FLOW`, `TARGET`), timestamps, recipe field strings, badges. Typically 9–11px, **letter-spacing 1–2px, UPPERCASE** for labels.

If Archivo licensing/bundling is a problem, the nearest system substitute is **SF Pro** with `.expanded` width + `.monospacedDigit()`, and **SF Mono** for the Space Mono role — but Archivo is the design intent.

### Type scale (digital minimums)
| Role | Size | Weight / width | Notes |
|---|---|---|---|
| Live weight hero (phone) | 104px | 480 / 118 | tabular, letter-spacing -2.5px |
| Watch weight | 74px (58 idle) | 520–560 / 112 | tabular |
| Screen title | 32px | 600 / 110 | |
| Section/stat number | 19–22px | 560–700 | tabular |
| Body | 14–17px | 400–700 | |
| Micro-label (mono) | 9–11px | 400–700 | uppercase, tracked |

### Spacing, radius, shadow
- **Spacing**: 4px base scale (4 / 8 / 12 / 16 / 24 / 32 / 48 …). Layouts breathe.
- **Radius**: grouped list cards 16–18px; inner cards 14px; iOS device-grouped sections feel; **buttons & chips are full pills (`999px` / `.capsule`)** — this is consistent everywhere (primary CTAs, Export, Save/Discard, filter chips, tags); token icon chips 6–8px; watch screen corners large.
- **Shadow**: quiet, warm-tinted, not neutral black. Cards: `0 30px 60px rgba(17,17,16,0.18)` for the device frames (decorative only); in-app cards use subtle `0 6px 18px rgba(17,17,16,0.10)` for floating elements (tab bar). Mostly flat.

### Chart anatomy (the hero — use **Swift Charts**)
The weight-vs-time curve is the centerpiece. Within Swift Charts:
- **Live weight line**: solid, ~3.4px, `.round` caps/joins, colored by state (orange while brewing, green when done/in detail, grey when idle). Add a subtle **area gradient** under the line in the same hue (≈20% → 0% opacity).
- **Target line**: horizontal **dashed** rule at the target weight, neutral ink (`rgba(ink,0.42)` light / `rgba(ink,0.40)` dark), dash pattern ≈ `[2,7]`, with a small mono caption `target 36 g`.
- **Gridlines**: very faint horizontal lines (`rgba(ink,0.07)`), a slightly stronger baseline. Axis labels in Space Mono, `ink-faint`: grams on the right, seconds on the bottom (`0 / 10 / 20 s`).
- **Leading-point dot**: while brewing, a filled dot at the live end of the curve (state color) with a 2.5px halo in the background color.
- Keep it calm and precise — minimal chrome, the curve and target do the work.

---

## Screens / Views

### 1. Live — the hero (`LiveView`)
Portrait. Top→bottom layout, generous horizontal padding (24px):
1. **Status row**: left = connection (state dot + `ShotStopper` device name); right = state pill — `REC` (orange, pulsing dot) while brewing / `DONE` (green check) when complete / nothing when idle.
2. **Hero weight** (the biggest thing on screen): the live grams as a 104px Archivo-Book-expanded tabular numeral + a 30px muted `g` unit, baseline-aligned. Color = ink (brewing), `disabled-num` (idle, shows `0.0`), green (done).
3. **Progress-to-target bar**: 8px pill track (`rgba(ink,0.08)`), fill in state color, width = weight/target. Below it a mono caption row: `WEIGHT` … `46% · target 36 g` (or `target 36 g` idle, `On target +0.0 g · 24.0 s` done).
4. **Secondary stats**: a 3-up grouped card (surface, hairline border, 16px radius) with hairline dividers — `Time` (s), `Flow` (g/s), `Target` (g). Numbers 22px/560 tabular, mono uppercase labels. Idle shows `—`.
5. **Chart** (fills remaining space): see Chart anatomy.
6. **Tab bar**: a floating pill (surface, hairline, soft shadow) with `Live / History / Settings`; active item is an orange pill with white icon+label. (iOS 26 "liquid glass" feel; native `TabView` styling is fine — keep the active = orange treatment.)

**States:**
- **Idle / Not connected**: status dot grey, `Not connected`; hero `0.0` in `disabled-num`; stats `—`; chart area replaced by a **dashed-bordered empty card**: extraction-curve glyph + "Place a cup to begin" + "Connect to the machine and start a shot. The curve draws here in real time." + an orange primary pill `▶ Simulate shot` (on device this is the real start affordance).
- **Brewing**: status `REC` orange pulsing; live number climbing; progress filling; leading dot on curve.
- **Done**: status `DONE` green; hero green at target; progress full green; a two-button pill row appears — **Save shot** (solid ink `#111110`, white text) + **Discard** (outlined). Curve plateaus at the target line.
- Recipe is **not** shown on Live (it's inferable from the target and can't change mid-pull).

### 2. Watch kiosk (`WatchLiveView`) — watchOS, true black
True-black background (`#000`) for OLED + burn-in safety. Layout: a top row (state dot+label left, `→ 36 g` target right), a giant centered weight numeral (74px Archivo expanded, cream/white; green when done; `#5A5A5E` `—` when idle), a compact mono row (`12.6 s` · `1.8 g/s`), and a mini chart (dashed target + state-colored curve, leading dot). Idle shows a small orange `▶ Start` pill.
- **Always-On (dimmed)**: implement via the watchOS `isLuminanceReduced` environment. Drop **all chroma to greys** (weight → `#9A9A9E`, labels → `#5A5A5E`), thin the curve (`#7A7A7E`, ~2.6px), **remove the gradient fill**, dim the state dot. The weight number must stay legible across the counter without lighting the room.

### 3. History (`HistoryView`)
Large title `History` + an `Export` pill (top-right). Below the title: a **horizontal filter-chip row** — `All` (active = solid ink pill, with count) followed by one chip per recipe (recipe-color dot + name, outlined). Tapping a chip filters the list **and changes the nav title to the recipe name** (see filtered state below). Then a single grouped card listing shots; each row:
- left: a small **sparkline** of that shot's curve (state-colored, ~2.4px);
- middle: title (`Today · 16:27`) + a row with the **recipe capsule tag** (or outlined `No recipe`) and the duration (`24.0 s`, mono);
- right: final weight (19px tabular) + a status line (green dot `ON TARGET`, or grey dot with delta `−0.6 g`).

**Filtered state** (`History` filtered to one recipe): title becomes the recipe name preceded by its token chip, with a mono subcaption `4 OF 38 SHOTS` and a circular **× clear** button; the chip for that recipe is active = **solid recipe color**, white text; the list shows only that recipe's shots.

### 4. Shot detail (`ShotDetailView`)
Pushed screen. Header: title `Shot detail` + a mono subtitle `14 JUN · 16:27 · ON TARGET` (green dot). Then the full **chart** (≈240px, see anatomy, with grams/seconds axes). Then a grouped summary card with rows: **Recipe** (token chip + name) · Final weight · Peak weight · Duration · Samples. Then a two-up **pill** button row: **Export CSV** (orange solid) + **Export JSON** (outlined). The back affordance is a **pill at the bottom** of the screen (`‹ Back`), not a top inline title — see navigation note.

### 5. Settings (`SettingsView`)
Large title `Settings`. Sections (grouped cards, mono uppercase section labels):
- **Connection card**: state dot + `ShotStopper` + sub-line `Reading data from the connected scale · firmware v2` + `CONNECTED` badge (green, mono). (We can't detect the scale model, so copy stays generic — do not name a brand.)
- **Recipes**: rows of `[token chip] name · fields` (`36 g · 3 s drip · auto-tare`); the currently-applied recipe shows an `APPLIED` badge (green, mono, right-aligned). Last row: `+ Save current as recipe…` (orange). Empty state: dashed-border bean glyph + "No recipes yet" + "Dial in a shot you like, then save it as a recipe…" + orange `Save current dial-in` pill.
- **Brew**: `Target weight` (value + −/+ stepper; the + is orange), `Brew by weight` toggle, `Auto-tare` toggle. **Toggles are ON = orange** (brand active control).

### 6. Firmware OTA (`FirmwareOTAView`)
Pushed screen. Title `Firmware OTA`. An **uploading card**: orange pulsing dot + `UPLOADING · 192.168.1.42`, a big `64%` numeral, a progress pill bar (orange), `firmware_v3.bin · 1.2 MB · keep app open`. Then **Wi-Fi** group (`Network` / `Password`) and **Device** group (`Current firmware  v2 → v3`, `Choose firmware (.bin)…`). Back pill at the bottom.

### 7. Empty / transitional states
Calm, instructive, never a dead end:
- **Not connected**: crossed-signal glyph + "Bring your phone near the machine. ShotStopper reconnects to it on its own." + ink pill `Scan for ShotStopper`.
- **Connecting…**: spinner (orange) + "Pairing with the ShotStopper in your machine over Bluetooth." + mono `HANDSHAKE · 2 OF 3`.
- **No shots yet**: extraction-curve glyph + "Pull your first shot and it lands here…" + orange pill `▶ Pull a shot`.
- **Flashing firmware**: dark card, orange pulsing dot + `FLASHING FIRMWARE`, big `64%`, progress bar, "don't close the app · ~20 s left".

### 8. App icon (3 directions to choose from)
- **A — Extraction curve**: cream bg, orange sigmoid curve rising to a dashed target line.
- **B — The stop**: near-black bg, a cream droplet meeting an orange cutoff line.
- **C — Monogram**: full-orange bg, an "S" drawn as the extraction curve in cream + dashed baseline.

---

## Interactions & Behavior
- **Tab navigation**: Live / History / Settings (root). Shot detail and Firmware OTA are pushed (`NavigationStack`); their back control is a bottom pill so the title sits at a constant top position across screens.
- **Brew lifecycle**: idle → brewing (auto-detected when weight starts climbing / brew starts) → done (target reached or flow stops). State drives the accent color everywhere (status pill, hero number, progress, curve, leading dot).
- **Recipe filter**: tapping a History chip filters + retitles; `×` clears back to `All`.
- **Steppers/toggles**: target weight −/+ ; toggles animate the standard iOS way but tinted orange.
- **Animation**: subtle. Durations 120/200/320ms; fades and small translations over scale/bounce. The `REC` / uploading dot pulses (opacity 1↔0.25, ~1.4s). Respect **Reduce Motion**.
- **Hover/press**: N/A (touch); press = slight color darken, no scale.

## State Management
- `ConnectionState`: `.disconnected`, `.connecting(step:Int)`, `.connected(firmware:String)`.
- `BrewState`: `.idle`, `.brewing(elapsed, weight, flow)`, `.done(final, peak, duration)`.
- `liveWeight`, `targetWeight`, `flowRate`, `elapsed` — streamed from the module over BLE while brewing.
- `activeRecipe: Recipe?` — the recipe applied to the machine (shows `APPLIED` in Settings).
- `historyFilter: Recipe?` — nil = All.
- Shot samples buffer for the live curve + persisted `Shot` records.

## Data model (SwiftData + CloudKit)
- `Recipe`: id, name, **color**, **icon** (identity), targetWeight, autoTare, minDuration, maxDuration, dripDelay, derived usage (shot count, avg weight). Fields limited to what's controllable over BLE.
- `Shot`: timestamp, finalWeight, peakWeight, duration, target, sample array (for curve), optional `recipe` relationship (nil ⇒ "No recipe").
- Recipes & shots **sync across the user's devices via CloudKit**.

> **Scope guardrails (do not design/build past these):** Recipe fields are only target weight, auto-tare, min/max shot duration, drip delay. **No** temperature / steam / pressure controls (those need a La Marzocco-cloud integration that is out of scope). The app controls a brew switch and reads a scale — nothing deeper. Phone is portrait-locked; watch is its own form factor. Keep it legible one-handed with wet hands; honor **Dynamic Type** and accessibility.

## Design Tokens — quick reference
- Colors: see tables above (light, dark, brand/state, recipe palette).
- Spacing: 4/8/12/16/24/32/48.
- Radius: pills `.capsule`; cards 14–18px; token chips 6–8px.
- Type: Archivo (variable, `wght`/`wdth`) + Space Mono; tabular figures on all numbers.
- Chart: Swift Charts — solid state-colored line + area gradient, dashed neutral target, faint grid, leading dot.

## Assets
- **App icon**: pick one of the 3 directions above; all are simple vector marks (no photography) — rebuild as a vector/SF-Symbols-style asset.
- **Recipe icons**: bean / leaf / droplet / crescent — use SF Symbols equivalents (e.g. `cup.and.saucer`, `leaf`, `drop.fill`, `moon.fill`) or custom glyphs, tinted white on the recipe-color chip.
- **UI icons**: thin-stroke, square-terminal style (chart line, clock, gear, share/upload, chevrons, plus, check, wifi). Map to SF Symbols.
- No raster assets are required; everything is type, color, and vector.

## Files
- `ShotStopper.dc.html` — the full design board (open in any browser). Scroll through: `01 Foundations`, `02 App icon`, `03 Live (hero)`, `04 Watch kiosk`, `05 Supporting screens`, `06 Empty & transitional states`, `07 Recipes`. Light and dark variants are shown side by side. This is the single source of truth for the visuals.
