# Development

How to build, run, and change Trading Up. For the game's rules and tuning
rationale see [DESIGN.md](DESIGN.md); for tests see [TESTING.md](TESTING.md).

- [Requirements](#requirements)
- [Run it (5 steps)](#run-it-5-steps)
- [Test app versus production](#test-app-versus-production)
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
3. **Select the `TradingUpTest` scheme**, then pick a simulator at the top —
   e.g. *iPhone 16*.
4. Press **▶︎ Run** (or `⌘R`). First build takes a moment; the app launches in the
   Simulator.
5. You start with **$100**. Open the **Shop** tab, buy a pack, swipe across its
   glowing top seam to rip it open, then tap through the cards.

There's nothing else to install — the app has **zero third‑party dependencies** and
all 250 cards are embedded in the binary.

## Test app versus production

Use **`TradingUpTest` for development and personal TestFlight builds**. Keep
`TradingUp` for the shipping app. Both schemes compile the same app target and
source files and share version/build numbers; the test app has its own identity
and automatic full-game access.

| Setting | Production | Test app |
| --- | --- | --- |
| Scheme | `TradingUp` | `TradingUpTest` |
| Run / unit-test configuration | `Debug` | `Debug-Test` |
| Archive / profile configuration | `Release` | `Release-Test` |
| Bundle identifier | `com.callmegreg.tradingup` | `com.callmegreg.tradingup.test` |
| Home Screen name | Trading Up | Trading Up Test |
| Full-unlock product ID | `com.callmegreg.tradingup.fullunlock` | `com.callmegreg.tradingup.test.fullunlock` |
| Local StoreKit catalog | `TradingUp.storekit` | `TradingUpTest.storekit` |
| Full-game access | Verified StoreKit purchase | Automatic, without StoreKit |

The **bundle identifier**, not the build number or scheme name, lets iOS install
both apps side by side. The existing production identifier is unchanged. Saves,
Binder, Gauntlet progress/runs, preferences, and the cached purchase entitlement
use each app's own sandbox, so the test app starts fresh without reading,
migrating, or clearing production data. Production purchases are not shared with
the test app; the test app automatically opens all paid content instead. This is
app/data isolation, not a separate backend deployment: the game still runs offline.

Automatic access requires **both** `TRADING_UP_TEST_APP` (defined only on the app
target's `Debug-Test` and `Release-Test` configurations) **and** the exact bundle
ID `com.callmegreg.tradingup.test`. Neither `DEBUG`, a TestFlight/sandbox receipt,
an environment variable, nor a saved preference enables it. The grant happens
before any StoreKit work, remains active across refreshes and new runs, and is
never written to the cached purchase entitlement or game save. Classic set
progression and Gauntlet milestones still apply. Production `Debug`/`Release`
compile out the automatic grant; even a mistakenly added test compiler flag
cannot enable it under the production bundle ID.

For a physical iPhone, select `TradingUpTest` and the connected device. In the
`TradingUp` target's **Signing & Capabilities**, select your team and automatic
signing, including the `Debug-Test` and `Release-Test` configurations. Enable
Developer Mode on the phone if Xcode requests it, then Run. Direct Xcode
installation needs no App Store Connect app record. **Do not run the production
scheme on a phone whose App Store installation you want to preserve.**

For TestFlight, follow [the one-time Apple setup](APP_STORE.md#separate-test-app-testflight).
A test archive must use `Release-Test`; overriding it with plain `Release`
would build the production identity even with the test scheme selected.

**Build numbers are shared across production and test.** For each new release
pair, choose one more than the highest build in either app's project settings
or local Organizer archives, also accounting for any higher uploads from
another Mac. Set `CURRENT_PROJECT_VERSION` to that number in **all four app
configurations** (`Debug`, `Release`, `Debug-Test`, `Release-Test`), never in the
XCTest/UI-test targets. Keep `MARKETING_VERSION` equal across all four too, and
change it only when the public version changes.

The `/build` skill creates **both signed archives from the same source commit**,
with one PR and one shared build-number bump. `/build production` and
`/build test` are aliases for that paired workflow, not independent counters.
Neither app is uploaded automatically. Starting with **1.2.2 (42)**, matching
production/test build numbers identify the matching release pair; the older
production 41 and test 5 sequences are historical.

`Release-Test` has the same optimization as `Release` and does not define
`DEBUG`. Its automatic full-game access is the sole intentional gameplay-access
difference. Keep other matching production/test build settings in sync; the
configuration checks in [TESTING.md](TESTING.md#app-identity) guard against drift.
The screenshot scheme deliberately stays on the production identity.

## Project layout

```
TradingUp.xcodeproj/         Xcode project (open this)
TradingUp/
  Models/                    Pure, testable game logic (Foundation only)
    Card.swift               Card, Rarity, Element, CardDatabase
    Economy.swift            Prices, grading table, value math — all tuning lives here
    GameCore.swift           Deterministic game state: buy / open / sell / grade / bonuses
    Collector.swift          Classic NPC requests, protected goals, exact-copy barter, and CollectorEconomy tuning
    Persistence.swift        Versioned save envelope, load hygiene, corrupt-save quarantine
    GameState.swift          @Observable wrapper: randomness + autosave; owns the full-version entitlement gate and the Binder
    Binder.swift             All-time showcase model: best copy ever owned of each Spryte (survives New Game)
    BinderStore.swift        Versioned store for the Binder, in its own file separate from the run save
    GauntletEconomy.swift    Gauntlet balance knobs: independent sell-back rate, tier config, target curve, interest, RunMods aggregator + GauntletSkillTuning (Trainer skill → advantage seam)
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
    TestBuildAccess.swift    Compile-time and exact-bundle-ID guard for automatic test-app access
  Audio/
    SoundManager.swift       Pooled Studio SFX + looping mode music; ambient audio/lifecycle handling
    AudioPreferences.swift   Independent Music/SFX levels and remembered one-tap mute
    Sound.swift              48 action cues, alternate-take resource names and grade-result selection
    SFX/                     60 approved Studio WAVs (generated; includes alternate takes)
    Music/                   2 original mode music loops (generated AAC)
  Assets.xcassets/           App icon + accent color + CardArt/ (250 card illustrations)
  PrivacyInfo.xcprivacy      Privacy manifest (no tracking, no data collection)
  TradingUp.storekit         StoreKit config for testing the IAP in the Simulator (dev only)
  TradingUpTest.storekit     Separate local purchase catalog for the test app
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
  generate_sfx.py            Publishes hash-pinned, approved Studio takes into the app
  generate_sound_lab.py      Renders/checks the review-only A/B soundboard (stdlib only)
  generate_music.py          Composes the mode music and audition alternatives (offline AAC encoding)
  generate_screenshots.py    Renders framed marketing scenes (needs rsvg-convert)
  capture_screenshots.sh     Plays the game in a Simulator and captures real screenshots
  capture_iap_review.sh      Captures the IAP paywall as the App Review screenshot
  publish_screenshots.sh     Curates 5 of those captures for the README and the website
  seed_save.py               Writes a completed-collection save (late-game screenshots)
  check_icon.py              Checks the 1024² icon against App Store rules
  check_screenshots.py       Checks captured screenshots against App Store sizes
  test_app_identity.py       Guards app identities, scheme routing, catalogs, build parity, and compiled test-unlock isolation
  verify/main.swift          The Foundation-only simulation harness (see TESTING.md)
  verify/classic_sim.swift   Reachable Classic policies, collector ablations, and 75% / 10% balance guardrails
```

## Where to tweak the game

Almost all balance knobs (starting cash, pack prices, pack composition, foil
chance, grade odds/multipliers, box guarantees, bonuses) live in
`TradingUp/Models/Economy.swift`. Card names and values live in
`tools/generate_cards.py`.

Re‑run the [verify harness](TESTING.md#the-simulation-harness-no-xcode-needed)
after any economy change — it enforces the target difficulty curve, not just
correctness.

**Classic collectors** live in `Models/Collector.swift`. `CollectorEconomy`
controls finite request rewards, per-set trade limits, and tracked-goal capacity.
Offers are rebuilt deterministically from the catalogue and saved completion
IDs; viewing or reopening the board cannot reroll them. The pure engine owns
eligibility, distinct-card requirements, reservation allocation, previews, and
atomic exchange. `GameState` adds entitlement/reveal gates and commits collector
mutations to disk before publishing them. The UI must use those previews, not
reimplement card selection. An old save defaults the additive `collectors`
payload without resetting the run.

**Gauntlet Mode has its own knobs, kept out of `Economy.swift`.** Tier configs, the
target-Aura curve, interest rate/ceiling, stipend curve, and the `RunMods` aggregator
live in `TradingUp/Models/GauntletEconomy.swift` — which also holds `GauntletSkillTuning`,
the live seam that turns a Trainer's five-skill graph into its advantage. The Trainer roster,
skill profiles and unlock thresholds live in `TradingUp/Models/Trainer.swift`; Catalyst
effects in `Catalyst.swift`. The pack rail (which element sets start unlocked and what
unlocking a set costs in the between-rounds shop) is driven from `GauntletCore.swift`. Gauntlet has its **own**
`tools/verify` checks (§14.8) — a neutral Rookie must still clear Hard, and no Trainer may
trivialise it — so re‑run the harness after any Gauntlet balance change too, especially when
setting the skill magnitudes; trainer-unlock thresholds are meta pacing and don't affect the win-rate
assertions.

Gauntlet's simulator now distinguishes the historical **full-budget** reference from
the **automatic-clear** play cadence. Both are needed: spending all remaining rips
after reaching a target is not possible in the UI. Showcase swaps discard the
outgoing card without paying cash. The Hard target ramp is 1.61, compensating for
that lost income while preserving the existing Trainer-sidegrade guardrails; the
opening, rip budget, boss multiplier, and other tiers are unchanged.
See [Gauntlet playtesting](TESTING.md#gauntlet-decisions-and-playtesting) for the
comparison, deterministic UI fixtures, and targeted commands.

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
  `PurchaseStore.fullUnlockProductID` is the running app's bundle identifier
  plus `.fullunlock`: production remains `com.callmegreg.tradingup.fullunlock`;
  the test app's ID remains `com.callmegreg.tradingup.test.fullunlock`, but its
  automatic access skips product loading, transaction listening, purchases, and
  restores without caching a purchase.
- **`TradingUp/Store/TestBuildAccess.swift`** — immutable, fail-closed eligibility
  for the [isolated test app](#test-app-versus-production). This is not a mutable
  `FeatureFlags` switch or a runtime setting.
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

`TradingUpTest` needs no StoreKit connection, Apple account, or IAP product setup
to play the full game, including archived `Release-Test` builds in TestFlight.
Its local `TradingUpTest.storekit` catalog remains namespaced to the test app,
but is not used while automatic access is active.

To exercise the actual purchase gate, use the **production `TradingUp` scheme
on a Simulator**, with no `TU_FORCE_UNLOCK` launch override. Select **Product ▸
Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration →
`TradingUp.storekit`**, then buy in-app and use **Debug ▸ StoreKit ▸ Manage
Transactions** to refund or reset between runs. These are simulated, free
transactions, not real purchases.

For production purchase testing against Apple's sandbox, set StoreKit
Configuration to **None** locally and use a Sandbox Apple Account on a dedicated
test device. Production-identity TestFlight builds still require the production
product's sandbox entitlement; TestFlight alone never grants automatic access.
Do not install that scheme over a production app whose data you want to preserve.

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
`UIImage(named:)`; `TrainerEmblem` crops the art into a circle and grays a locked
Trainer's medallion the same way
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

### Sound effects and music

**Studio is the approved direction for every action.** The app ships 48 cues in
60 WAVs, combining physical CC0 card/wrapper/chip recordings with original
resonant, granular and harmonic layers. Six frequent gestures have three
alternate takes. `Sound.swift` names the cues; `SoundManager` preloads player
pools, rotates available takes, applies the SFX mix level to playing voices, and
keeps routine accents quieter under celebrations.

The original Classic music also accompanies the main menu and Binder; Gauntlet
has its own loop. Mode changes crossfade briefly, and returning to a mode resumes
its paused track. Music starts at **28%** of its authored mix. In **gear ->
Settings**, Music and SFX have independent live sliders and one-tap speaker mute.
Zero mutes without forgetting the previous nonzero level; raising a slider
unmutes. Haptics remain a separate toggle.

The selected, bundled choices are **Soft Circuit** (Classic, about 116 BPM /
66.20 seconds) and **Neon Dead Drop** (Gauntlet, about 148 BPM / 51.88 seconds).
Soft Circuit uses rounded electronic bass, cushioned four-on-the-floor kicks
and subdued offbeat hats, without a lead melody or build-ups. Neon's selected
arrangement retains its original octave bass and drums but removes the lead,
replies, melodic echoes and brass. Its 32-bar loop keeps the quieter middle
pocket and fuller final return. **Pocket Change** and **Velvet Current** are
background alternatives; **Sunlit Sleeves**, **Paper Lanterns**, **Quiet Resolve**
and **Northbound** remain earlier audition-only alternatives.

The four earlier scores retain their 16-bar arrangements: rounded reed/soft-brass
hooks, short plucked arpeggios, mobile bass and occasional muted tom fills, with
quieter answering phrases and a second-half variation. Their D-major/B-minor
palette shares the SFX colors; lead notes stay below G5. The explicit original
scores and locally synthesized instruments live in `tools/sound_lab/music.py`,
`tools/sound_lab/neon_dead_drop.py` and `tools/sound_lab/classic_backgrounds.py`;
no musical samples or generative-audio services are involved.

Energy comes from the writing rather than extra loudness: the authored mixes
remain quiet beds and the in-app default remains 28%. Notes, echoes and room
tails wrap across the boundary, rather than fading into silence.
The exact tempo is adjusted by less than
0.04 BPM to fit whole AAC access units. Offline FFmpeg encoding retains decoder
pre-roll in an MP4 edit list and has no trailing padding. Keep that timing
metadata intact: native `AVAudioPlayer` looping and the browser's looping
`AudioBufferSourceNode` must honor the decoded period. The two bundled files
remain 48 kHz stereo AAC-LC at 192 kbps.

`AudioPreferences` retains the existing `tradingup_sound_enabled` preference.
Music inherits that legacy preference **once**, so an existing silent game does
not suddenly start playing a score. After migration, changing SFX never changes
Music, including across launches. These preferences are separate from game saves.

Playback uses `.ambient` with `.mixWithOthers`, honoring the device silent switch.
Music pauses for backgrounding, interruptions, unplugged headphones and the
system's secondary-audio silence hint. A headphone disconnect or an interruption
without permission to resume requires an explicit music-volume/mode action.
Effects queued before a mute, interruption or background transition are
invalidated rather than sounding late on return. DEBUG-only `TU_AUDIO_DISABLED=1`
suppresses hardware playback for UI automation without changing preferences;
XCTest-hosted unit runs are also silent.

```bash
python3 tools/generate_sound_lab.py          # Render the candidate source recipes
python3 tools/generate_sfx.py                # Publish only the approved Studio bytes
python3 tools/generate_sfx.py --check         # Verify all 60 shipping files
python3 tools/generate_music.py              # Render/encode original mode music
python3 tools/generate_music.py --check
# Also recompose and compare the deterministic pre-encode PCM:
python3 tools/generate_music.py --check --render-pcm
```

The Xcode synchronized target bundles the generated WAV/M4A files automatically.
`docs/sound-lab/studio-approval.json` pins the selected Studio file hashes.
Publishing fails if those sounds changed: audition the changes and obtain
approval before deliberately running `generate_sfx.py --approve-studio`.
Neither a render nor a browser play button grants a new approval.

#### Sound direction review

The [sound lab](sound-lab/index.html) retains the complete **audition and review
workspace**. It covers 48 actions: 19 shared, 6 Classic-only
and 23 Gauntlet-only. Every action has **A / Studio** (close, tactile material
sound) and **B / Mythic** (more weight, motion and harmonic space). Six frequent
actions have three alternate takes per direction, for **120 candidate WAVs**.
The seven pre-redesign sounds are preserved in `sources/legacy/` for
level-trimmed comparisons; they are not the app's current sounds.

```bash
# Regenerate candidates from the included source material; no network or packages.
python3 tools/generate_sound_lab.py

# Serve only the soundboard, on loopback. Open http://127.0.0.1:8766.
python3 -m http.server 8766 --bind 127.0.0.1 --directory docs/sound-lab

# Validate the delivered catalogue and audio; optionally reproduce every WAV.
python3 tools/generate_sound_lab.py --check
python3 tools/generate_sound_lab.py --check --rerender
```

The local server is necessary for Web Audio decoding; opening `index.html` as a
`file://` URL displays the board but cannot audition audio. Once the files are
present, the board works without internet access. It has no analytics, CDN,
external fonts, upload endpoint, or automatic playback.

Start with the Studio signature reel, then the six listening scenes. The
original hybrid proposal remains an explicit comparison option, not the shipping
selection. Filter by mode, action family, review
state or text; compare A/B/previous, rotate alternate takes, and audition in
stereo, mono or a band-limited phone approximation. The phone filter is not a
physical-device substitute. Individual WAV downloads are under each action's
trigger details. Five original music options (two Classic, three Gauntlet) can loop under
the effects; the recommended track for each mode is bundled in the app, while
the alternates stay in the lab. Music preview volume/mute is independent, and
Stop ends both music and effects.

**Approval is explicit and per action.** The requested all-Studio selection
appears approved only where it matches the pinned file hashes. Review overrides
can choose A, B, revision, or silence, and add notes. Choices persist in that
browser's local storage, not the game save.
Export the review JSON for a durable handoff; import it to continue elsewhere.
Audio fingerprints invalidate stale decisions after a render changes, retaining
the prior choice and notes for re-audition. Nothing automatically edits Swift,
copies files into the app, or interprets an audition as approval.

The source of truth is `tools/sound_lab/`: `catalog.py` owns the action inventory,
action hooks, timing/priority notes and listening scenes; `recipes.py` owns the
layered gestures; `dsp.py` owns material processing, resonators, granular texture,
diffuse stereo rooms and mastering. `tools/generate_sound_lab.py` writes
`docs/sound-lab/catalog.js` and `docs/sound-lab/audio/`; **do not hand-edit those
outputs**. Candidate WAVs are 48 kHz, 16-bit stereo with category-based levels and
at least 3.5 dB of sample-peak headroom. A/B and alternate takes are trimmed
downward to a common per-action active-RMS level, rather than giving louder
candidates an unfair advantage. Measurements distinguish active RMS from
LUFS; they are not a loudness certification. The browser has a separate
overlap-safety compressor and starts at 45% master volume.

The material foundation is 18 provenance-tracked recordings from
[Kenney Casino Audio](https://kenney.nl/assets/casino-audio), under **CC0 1.0**.
The pack's supplied license and the source-file hashes are included in the lab.
The tonal/noise layers and compositions are original, generated locally with
Python's standard library. No sample service, model weights, stock music, or
unverified preset library is used. SFX regeneration does not need FFmpeg;
that open-source command-line tool prepares source PCM and encodes the original
music. No FFmpeg binary/library is included in the app.

To repeat that one-time preparation, download the exact archive URL recorded in
`docs/sound-lab/sources/provenance.json`, then run:

```bash
python3 tools/prepare_sound_lab_sources.py /path/to/kenney_casino-audio.zip \
  --archive-sha256 f36250766ac5bc378c13708ddf12a23a8e54a3251f8d482c7536e51b5dbafa18 \
  --download-url 'https://kenney.nl/media/pages/assets/casino-audio/2472606a04-1721639069/kenney_casino-audio.zip'
```

The importer checks the archive hash and embedded CC0 declaration, selects only
named card/wrapper/chip recordings, and records both original and prepared file
hashes. It never installs anything. This archive contains 54 audio recordings
despite the current source page's 50-asset label; only the listed 18 are used.
Source preparation used FFmpeg 9.0.1; rendering was reproduced with Python
3.14.6. Retain the prepared PCM and toolchain for byte-identical reproduction;
do not assume that different resamplers or future Python RNG implementations
will yield identical bytes.

The board's **Production options & commercial-use licensing** section records
the alternatives and their primary sources. Audacity, Surge XT and SuperCollider
are potential offline production tools, **not** proposed dependencies for the
closed-source app. Their software licenses and any imported content's licenses
must be considered separately; in particular, do not embed a GPL synthesis
engine in a proprietary target.

The Studio cues cover navigation, pack/card reveals, trading, grading,
collection progress, Showcase decisions, Catalysts, upgrades and run outcomes.
NEW/Binder/Aura/last-rip accents stay restrained: ordinary new-card glints do not
stack over foil/rarity stings; Binder improvements are heard on opening the
Binder; target/line celebrations take precedence over a small Aura tick; the
last-rip warning waits for the reveal to close. The first card still has no
extra flip, foil layers under rarity, and endings still wait for the pack
summary. `GauntletAudioSnapshot` selects one dominant transition cue and avoids
re-celebrating a round at shop entry. Models remain Foundation-only, with
**no gameplay or save-schema change**.

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
box and pack tray (P3), and the shelf list (H1) — so the gallery now doubles as
the reference for that art (`TradingUp/Views/PackWrapper.swift`).

[Classic card action layouts](mockups/ui/binder-actions.html) compares three
safer arrangements for the Collection card detail's per-copy **Grade** and
**Sell** actions: Grade-first with Sell in a menu, select-then-act with a
persistent action dock, and separate Grade/Sell intent modes. The phones are
interactive and include large-text and tap-target overlays. Open
`http://localhost:8787/ui/binder-actions.html` from the same server.
The selected native direction is the intent switch (C), implemented in
`TradingUp/Views/CardDetailView.swift` without the explanatory mode callout.

[Pack-opening cue concepts](mockups/ui/pack-opening.html) compares three
Pocket-inspired treatments using the app's original art: **Clean cut** (a crisp
strip release), **Foil ribbon** (a finger-following bend), and **Cut + lift**
(a card-stack entrance). Each browser mockup uses a light, uncluttered stage and subtle seam
cues rather than oversized handles or swipe lanes, with independent **Tap to open packs** and
**Auto open packs** preview switches, both initially off. Open
`http://localhost:8787/ui/pack-opening.html#clean` from the same server.
**Clean cut is the selected native style**, implemented in `SealedPackView`:
its only visible instruction is **“Swipe to open”**, even with either opening
preference enabled, and it ships on the existing dark, set-tinted reveal
backdrop supplied by `RevealView` and `GauntletRevealView` — the light stage
above is a browser mockup only, not the shipped look. The other two treatments
remain comparison mockups.
The app's two preferences
live in `Views/PackOpeningPreferences.swift`, outside game saves, and apply to
both Classic and Gauntlet.
