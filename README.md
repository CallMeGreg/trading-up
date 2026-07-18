# Trading Up

A collectible-card **collecting & economy** game for iOS, built with SwiftUI. It's
inspired by the loop of opening trading-card packs, chasing rares and foils, grading
your best pulls, and completing sets — but with a wholly original world (the
**Mythlings**) and **no Pokémon names, characters, or artwork**.

Start with **$100**, rip packs, flip duplicates back to the shop, grade your hits,
and try to collect all **250** cards across **5 sets** — without going broke.

---

## Contents

- [Overview](#overview)
- [How to play](#how-to-play)
- [Local development & testing](#local-development--testing)
  - [Requirements](#requirements)
  - [Run it (5 steps)](#run-it-5-steps)
  - [Testing (no Xcode needed)](#testing)
  - [Project layout](#project-layout)
  - [Regenerating content](#regenerating-content)

---

## Overview

Trading Up is a single-player **collecting & economy** game: buy packs, open them,
sell duplicates back to the shop, grade your best pulls, and chase a complete
collection before your cash runs out. Everything — all 250 cards across 5 sets — is
embedded in the app, which has **zero third‑party dependencies**.

See **[DESIGN.md](DESIGN.md)** for the full write‑up: the Mythlings world, all five
sets and their themes, the rarity value bands, the complete economy and grading
tables, booster‑box guarantees, bonus payouts, and win/lose rules.

The card art is generated deterministically by `tools/generate_art.py`: every card
gets a name‑aligned, flat‑vector creature on a per‑set scene, tinted to its element
and scaled up through its evolution line. The rendered images live in the asset
catalog (`TradingUp/Assets.xcassets/CardArt`) and, as SVGs, in the HTML mockups
(`design/mockups/art`). The app's procedural `SigilView` remains as a fallback.

---

## How to play

- **Shop** — each of the 5 sets sells a **Pack** (6 cards) or a **Booster Box**
  (24 packs, cheaper per pack, with guaranteed foils & ultras). Higher sets cost
  more but contain more valuable cards.
- **Open packs** — tap to reveal cards one at a time. Every pack is
  **3 commons, 2 uncommons, and 1 rare‑or‑ultra**. Every card has a **1%** chance
  to be a shiny **foil** (×3 value). On the summary, brand‑new cards are flagged
  **✦ NEW** in the corner — **tap any duplicate (the cards without a NEW tag) to
  keep or sell it individually**, or use **Sell Duplicates** / **Keep All** at the
  bottom (blue = keep, green = sell). The sell total updates live as you decide
  each card.
- **Collection** — browse all 50 cards per set. Owned cards show off their best
  copy; unowned cards are locked silhouettes. Tap a card for details. Filter the
  grid by **Dupes**, **Foils**, and **Rare+** — combine filters to narrow further
  (e.g. Dupes + Foils shows only foil duplicates).
- **Sell** — flip duplicate cards back to the shop for cash. You can **never sell
  your last copy** of a card, so your collection is safe.
- **Grade** — send a rare/ultra to grading for a fee. The PSA grade you roll
  changes its value a lot: a **PSA 10** is ×5, a **PSA 9** is ×2, a **PSA 1** is a
  freak ×10 jackpot — but grades 2–7 are worth *less* than ungraded. Grading and
  foils stack.
- **Bonuses** — completing an **evolution line** pays a cash bonus; completing a
  whole **set** pays a big one.
- **Win** by collecting all **250** cards. **Lose** if your cash drops **below $10**
  (the cheapest pack) with no duplicates left to sell.

Your progress **auto‑saves** after every action.

---

## Local development & testing

### Requirements

| Need | Why |
|------|-----|
| **macOS** (Sonoma 14 or newer recommended) | to run Xcode |
| **Xcode 16 or newer** (free, Mac App Store) | builds & runs the app. The project uses Xcode 16's file‑system‑synchronized folders. |
| An **iOS 17+ Simulator** | comes bundled with Xcode; no paid account needed to run in the Simulator |

### Run it (5 steps)

1. **Install Xcode 16+** from the Mac App Store, launch it once, and accept the
   component install prompt.
2. **Open the project**: double‑click `TradingUp.xcodeproj` (or `xed .` from this
   folder).
3. **Pick a simulator** in the scheme selector at the top — e.g. *iPhone 16*.
4. Press **▶︎ Run** (or `⌘R`). First build takes a moment; the app launches in the
   Simulator.
5. You start with **$100**. Open the **Shop** tab, buy a pack, and tap to reveal!

There's nothing else to install — the app has **zero third‑party dependencies** and
all 250 cards are embedded in the app.

### Testing

The entire game economy and rules are covered by a Foundation‑only simulation you
can run **without Xcode** (just the Swift toolchain from Command Line Tools):

```bash
swiftc TradingUp/Models/Card.swift \
       TradingUp/Models/Economy.swift \
       TradingUp/Models/GameCore.swift \
       TradingUp/Generated/CardData.swift \
       tools/verify/main.swift \
       -o /tmp/tu_verify && /tmp/tu_verify
```

This checks, among other things:

- all 250 cards load and match the Swift model, with unique names/ids;
- each set's rarity split is 25/15/7/3 and value bands don't overlap (best of a
  tier is worth less than the worst of the next);
- **pack expected value matches each set's target curve** — 1.1× / 1.0× / 0.9× / 0.8× /
  0.7× of the pack price for sets 1–5 (Monte Carlo);
- the **PSA grade odds** match the spec exactly and sum to 100%;
- selling protects your last copy; the game‑over check is correct;
- collecting all 250 triggers the win and pays every evolution/set bonus exactly
  once.

It prints `ALL CHECKS PASSED ✅` on success.

### Project layout

```
TradingUp.xcodeproj/         Xcode project (open this)
TradingUp/
  Models/                    Pure, testable game logic (Foundation only)
    Card.swift               Card, Rarity, Element, CardDatabase
    Economy.swift            Prices, grading table, value math — all tuning lives here
    GameCore.swift           Deterministic game state: buy / open / sell / grade / bonuses
    GameState.swift          ObservableObject wrapper: randomness + autosave for SwiftUI
  Generated/
    CardData.swift           The 250 cards (auto‑generated — do not edit by hand)
  Views/                     SwiftUI screens (Shop, Collection, pack opening, etc.)
  Audio/
    SoundManager.swift       AVAudioPlayer pool + mute preference; Sound.play(.x) API
    SFX/                     3 generated sound effects (auto‑generated .wav files)
  Assets.xcassets/           App icon + accent color + CardArt/ (250 card illustrations)
data/cards.json              The 250 cards as JSON (source for tooling/other targets)
design/
  DESIGN.md                  Full game design document
  mockups/                   Interactive HTML card‑style mockups (open index.html)
  screenshots/               Generated App Store screenshots (6.9" + 6.5")
tools/
  generate_cards.py          Regenerates data/cards.json AND Generated/CardData.swift
  generate_art.py            Regenerates the 250 card illustrations (needs rsvg-convert)
  generate_icon.py           Regenerates the app icon (needs Pillow)
  generate_sfx.py            Regenerates the 3 sound effects (stdlib only)
  generate_screenshots.py    Regenerates App Store screenshots (needs rsvg-convert)
  verify/main.swift          The simulation test harness described above
```

**Where to tweak the game:** almost all balance knobs (starting cash, pack prices,
pack composition, foil chance, grade odds/multipliers, box guarantees, bonuses)
live in `TradingUp/Models/Economy.swift`. Card names/values live in
`tools/generate_cards.py`.

### Regenerating content

**Cards** — after editing names or values in `tools/generate_cards.py`:

```bash
python3 tools/generate_cards.py
```

This rewrites both `data/cards.json` and `TradingUp/Generated/CardData.swift`, and
prints an economy report. Re‑run the [test harness](#testing) afterward.

**Card art** — each of the 250 cards has a deterministic, name‑aligned creature
illustration (a flat‑vector creature on a per‑set scene, tinted to the card's
element). To (re)generate the art after editing `tools/generate_art.py`:

```bash
brew install librsvg                        # one‑time: provides rsvg-convert
python3 tools/generate_art.py assets        # 250 PNGs -> Assets.xcassets/CardArt + mockup SVGs
python3 tools/generate_art.py qa            # optional: QA contact sheets to /tmp/qa_set{n}.png
```

The app shows these via `UIImage(named: card.id)` in `CardView`; the procedural
`SigilView` stays as an automatic fallback if an image is ever missing.

**App icon** — the icon is the game's procedural "sigil" rendered with Pillow:

```bash
python3 -m venv .venv && .venv/bin/pip install Pillow
.venv/bin/python tools/generate_icon.py
```

**Sound effects** — the app keeps a deliberately minimal set of three SFX (a
purchase chime when you buy a pack, a sparkly shimmer for foil pulls, and a coin
chime when cards are sold), each synthesized from scratch with the Python standard
library only (no samples, no dependencies). To regenerate them after editing
`tools/generate_sfx.py`:

```bash
python3 tools/generate_sfx.py                # 3 .wav files -> TradingUp/Audio/SFX
```

The file‑system‑synchronized Xcode target picks the `.wav` files up automatically.
`SoundManager` preloads them at launch and honors the in‑app mute toggle (Stats →
Settings), so no wiring is needed after regenerating.

**App Store screenshots** — faithful, marketing‑ready screenshots are composited
as SVG (exact app palette + embedded real card art) and rasterized to the official
sizes. To regenerate them after editing `tools/generate_screenshots.py`:

```bash
brew install librsvg                         # one‑time: provides rsvg-convert
python3 tools/generate_screenshots.py        # -> design/screenshots (6.9" + 6.5")
```

This writes five framed scenes (reveal, shop, collection, grade, win) at both
1290×2796 (6.9") and 1242×2688 (6.5") — the two required App Store display sizes.

**Mockups** — preview the card visual style in a browser:

```bash
cd design/mockups && python3 -m http.server 8787
# then open http://localhost:8787
```
