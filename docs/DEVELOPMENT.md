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
    GameState.swift          @Observable wrapper: randomness + autosave; owns the full-version entitlement gate and the Binder
    Binder.swift             All-time showcase model: best copy ever owned of each Spryte (survives New Game)
    BinderStore.swift        Versioned store for the Binder, in its own file separate from the run save
    GauntletEconomy.swift    Gauntlet balance knobs: tier config, target curve, interest, RunMods aggregator + GauntletSkillTuning (Trainer skill → advantage seam)
    Trainer.swift            Gauntlet Trainers: per-run archetypes defined by a 5-skill graph (Energy/Aura/Selling/Grading/Inventory); only the Rookie is free, five specialists unlock on milestones, and mystery Red unlocks on beating Hard with all others
    Catalyst.swift           Gauntlet Catalysts: run-long buff cards, one per element lane
    GauntletCore.swift       Deterministic Gauntlet run state machine: rip (per-element pack rail) / keep / grade / shop / round resolution
    GauntletProgress.swift   Cross-run Gauntlet meta: per-Trainer cleared tiers (badges + ladder + Red unlock), unlocked Trainers, lifetime stats, intro-seen flag (survives New Game)
    GauntletProgressStore.swift  Versioned store for Gauntlet progress, in its own file separate from the run save
    GauntletReward.swift     Win payout: the choose-1-of-3 Foil Extended Art reward (rarity, promotion, consolation)
    GauntletState.swift      @Observable driver: runs a GauntletRun, banks progress, routes the win reward into the Binder
    GauntletRunStore.swift   Versioned store for an in-progress run so leaving mid-run saves it to resume (separate from progress + Binder)
    FeatureFlags.swift       Build-time switches (see "Feature flags" below)
  Generated/
    CardData.swift           The 250 cards (auto-generated — do not edit by hand)
  Views/                     SwiftUI screens. Menu shell: MainMenuView + SpryteParadeView (home animation),
                             ClassicModeView (the tabbed game), GauntletView + GauntletFlowViews + GauntletRunViews
                             (the Gauntlet loop), BinderView; plus Shop, Collection, pack opening, PaywallView, etc.
  Store/
    PurchaseStore.swift      StoreKit 2 layer for the one-time full-version unlock (outside Models/)
  Audio/
    SoundManager.swift       AVAudioPlayer pool + mute preference; Sound.play(.x) API
    SFX/                     7 generated sound effects (auto-generated .wav files)
  Assets.xcassets/           App icon + accent color + CardArt/ (250 card illustrations)
  PrivacyInfo.xcprivacy      Privacy manifest (no tracking, no data collection)
  TradingUp.storekit         StoreKit config for testing the IAP in the Simulator (dev only)
TradingUpTests/              XCTest unit tests (fast, deterministic)
TradingUpUITests/            The screenshot playthrough (TradingUpScreenshots scheme)
data/cards.json              The 250 cards as JSON (source for tooling/other targets)
docs/                        Everything in this folder — design, dev, testing, App Store
  mockups/                   Interactive HTML card-style mockups (open index.html)
  screenshots/               Rendered marketing scenes (App Store); app/ = real shots the README uses
tools/
  generate_cards.py          Regenerates data/cards.json AND Generated/CardData.swift
  generate_art.py            Regenerates the 250 card illustrations (needs rsvg-convert)
  generate_icon.py           Regenerates the app icon (needs rsvg-convert)
  generate_trainer_art.py    Regenerates the 7 Gauntlet Trainer emblems (needs rsvg-convert)
  generate_iap_promo.py      Regenerates the IAP promo image (needs rsvg-convert)
  generate_sfx.py            Regenerates the 3 sound effects (stdlib only)
  generate_screenshots.py    Renders framed marketing scenes (needs rsvg-convert)
  capture_screenshots.sh     Plays the game in a Simulator and captures real screenshots
  capture_iap_review.sh      Captures the IAP paywall as the App Review screenshot
  publish_screenshots.sh     Curates 5 of those captures for the README and the website
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

