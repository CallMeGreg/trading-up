# Trading Up

A collectible-card **collecting & economy** game for iOS, built with SwiftUI. It's
inspired by the loop of opening trading-card packs, chasing rares and foils, grading
your best pulls, and completing sets — but with a wholly original world (the
**Sprytes**) and **no Pokémon names, characters, or artwork**.

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

See **[DESIGN.md](DESIGN.md)** for the full write‑up: the Sprytes world, all five
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
  (12 packs, with guaranteed foils & ultras). Higher sets cost **steeply** more
  ($10 → $30 → $75 → $160 → $320) but contain more valuable cards. A box costs
  **11× the pack price** — you buy it for the guaranteed chase cards, not a discount.
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
- **Sell** — flip duplicate cards back to the shop for cash. The shop buys at a
  **buylist spread**: you get **65%** of a card's market value, so churning packs and
  dumping dupes slowly bleeds money — that spread is the game's main risk. You can
  **never sell your last copy** of a card, so your collection is safe.
- **Grade** — send a rare/ultra to grading for a flat per‑set fee (**$2–$10**). The PSA
  grade you roll changes its value a lot: a **PSA 10** is ×5, a **PSA 9** is ×2, a
  **PSA 1** is a freak ×10 jackpot — but grades 2–7 are worth *less* than ungraded.
  Because the fee is cheap next to a pricey card, **grading valuable dupes before you
  sell them** is a real edge. Grading and foils stack.
- **Bonuses** — completing an **evolution line** pays a cash bonus; completing a
  whole **set** pays a big one (**15× the pack price**).
- **Win** by collecting all **250** cards. **Lose** if your cash drops **below $10**
  (the cheapest pack) with no duplicates left to sell — with the buylist spread and
  steep prices, careless spam‑and‑dump really can bankrupt you. Winning is a
  celebration, not an ending: dismiss the win screen and your completed collection
  stays yours to browse — starting over is always an explicit, confirmed choice.

Your progress **auto‑saves** after every action. Saves carry a schema version, tolerate
missing or newly added fields, and are **never silently discarded** — an unreadable save
is moved aside rather than deleted.

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
       TradingUp/Models/Persistence.swift \
       TradingUp/Generated/CardData.swift \
       tools/verify/main.swift \
       -o /tmp/tu_verify && /tmp/tu_verify
```

This checks, among other things:

- all 250 cards load and match the Swift model, with unique names/ids;
- each set's rarity split is 25/15/7/3 and value bands don't overlap (best of a
  tier is worth less than the worst of the next);
- **pack expected value matches each set's target curve** — 1.0× / 0.9× / 0.8× / 0.7× /
  0.6× of the pack price for sets 1–5 (Monte Carlo);
- the **PSA grade odds** match the spec exactly and sum to 100%;
- the **economy knobs** are set as designed — steep pack prices `[10,30,75,160,320]`,
  flat grade fees `[2,4,6,8,10]`, booster box at 11× pack price, set‑completion bonus at
  15× pack price, and a **65% sell‑back rate**;
- the **sell‑back spread** works — a duplicate sells for 65% of market value, and
  buying into an already‑complete set then dumping the dupes is a **net loss** (the
  core losing risk);
- the **save format is forward‑compatible** — a payload missing newer keys (or missing
  every key) still decodes to sensible defaults, the envelope carries its schema
  version, a pre‑envelope save still loads, retired card ids are stripped rather than
  crashing, and an unreadable save is **quarantined on disk, never deleted**;
- **winning doesn't erase your collection** — the celebration shows once, and dismissing
  it leaves the finished collection browsable;
- **strategy simulations** hold the "moderate" difficulty target — reckless
  spam‑and‑dump play **busts ~44%** of the time, while thoughtful play (pace buys, grade
  valuable dupes before selling) still **wins ~77%**, a clear skill gap;
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
    Persistence.swift        Versioned save envelope, load hygiene, corrupt-save quarantine
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
  app-store/                 Ready‑to‑paste App Store Connect listing metadata
  mockups/                   Interactive HTML card‑style mockups (open index.html)
  screenshots/               Framed marketing renders (6.9" + 6.5")
    appstore/                Real device captures from an automated playthrough
DESIGN.md                    Full game design document
tools/
  generate_cards.py          Regenerates data/cards.json AND Generated/CardData.swift
  generate_art.py            Regenerates the 250 card illustrations (needs rsvg-convert)
  generate_icon.py           Regenerates the app icon (needs Pillow)
  generate_sfx.py            Regenerates the 3 sound effects (stdlib only)
  generate_screenshots.py    Renders framed marketing scenes (needs rsvg-convert)
  capture_screenshots.sh     Plays the game in a Simulator and captures real screenshots
  seed_save.py               Writes a completed‑collection save (late‑game screenshots)
  check_icon.py              Checks the 1024² icon against App Store rules
  check_screenshots.py       Checks captured screenshots against App Store sizes
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

**App icon** — the icon is Emberpup, card 001, drawn by the *same* code that draws
his card art, so the icon can never drift away from the game's look:

```bash
brew install librsvg                         # one‑time: provides rsvg-convert
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

**App Store screenshots** — the ones to actually upload are captured by *playing
the game*. `TradingUpUITests/ScreenshotTests.swift` starts from a wiped app
container, buys packs with the $100 the game gives you, rips them card by card,
sells the duplicates, grades a rare and browses the collection it built — taking
full‑resolution device screenshots along the way. A second short pass seeds a
completed collection (`tools/seed_save.py`) so the win screen, a finished set and
a booster box are covered too.

```bash
tools/capture_screenshots.sh                 # both required sizes, ~10 minutes
tools/capture_screenshots.sh "iPhone 17 Pro Max"   # just one device
tools/capture_screenshots.sh --only endgame  # refresh shots 25-29 only
```

Output lands in `design/screenshots/appstore/<device>/` — 29 numbered PNGs per
device at **1320×2868** (iPhone 6.9") and **2064×2752** (iPad 13"). Both are
required: the target ships `TARGETED_DEVICE_FAMILY = "1,2"`, so App Store Connect
asks for an iPad set as well as an iPhone set. `tools/check_screenshots.py <dir>`
re‑validates sizes and alpha channels, and the capture script runs it for you.

The PNGs are **gitignored on purpose** — they're build output, and ~65 MB a
capture would dwarf the rest of the repo. Regenerate on demand; the set you
submit lives in App Store Connect. `--only playthrough|endgame` re‑shoots just
one pass, which is handy when a change only affects part of the game.

The screenshots use the `TradingUpScreenshots` scheme, which is deliberately
separate from the `TradingUp` scheme so CI's unit‑test run stays fast.

Optional stylized alternates — device‑framed scenes with marketing captions,
composited as SVG rather than captured from a running app — come from the older
generator:

```bash
brew install librsvg                         # one‑time: provides rsvg-convert
python3 tools/generate_screenshots.py        # -> design/screenshots (6.9" + 6.5")
```

**App Store listing copy** — recommended values for every App Store Connect
field (name, subtitle, keywords, description, age‑rating answers, privacy,
review notes) are in [`design/app-store/listing.md`](design/app-store/listing.md).

**Privacy manifest** — `TradingUp/PrivacyInfo.xcprivacy` declares no tracking and
no data collection, plus the one required‑reason API the app touches:
`UserDefaults` (the mute preference), under reason `CA92.1`. Apple bounces
uploads that use such an API without declaring it, so keep the manifest in sync
if the app ever grows a new dependency or starts talking to the network.

**Mockups** — preview the card visual style in a browser:

```bash
cd design/mockups && python3 -m http.server 8787
# then open http://localhost:8787
```
