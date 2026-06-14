# Design brief — Recipes (a.k.a. presets)

Companion to the screenshots in this folder. See `ios-5-settings.png` (the preset
list) and `ios-3-history.png` (the recipe tags + filter).

## What it is
A *recipe* is a named bundle of per-coffee brew settings used to dial in a coffee:
target weight, auto-tare, min/max shot duration, drip delay. The loop is:
**save** a recipe → **apply** it to the machine → every shot pulled while it's active
is **tagged** with it → later, **filter** History to compare all shots made with that
recipe.

## Where it appears (3 surfaces — should feel like one concept)
1. **Settings → "Presets" section** (`ios-5-settings.png`): a list of saved recipes,
   each showing name + a summary line (`36 g · 3 s drip · auto-tare`). Tap to apply;
   "Save current as preset…"; swipe to delete.
2. **History → recipe tag + filter** (`ios-3-history.png`): each shot row carries a
   recipe capsule tag (currently a generic tinted capsule). A toolbar filter icon
   narrows the list to one recipe; the nav title becomes the recipe name.
3. **Shot detail**: a "Recipe" row in the summary grid.

## States to design for
- **Untagged shots** (pulled with no recipe / after a manual setting change) — needs a
  clear, calm "no recipe" treatment vs. tagged.
- A recipe is the **primary way to group/compare shots**, so its identity should be
  visually strong and *consistent across all 3 surfaces*.

## Opportunities I'd most want explored
- **Per-recipe identity (color + maybe icon).** Every tag is the same tint today.
  Giving each recipe a colour/symbol that carries across the History tag, the filter,
  and the detail would make scanning months of shots genuinely powerful — the single
  highest-leverage move here.
- **Filter affordance.** It's a hidden toolbar menu today. Consider a row of filter
  chips above the list (one per recipe) so comparison is one tap and the available
  recipes are visible at a glance.
- **"Currently active recipe" indicator.** Nothing shows which recipe is applied to the
  machine right now. Worth surfacing (Live tab header? a badge in Settings?).
- **Preset list richness.** Plain rows now — could be cards, could show usage
  ("12 shots, avg 35.8 g").
- **Empty state** for recipes ("No recipes yet — save your current dial-in").

## ⚠️ Terminology to resolve
The UI is inconsistent: the Settings section says **"Presets"**, but the tags / filter /
detail say **"Recipe."** Please pick one and apply everywhere. Recommendation:
**"Recipe"** (warmer, coffee-native).

## Constraints (don't design past these)
- Recipe fields are limited to what we control over BLE: **target weight, auto-tare,
  min/max shot duration, drip delay**. No temperature / steam / pressure fields — those
  need La Marzocco cloud integration, which is out of scope.
- Built in SwiftUI / SwiftData; tags are SwiftUI capsules; recipes sync across the
  user's devices via CloudKit.
