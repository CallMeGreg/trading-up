# Trading Up

A collectible-card **collecting & economy** game for iOS, built with SwiftUI. It's
inspired by the loop of opening trading-card packs, chasing rares and foils, grading
your best pulls, and completing sets — but with a wholly original world (the
**Mythlings**) and **no Pokémon names, characters, or artwork**.

Start with **$100**, rip packs, flip duplicates back to the shop, grade your hits,
and try to collect all **250** cards across **5 sets** — without going broke.

> Status: fully playable first build. All game logic is verified by an automated
> simulation (see [Testing](#testing)). Art is procedural placeholder "sigils" —
> good enough to ship a prototype, ready to be swapped for real illustrations later.

---

## Contents

- [Requirements](#requirements)
- [Run it (5 steps)](#run-it-5-steps)
- [How to play](#how-to-play)
- [Testing (no Xcode needed)](#testing)
- [Project layout](#project-layout)
- [Regenerating content](#regenerating-content)
- [Game design](#game-design)
- [Road to the App Store](#road-to-the-app-store)

---

## Requirements

| Need | Why |
|------|-----|
| **macOS** (Sonoma 14 or newer recommended) | to run Xcode |
| **Xcode 16 or newer** (free, Mac App Store) | builds & runs the app. The project uses Xcode 16's file‑system‑synchronized folders. |
| An **iOS 17+ Simulator** | comes bundled with Xcode; no paid account needed to run in the Simulator |

> Command Line Tools alone are **not** enough to run the app — you need the full
> Xcode application. (The logic test harness in [Testing](#testing) *does* run with
> just Command Line Tools.)

---

## Run it (5 steps)

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

---

## How to play

- **Shop** — each of the 5 sets sells a **Pack** (6 cards) or a **Booster Box**
  (24 packs, cheaper per pack, with guaranteed foils & ultras). Higher sets cost
  more but contain more valuable cards.
- **Open packs** — tap to reveal cards one at a time. Every pack is
  **3 commons, 2 uncommons, and 1 rare‑or‑ultra**. Every card has a **1%** chance
  to be a shiny **foil** (×3 value).
- **Collection** — browse all 50 cards per set. Owned cards show off their best
  copy; unowned cards are locked silhouettes. Tap a card for details.
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

## Testing

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
- **pack expected value ≈ 1.1× the pack price** (Monte Carlo);
- the **PSA grade odds** match the spec exactly and sum to 100%;
- selling protects your last copy; the game‑over check is correct;
- collecting all 250 triggers the win and pays every evolution/set bonus exactly
  once.

It prints `ALL CHECKS PASSED ✅` on success.

---

## Project layout

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
  Assets.xcassets/           App icon + accent color
data/cards.json              The 250 cards as JSON (source for tooling/other targets)
design/
  DESIGN.md                  Full game design document
  mockups/                   Interactive HTML card‑style mockups (open index.html)
tools/
  generate_cards.py          Regenerates data/cards.json AND Generated/CardData.swift
  generate_icon.py           Regenerates the app icon (needs Pillow)
  verify/main.swift          The simulation test harness described above
```

**Where to tweak the game:** almost all balance knobs (starting cash, pack prices,
pack composition, foil chance, grade odds/multipliers, box guarantees, bonuses)
live in `TradingUp/Models/Economy.swift`. Card names/values live in
`tools/generate_cards.py`.

---

## Regenerating content

**Cards** — after editing names or values in `tools/generate_cards.py`:

```bash
python3 tools/generate_cards.py
```

This rewrites both `data/cards.json` and `TradingUp/Generated/CardData.swift`, and
prints an economy report. Re‑run the [test harness](#testing) afterward.

**App icon** — the icon is the game's procedural "sigil" rendered with Pillow:

```bash
python3 -m venv .venv && .venv/bin/pip install Pillow
.venv/bin/python tools/generate_icon.py
```

**Mockups** — preview the card visual style in a browser:

```bash
cd design/mockups && python3 -m http.server 8787
# then open http://localhost:8787
```

---

## Game design

See **[DESIGN.md](DESIGN.md)** for the full write‑up: the Mythlings world, all five
sets and their themes, the rarity value bands, the complete economy and grading
tables, booster‑box guarantees, bonus payouts, and win/lose rules.

The card art is generated procedurally: a deterministic "sigil" emblem derived from
each card's name so the same card always looks the same. The exact same algorithm is
used in the HTML mockups (`design/mockups/cards.js`) and in the app
(`TradingUp/Views/SigilView.swift`), so what you preview is what you get.

---

## Road to the App Store

This repo is a complete, runnable prototype. To actually publish it you'll need to:

1. **Enroll in the Apple Developer Program** ($99/year) — required to ship to the
   App Store and to run on a physical device.
2. **Set your signing team** in Xcode: select the *TradingUp* target →
   *Signing & Capabilities* → pick your team. The bundle id is
   `com.callmegreg.tradingup` (change if you like).
3. **Commission real artwork** for the 250 cards (and a polished app icon) to
   replace the procedural placeholders.
4. **Add polish**: sound effects, richer pack‑opening animation, App Store
   screenshots, and an App Privacy questionnaire (this app collects no data).
5. **Test on device** and distribute a beta via **TestFlight** before submitting for
   review.

---

*Built as a first iOS project. No Pokémon assets, names, or trademarks are used;
all characters, sets, and art are original to Trading Up.*
