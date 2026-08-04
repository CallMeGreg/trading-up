# Development

How to build, run, and change Trading Up. For the game's rules and tuning
rationale see [DESIGN.md](DESIGN.md); for tests see [TESTING.md](TESTING.md).

- [Requirements](#requirements)
- [Run it (5 steps)](#run-it-5-steps)
- [Project layout](#project-layout)
- [Where to tweak the game](#where-to-tweak-the-game)
- [Regenerating content](#regenerating-content)
- [Mockups](#mockups)

---

## Requirements

| Need | Why |
|------|-----|
| **macOS** (Sonoma 14 or newer recommended) | to run Xcode |
| **Xcode 16 or newer** (free, Mac App Store) | builds & runs the app. The project uses Xcode 16's file‑system‑synchronized folders. |
| An **iOS 17+ Simulator** | comes bundled with Xcode; no paid account needed to run in the Simulator |

Optional, only for regenerating content:

| Need | Why |
|------|-----|
| `python3` | every generator in `tools/` is a stdlib‑only Python script |
| `rsvg-convert` (`brew install librsvg`) | rasterizes the card art, app icon and marketing renders |

## Run it (5 steps)

1. **Install Xcode 16+** from the Mac App Store, launch it once, and accept the
   component install prompt.
2. **Open the project**: double‑click `TradingUp.xcodeproj` (or `xed .` from the
   repo root).
3. **Pick a simulator** in the scheme selector at the top — e.g. *iPhone 16*.
4. Press **▶︎ Run** (or `⌘R`). First build takes a moment; the app launches in the
   Simulator.
5. You start with **$100**. Open the **Shop** tab, buy a pack, and tap to reveal!

There's nothing else to install — the app has **zero third‑party dependencies** and
all 250 cards are embedded in the binary.

## Project layout

```
TradingUp.xcodeproj/         Xcode project (open this)
TradingUp/
  Models/                    Pure, testable game logic (Foundation only)
    Card.swift               Card, Rarity, Element, CardDatabase
    Economy.swift            Prices, grading table, value math — all tuning lives here
    GameCore.swift           Deterministic game state: buy / open / sell / grade / bonuses
    Persistence.swift        Versioned save envelope, load hygiene, corrupt-save quarantine
    GameState.swift          @Observable wrapper: randomness + autosave for SwiftUI
    FeatureFlags.swift       Build-time switches (see "Feature flags" below)
  Generated/
    CardData.swift           The 250 cards (auto-generated — do not edit by hand)
  Views/                     SwiftUI screens (Shop, Collection, pack opening, etc.)
  Audio/
    SoundManager.swift       AVAudioPlayer pool + mute preference; Sound.play(.x) API
    SFX/                     3 generated sound effects (auto-generated .wav files)
  Assets.xcassets/           App icon + accent color + CardArt/ (250 card illustrations)
  PrivacyInfo.xcprivacy      Privacy manifest (no tracking, no data collection)
TradingUpTests/              XCTest unit tests (fast, deterministic)
TradingUpUITests/            The screenshot playthrough (TradingUpScreenshots scheme)
data/cards.json              The 250 cards as JSON (source for tooling/other targets)
docs/                        Everything in this folder — design, dev, testing, App Store
  mockups/                   Interactive HTML card-style mockups (open index.html)
  screenshots/               Rendered marketing shots used by the README
tools/
  generate_cards.py          Regenerates data/cards.json AND Generated/CardData.swift
  generate_art.py            Regenerates the 250 card illustrations (needs rsvg-convert)
  generate_icon.py           Regenerates the app icon (needs Pillow)
  generate_sfx.py            Regenerates the 3 sound effects (stdlib only)
  generate_screenshots.py    Renders framed marketing scenes (needs rsvg-convert)
  capture_screenshots.sh     Plays the game in a Simulator and captures real screenshots
  seed_save.py               Writes a completed-collection save (late-game screenshots)
  check_icon.py              Checks the 1024² icon against App Store rules
  check_screenshots.py       Checks captured screenshots against App Store sizes
  verify/main.swift          The Foundation-only simulation harness (see TESTING.md)
```

## Where to tweak the game

Almost all balance knobs (starting cash, pack prices, pack composition, foil
chance, grade odds/multipliers, box guarantees, bonuses) live in
`TradingUp/Models/Economy.swift`. Card names and values live in
`tools/generate_cards.py`.

Re‑run the [verify harness](TESTING.md#the-simulation-harness-no-xcode-needed)
after any economy change — it enforces the target difficulty curve, not just
correctness.

## Feature flags

`TradingUp/Models/FeatureFlags.swift` holds build-time switches for behaviour we
want to turn on or off by editing one line, rather than deleting code and later
digging it back out of git history. Change the value, rebuild — there's no
runtime toggle and nothing is persisted.

| Flag | Default | Effect when `true` |
| --- | --- | --- |
| `removeBoosterBoxes` | `true` | Takes booster boxes off the shop shelf. `SetShelfRow` drops its "Booster box · …" line, `GameState.buyBox` / `buyBoxPacks` refuse the sale so no other call site can spend cash on a box the shop no longer offers, and the "Boxes Opened" tile is dropped from the Stats, win and share‑card screens. `GameCore` and `Economy` keep the box mechanics and their tests, so re‑enabling is a one‑line change — but see `docs/DESIGN.md` §6: boxes paid for the sell‑back spread, so turning them back on needs a balance pass, not just a flag flip. |

Each flag is covered by `TradingUpTests/FeatureFlagTests.swift` in **both**
states, so flipping one is a one-line change rather than a leap of faith.

## Regenerating content

### Cards

After editing names or values in `tools/generate_cards.py`:

```bash
python3 tools/generate_cards.py
```

This rewrites both `data/cards.json` and `TradingUp/Generated/CardData.swift`, and
prints an economy report. Re‑run the [test harness](TESTING.md) afterward.

### Card art

Each of the 250 cards has a deterministic, name‑aligned creature illustration (a
flat‑vector creature on a per‑set scene, tinted to the card's element and scaled
up through its evolution line). To (re)generate the art after editing
`tools/generate_art.py`:

```bash
brew install librsvg                        # one-time: provides rsvg-convert
python3 tools/generate_art.py assets        # 250 PNGs -> Assets.xcassets/CardArt + mockup SVGs
python3 tools/generate_art.py qa            # optional: QA contact sheets to /tmp/qa_set{n}.png
```

The app shows these via `UIImage(named: card.id)` in `CardView`; the procedural
`SigilView` stays as an automatic fallback if an image is ever missing.

### App icon

The icon is Emberpup, card 001, drawn by the *same* code that draws his card art,
so the icon can never drift away from the game's look:

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_icon.py
python3 tools/check_icon.py                  # App Store rules: 1024², no alpha, no baked corners
```

`generate_icon.py` imports the creature straight out of `generate_art.py`, measures
its bounding box from a throwaway render so it can't end up off‑centre or cropped,
and composes it over a square Emberfall backdrop. Both scripts are stdlib‑only
apart from `rsvg-convert`.

`check_icon.py` is what proves the marketing icon is submittable: exactly
1024×1024, 8‑bit, **no alpha channel**, and full‑bleed to the edges (iOS applies
the rounded‑corner mask itself, so a baked‑in one shows up as dark wedges).

### Sound effects

The app keeps a deliberately minimal set of three SFX (a purchase chime when you
buy a pack, a sparkly shimmer for foil pulls, and a coin chime when cards are
sold), each synthesized from scratch with the Python standard library only — no
samples, no dependencies. To regenerate them after editing `tools/generate_sfx.py`:

```bash
python3 tools/generate_sfx.py                # 3 .wav files -> TradingUp/Audio/SFX
```

The file‑system‑synchronized Xcode target picks the `.wav` files up automatically.
`SoundManager` preloads them at launch and honors the in‑app mute toggle (Stats →
Settings), so no wiring is needed after regenerating.

### Marketing renders

The captioned, device‑framed images the README uses are composited as SVG rather
than captured from a running app, so they regenerate anywhere:

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_screenshots.py        # -> docs/screenshots (iPhone 6.5" + iPad 13")
```

These are *not* the ones you submit to Apple — see [APP_STORE.md](APP_STORE.md)
for the real device captures.

## Mockups

Preview the card visual style in a browser without building the app:

```bash
cd docs/mockups && python3 -m http.server 8787
# then open http://localhost:8787
```

`docs/mockups/ui/` is a second, separate gallery: proposed directions for the
**booster pack** and the **Shop home screen** (three options each, plus the
tear‑open interaction). Open `http://localhost:8787/ui/` from the same server.
The app ships the recommended combination — the foil wrapper (P1), the booster
box and pack tray (P3), the shelf list (H1) and tap‑to‑tear — so the gallery now
doubles as the reference for that art (`TradingUp/Views/PackWrapper.swift`).