**Gauntlet Mode has its own knobs, kept out of `Economy.swift`.** Tier configs, the
target-Aura curve, interest rate/ceiling, stipend curve, and the `RunMods` aggregator
live in `TradingUp/Models/GauntletEconomy.swift` — which also holds `GauntletSkillTuning`,
the seam that turns a Trainer's five-skill graph into its advantage (its per-pip magnitudes
are `TODO(balance)` zeros today, so every Trainer is currently neutral). The Trainer roster,
skill profiles and unlock thresholds live in `TradingUp/Models/Trainer.swift`; Catalyst
effects in `Catalyst.swift`. The pack rail (which element sets start unlocked and what
unlocking a set costs mid-round) is driven from `GauntletCore.swift`. Gauntlet has its **own**
`tools/verify` checks (§14.8) — a neutral Rookie must still clear Hard, and no Trainer may
trivialise it — so re‑run the harness after any Gauntlet balance change too, especially when
setting the skill magnitudes; trainer-unlock thresholds are meta pacing and don't affect the win-rate
assertions.

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

## In-app purchase (full-version unlock)

The app is free with one non-consumable IAP that unlocks sets 2–5; Set 1 is free
to play in full (design rationale in `docs/DESIGN.md` §11). The moving parts:

- **`TradingUp/Store/PurchaseStore.swift`** — the StoreKit 2 layer. Verifies
  `Transaction.currentEntitlements`, listens to `Transaction.updates`, and pushes
  the verified entitlement into `GameState`. Product id
  `com.callmegreg.tradingup.fullunlock` (`PurchaseStore.fullUnlockProductID`).
- **`GameState.isFullVersionUnlocked`** — the single game-facing flag. Sets above
  `GameState.freeSetCount` (the one knob for the size of the free slice, default
  `1`) gate *buying* packs on it, so `buyPack` / `buyBox` / `buyBoxPacks` refuse a
  still-locked paid set. Progression (`Economy.uniquesToUnlock`) is enforced
  separately, so the unlock opens the paid sets but never skips their milestones.
- **`TradingUp/Views/PaywallView.swift`** — the purchase sheet; `ShopView` opens
  it from a paid, locked set and shows the live StoreKit price.

The gate is unit-tested in both states by
`TradingUpTests/FullUnlockGateTests.swift`, which never touches StoreKit — it
sets the entitlement directly. **The economy is untouched**, so the
[verify harness](TESTING.md#the-simulation-harness-no-xcode-needed) needs no
re-run for this feature.

To exercise the real purchase/restore flow in the Simulator, point the run action
at the bundled StoreKit config: **Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸
StoreKit Configuration → `TradingUp.storekit`**. Then buy in-app, and use
**Debug ▸ StoreKit ▸ Manage Transactions** to refund or reset between runs.

## Regenerating content

### Cards

After editing names or values in `tools/generate_cards.py`:

```bash
python3 tools/generate_cards.py
```

This rewrites both `data/cards.json` and `TradingUp/Generated/CardData.swift`, and
prints an economy report. Re‑run the [test harness](TESTING.md) afterward.

### Card art

Each of the 250 cards has its **own** deterministic, name‑aligned creature
illustration — no card is a recolour of another. Every set has a design language
that changes real geometry (silhouette, limbs, head, eyes, crest, tail, surface),
every slot gets a different concept in each set, and every evolution stage adds
structure rather than scale. To (re)generate the art after editing
`tools/generate_art.py`:

```bash
brew install librsvg                        # one-time: provides rsvg-convert
python3 tools/generate_art.py assets        # 250 PNGs -> Assets.xcassets/CardArt + mockup SVGs
python3 tools/generate_art.py qa            # optional: QA contact sheets to /tmp/qa_set{n}.png
python3 tools/generate_art.py dupes         # fails if any two cards share a character design
```

`dupes` hashes each creature's geometry with the palette and elemental accents
stripped out, so "same shape, different colour" counts as a duplicate. Keep it at
250 unique designs.

The app shows these via `UIImage(named: card.id)` in `CardView`; the procedural
`SigilView` stays as an automatic fallback if an image is ever missing.

### Pack art

Booster packs and booster boxes do *not* use card art. `TradingUp/Views/SetArt.swift`
draws a themed miniature landscape per set with a SwiftUI `Canvas` — volcano
(Emberfall), curling swell over islands (Tidecaller), a stand of jungle trees (Verdspire),
thunderhead and bolt (Voltcrest), eclipse and spirits (Umbral Reach). Use it as
`SetEmblem(set: 1)`; it fills whatever frame you give it, drawing in a fixed
100×100 design space, and skips fine particle detail below 64 pt so shop
thumbnails stay readable. `tools/generate_screenshots.py` mirrors the same scenes
in SVG (`set_emblem`) — change one, change the other.

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

### Trainer emblems

Each Gauntlet Trainer carries a bespoke flat‑vector badge (shown on its card in
the Trainer‑select screen), drawn in the same stdlib‑SVG → `rsvg-convert` style as
the card art — no third‑party art, licence or attribution:

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_trainer_art.py assets # 7 emblems -> Assets.xcassets/TrainerArt
python3 tools/generate_trainer_art.py sheet  # labelled contact sheet -> docs/mockups/trainers
```

Emblems are keyed by Trainer `id` as `trainer-<id>` (so Farmer's asset is
`trainer-appraiser`, matching its persisted id) and loaded via
`UIImage(named:)`; `TrainerEmblem` grays a locked Trainer's badge the same way
the shop fades an unaffordable item, and hides the mystery Trainer (Red) behind a
"?" plate until it's earned. To restyle a Trainer, edit the motif in
`generate_trainer_art.py` and re‑run — never hand‑edit the `TrainerArt` PNGs.

### In-app purchase promo image

The optional 1024×1024 image that represents the "Unlock the Full Collection"
purchase on the App Store is generated the same way, reusing the card art engine
so it can't drift from the game:

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_iap_promo.py          # -> docs/app-store/iap-full-unlock-1024.png
```

`generate_iap_promo.py` fans the five set signature legendaries — one per element,
Emberfall fire → Umbral Reach shadow — so the art reads as "the whole collection"
without any localizable text. It enforces Apple's rules before writing (1024²,
72 dpi, RGB, flattened/no alpha, no rounded corners) and exits non‑zero if any
fail. See [APP_STORE.md](APP_STORE.md#in-app-purchase-promo-image) for where the
image is used.

### In-app purchase App Review screenshot

App Store Connect also requires a review‑only screenshot of the purchase itself.
Rather than mock it, this captures the real paywall the same way the marketing
screenshots are captured — by playing the app in a Simulator:

```bash
tools/capture_iap_review.sh                  # -> docs/app-store/iap-review-full-collection.png
```

`IAPReviewScreenshotTests` launches a fresh save, opens the paywall from a paid,
locked set in the shop, and shoots one frame at **1320×2868** (a valid iPhone
6.9" size, validated before the script exits). The live `$2.99` price comes from
a **DEBUG‑only** `TU_FAKE_PRICE` launch override (a UI‑test host can't load a real
StoreKit product); it's compiled out of release, so shipping builds only ever
show StoreKit's own price. See
[APP_STORE.md](APP_STORE.md#in-app-purchase-app-review-screenshot) for where the
image is uploaded.

### Sound effects

Every SFX is synthesized from scratch with the Python standard library only — no
samples, no dependencies. The set is seven sounds: two for the shop (a purchase
chime when you buy a pack, a coin chime when cards are sold) and five for the pack
reveal — a paper‑rip **pack‑open**, a soft **card‑flip** as each card *after the
first* turns (the first card rides in on the pack‑rip, so it's left silent), an
airy **foil** glisten, and “achievement unlocked” stings for **rare** and **ultra**
pulls. To regenerate them after editing `tools/generate_sfx.py`:

```bash
python3 tools/generate_sfx.py                # 7 .wav files -> TradingUp/Audio/SFX
```

The file‑system‑synchronized Xcode target picks the `.wav` files up automatically.
`SoundManager` preloads them at launch and honors the in‑app mute toggle (the
home‑screen **gear → Settings** sheet, which also carries the **Haptics** toggle).
The reveal fires each sound at its moment in
`TradingUp/Views/RevealAnimation.swift` (`RevealingCardView.run` for the flip/foil/
rare/ultra stings, `SealedPackView.open` for the tear), so no extra wiring is
needed after regenerating.

### Marketing renders

The captioned, device‑framed images the App Store listing uses are composited as
SVG rather than captured from a running app, so they regenerate anywhere:

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_screenshots.py        # -> docs/screenshots (iPhone 6.5" + iPad 13")
```

These are *not* the ones you submit to Apple, and they're not what the README
shows either — see [APP_STORE.md](APP_STORE.md) for the real device captures and
for how five of them get published to the README and the website.

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
