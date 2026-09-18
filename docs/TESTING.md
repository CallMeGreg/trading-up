# Testing

Trading Up has two test layers, on purpose:

| Layer | What it is | When it runs | Needs Xcode? |
| --- | --- | --- | --- |
| `TradingUpTests/` | Fast, deterministic XCTest unit tests | Every push and PR (CI) | Yes |
| `tools/verify/main.swift` | Foundation‑only Monte Carlo simulation of the whole economy | Every push and PR (CI), and locally after any economy change | No |

The split exists because the interesting properties of this game are
*statistical* — pack expected value, grade odds, how often reckless play goes
bust. Those need tens of thousands of simulated runs, which is the wrong shape
for a unit‑test suite, so they live in a standalone harness that compiles the
pure model files with `swiftc` and runs in seconds.

---

## Unit tests

```bash
xcodebuild test \
  -project TradingUp.xcodeproj \
  -scheme TradingUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO
```

Or just press `⌘U` in Xcode.

| File | Covers |
| --- | --- |
| `AppIdentityTests.swift` | The running app's bundle ID, Home Screen name, test host, and full-unlock product ID agree for both production and the isolated test app |
| `DataIntegrityTests.swift` | The generated catalogue: 250 cards, unique names/ids, rarity splits |
| `EconomyRulesTests.swift` | The economy knobs are exactly as designed (prices, fees, sellback rate) |
| `GameplaySimulationTests.swift` | Buy/open/sell/grade flows against a seeded, reproducible RNG |
| `SaveFormatTests.swift` | Old saves decode, schema changes stay additive, retired cards are stripped |
| `SaveStoreTests.swift` | Unreadable saves are quarantined on disk, never deleted |
| `WinAndUnlockTests.swift` | Winning shows once, doesn't erase the collection; set unlocks |
| `FullUnlockGateTests.swift` | The free-tier/full-version IAP gate: Set 1 free, paid sets refuse a buy until unlocked, and the unlock never skips progression |
| `RevealFlowTests.swift` | The win/Game Over overlay waits for a pack reveal to finish; summaries omit repeated evolution banners but retain them when auto-open skips the reveal; the DEBUG fast‑travel seed |
| `PackRipMotionTests.swift` | Both horizontal opening directions, the pack-width-relative threshold, rejected/cancelled/reversed drags, and a physical-distance cut trail clamped to the wrapper rather than its padded hit target |
| `PackOpeningPreferencesTests.swift` | Both preferences default off, all four persisted combinations, independent toggles, and opting back out without changing the other preference |
| `AudioTests.swift` | Independent persisted Music/SFX channels and legacy migration; continuous-drag mute/restore; one-shot Gauntlet audio priorities; all 60 Studio effects and both selected music loops decode from the app bundle, with exact authored loop durations |

### App identity

Both `TradingUp` and `TradingUpTest` run the same XCTest suite against their own
app identity. `AppIdentityTests` checks the built app, not just project text.
The fast configuration tests additionally guard all scheme actions (especially
Archive), both StoreKit catalogs, separate test-runner IDs, version pairs, and
equivalent compiler/build settings. They require macOS's `plutil`, not a
simulator or third-party Python packages:

```bash
python3 -B -m unittest discover -s tools -p test_app_identity.py

for SCHEME in TradingUp TradingUpTest; do
  xcodebuild test -project TradingUp.xcodeproj -scheme "$SCHEME" \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:TradingUpTests/AppIdentityTests \
    -only-testing:TradingUpTests/FullUnlockGateTests \
    -only-testing:TradingUpTests/SaveStoreTests \
    -only-testing:TradingUpTests/SaveFormatTests \
    CODE_SIGNING_ALLOWED=NO
done
```

For an installation smoke test, use a disposable simulator: install both
variants, confirm `simctl get_app_container <udid> <bundle-id> data` returns
different containers, then update the test app and confirm production's
progress remains unchanged. Re-read container paths after installation: iOS can
relocate the updated app's container, so compare saved contents rather than
assuming its directory UUID stays fixed. Never run destructive save fixtures
against the App Store installation on your phone.

### Pack opening

```bash
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TradingUpTests/PackOpeningPreferencesTests \
  -only-testing:TradingUpTests/PackRipMotionTests \
  -only-testing:TradingUpTests/RevealFlowTests \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test -project TradingUp.xcodeproj -scheme TradingUpScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TradingUpUITests/PackOpeningSettingsUITests \
  CODE_SIGNING_ALLOWED=NO
```

`PackOpeningSettingsUITests` changes the real Settings switches and checks
relaunch persistence. In **both modes** it exercises wrapper taps, seam taps,
swiping with tap-to-open enabled, and rejected gestures with auto-open enabled.
The shared sealed-pack assertion requires exactly the **“Swipe to open”**
instruction and checks that the former title and helper messages stay absent,
independently of either preference.
It verifies that disabling auto-open preserves all six reveal steps, while
enabling it reaches the summary without consuming another rip, deciding cards
or Catalysts, or letting a Classic win cover the summary. It restores both
switches to off after each test and attaches a Settings screenshot.

The existing `testClassicPackRequiresSeamSwipe…` cases in `EndingFlowTests` and
`testGauntletPackRequiresSeamSwipe…` cases in `GauntletExperienceTests` cover the
default-off flow in both swipe directions. The
[browser cue concepts](mockups/ui/pack-opening.html) retain the selected Clean cut
reference alongside two alternatives;
their preview switches do not change app preferences.

### Audio

Run the focused audio and reveal/state regression tests after changing playback
or presentation hooks:

```bash
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TradingUpTests/AudioPreferencesTests \
  -only-testing:TradingUpTests/GauntletAudioFeedbackTests \
  -only-testing:TradingUpTests/AudioCatalogueTests \
  -only-testing:TradingUpTests/RevealFlowTests \
  -only-testing:TradingUpTests/GauntletStateTests \
  CODE_SIGNING_ALLOWED=NO
```

`TradingUpUITests/AudioSettingsUITests` exercises both sliders, independent
speaker mute, restoring a pre-drag level after sliding to zero, relaunch
persistence and the separate Haptics control. It attaches a Settings screenshot.
Run it on the existing `TradingUpScreenshots` scheme:

```bash
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUpScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:TradingUpUITests/AudioSettingsUITests \
  CODE_SIGNING_ALLOWED=NO
```

The UI test sets `TU_AUDIO_DISABLED=1`, and unit-test hosts suppress hardware
playback automatically in Debug. Neither changes the visible audio preferences.
For generated assets, use the offline checks below; `--rerender` also proves
every SFX candidate reproduces byte-for-byte from its sources.

```bash
python3 tools/generate_sound_lab.py --check --rerender
python3 tools/generate_sfx.py --check
python3 tools/generate_music.py --check
```

The music check verifies source/output hashes, exact decoded frame counts,
AAC priming/padding, true peaks and the loop seam. Neon's score pins the
historical no-brass arrangement before removing its 650 pluck and eight string
events, retaining exactly 908 original bass/drum events and their timings,
gains and variations. Add `--render-pcm` to recompose all eight scores and
compare their pre-encode PCM hashes as well.

Soft Circuit is the selected Classic bass/percussion loop. Pocket Change and
Velvet Current remain unselected background alternatives, and Paper Lanterns
remains available as an earlier alternate. Fast source checks cover event
retention, instrument counts, exact frame budgets, renderer routing and the
Classic app copy's byte-for-byte match to the approved Soft Circuit audition:

```bash
python3 -B -m unittest discover -s tools -p test_music.py
```

After changing a score, run `python3 tools/generate_music.py` before the asset
checks. Source-only changes are not an audio update: the generated catalog and
app audio must be regenerated together.

In the [sound lab](sound-lab/index.html), audition repeated Studio actions under
each recommended music loop, at low volume and through actual phone speakers
as well as headphones. Check the native app's silent switch, background/return,
other-app audio priority and headphone disconnect on a device. Automated
decoding and peak/loop-boundary checks do not establish subjective mix quality.

## The simulation harness (no Xcode needed)

Only the Swift toolchain from Command Line Tools is required:

```bash
swiftc -O TradingUp/Models/Card.swift \
       TradingUp/Models/Economy.swift \
       TradingUp/Models/FeatureFlags.swift \
       TradingUp/Models/GameCore.swift \
       TradingUp/Models/Persistence.swift \
       TradingUp/Models/GauntletEconomy.swift \
       TradingUp/Models/Trainer.swift \
       TradingUp/Models/Catalyst.swift \
       TradingUp/Models/GauntletCore.swift \
       TradingUp/Generated/CardData.swift \
       tools/verify/gauntlet_sim.swift \
       tools/verify/main.swift \
       -o /tmp/tu_verify && /tmp/tu_verify
```

It prints `ALL CHECKS PASSED ✅` on success, and checks, among other things:

- all 250 cards load and match the Swift model, with unique names/ids;
- each set's rarity split is 25/15/7/3 and value bands don't overlap (best of a
  tier is worth less than the worst of the next);
- **pack expected value matches each set's target curve** — 1.0× / 0.9× / 0.8× / 0.7× /
  0.6× of the pack price for sets 1–5 (Monte Carlo);
- the **PSA grade odds** match the spec exactly and sum to 100%;
- the **economy knobs** are set as designed — steep pack prices `[10,30,75,160,400]`,
  flat grade fees `[2,4,6,8,10]`, booster box at 11× pack price (still modelled even
  though the shop no longer sells one), set‑completion bonus at 15× pack price, and a
  **75% sell‑back rate**;
- the **sell‑back spread** works — a duplicate sells for 75% of market value, and
  buying into an already‑complete set then dumping the dupes is a **net loss** (the
  core losing risk);
- the **save format is forward‑compatible** — a payload missing newer keys (or missing
  every key) still decodes to sensible defaults, the envelope carries its schema
  version, a pre‑envelope save still loads, retired card ids are stripped rather than
  crashing, and an unreadable save is **quarantined on disk, never deleted**;
- **winning doesn't erase your collection** — the celebration shows once, and dismissing
  it leaves the finished collection browsable;
- **strategy simulations** hold the "moderate" difficulty target — reckless
  spam‑and‑dump play **busts ~61%** of the time, while thoughtful play (pace buys, grade
  valuable dupes before selling) still **wins ~59%**, a clear skill gap. The simulated
  shop respects `FeatureFlags.removeBoosterBoxes`, so these numbers describe the game
  as it actually ships;
- selling protects your last copy; the game‑over check is correct;
- collecting all 250 triggers the win and pays every evolution/set bonus exactly
  once.

That last one is the reason to run this harness after *any* balance change: it's
the only thing that will tell you the game is still winnable and still losable.

## CI

`.github/workflows/ci.yml` runs these checks on every push to `main` and every pull
request, on `macos-15` with Xcode 16.4:

1. **Verify harness** — checks app identity configuration, then compiles with
   `swiftc -O` and runs `tools/verify/main.swift`.
2. **Build (iOS Simulator)** and **Build test app (iOS Simulator)** — build
   `Release` and `Release-Test` respectively, with code signing off.
3. **Unit tests (iOS Simulator)** and **Unit tests test app (iOS Simulator)** —
   run the full suite in `Debug` and `Debug-Test` against a simulator picked at
   runtime by `.github/scripts/pick_simulator.py`, so the workflow doesn't break
   when GitHub rotates the installed runtimes.

The UI screenshot pass is deliberately **not** in CI — it takes ~10 minutes and
lives on its own `TradingUpScreenshots` scheme so the unit‑test run stays fast.
See [APP_STORE.md](APP_STORE.md#screenshots).

### CodeQL code scanning

`.github/workflows/codeql.yml` runs CodeQL (code scanning) on every push to
`main`, on pull requests to `main`, weekly, and on manual dispatch. It analyses
three languages: `actions` and `python` build‑free on Ubuntu, and `swift` on
`macos-15` with Xcode 16.4. The `swift` leg is a ~15-minute traced build, so it
is **skipped on pull requests** (no required status check depends on it) and runs
only on push to `main`, the weekly schedule, and manual dispatch;
`actions`/`python` are seconds each and keep running on every push and pull
request.

Swift uses **`build-mode: manual`** and the same `xcodebuild build` as the CI
build job (restricted to a single architecture), rather than CodeQL's autobuild.
The Xcode project keeps its sources in Xcode 16 synchronized folder groups
(`PBXFileSystemSynchronizedRootGroup`), so every target's `Sources` build phase
is empty; autobuild inspects those phases to choose a target, finds no Swift in
the app target, and fails with "No Swift compilation target found". Building
manually makes CodeQL trace the real `swiftc` invocations instead. This is an
**advanced setup**, so code scanning **default setup must stay disabled** — the
two are mutually exclusive, which is why all three languages are analysed here
rather than leaving `actions`/`python` on default setup.

The Swift build is the whole cost of the scan (~15 min; init and analysis are
seconds). A few things keep it down, and one tempting thing does **not** work:

- **Single architecture.** The build passes `ARCHS=arm64` (the runner's native
  simulator slice) instead of the default arm64 + x86_64. CodeQL extracts each
  source file the traced build compiles, so building both arches extracts every
  file twice into an identical database. One arch roughly halves the build.
- **No source index.** `COMPILER_INDEX_STORE_ENABLE=NO` skips Xcode's
  source-index generation, an IDE-only artifact CodeQL never reads.
- **No build‑output caching.** Caching DerivedData across runs to skip the
  rebuild would break the scan: CodeQL only extracts files the traced build
  actually recompiles, so a warm/incremental build produces an empty or
  incomplete database. The CodeQL bundle itself is already cached by the runner
  toolcache, and `dependency-caching` only caches package‑manager dependencies —
  of which this project has none.

## Fast‑travel launch hooks (DEBUG only)

Finishing a collection by hand takes ~300 packs, far too slow to exercise the
*ending* in a test. A DEBUG‑only launch hook (`DebugLaunchState`) fast‑travels
straight into a late‑game state from three launch‑environment variables:

| Variable | Effect |
| --- | --- |
| `TU_TEST_STATE=almost-won` | Seed 249 of 250 cards, every other set already claimed, cash to spare |
| `TU_TEST_MISSING=<card id>` | Which card to hold out (e.g. `S1-047`, a rare, so the pack's *hit* is the last card revealed) |
| `TU_TEST_SEED=<n>` | Pin `AppRNG` to a fixed seed so the pull is reproducible |
| `TU_TEST_CASH=<amount>` | Override the seeded bankroll |

The whole mechanism is wrapped in `#if DEBUG`, so it is **compiled out of release
builds entirely** — a shipped App Store build has no code path that can grant
cash or cards. Seeds are found the same way the verify harness reproduces runs:
SplitMix64 over the frozen `CardData`.

`TradingUpUITests/EndingFlowTests` uses all four to play the exact bug scenario
deterministically: launch at 49 of 50, rip the pack whose hit completes the set,
and assert the win celebration only appears *after* the pack summary — never
cutting in over the reveal — and that the finished set then reads 50 of 50. It
runs on the `TradingUpScreenshots` scheme (Debug config) and doubles as the pass
`tools/capture_ending.sh` screen‑records for a demo video:

```bash
tools/capture_ending.sh                 # iPhone 17 Pro -> build/ending.mov
tools/capture_ending.sh "iPhone 17 Pro Max" build/ending.mov
```

## Component galleries (DEBUG only)

Some views are gated behind randomness or a full run — a Catalyst offer appears on
a chance roll, and the Gauntlet share card only renders after a win — which makes
them awkward to screenshot or eyeball. A second DEBUG‑only hook, `DebugGallery`,
renders one such component on its own from a launch‑environment variable:

| Variable | Renders |
| --- | --- |
| `TU_TEST_GALLERY=catalyst` | A single `CatalystCardView` on the mode backdrop |
| `TU_TEST_GALLERY=share` | The `GauntletShareCard` with a sample showcase, prize and attuned Catalysts |
| `TU_TEST_GALLERY=showcase` | A Showcase grid of graded, multi‑stage cards — the PSA grade slab in the artwork corner beside the header stage pips |
| `TU_TEST_GALLERY=extended` | Graded, multi‑stage **Extended‑Art** cards, where the grade slab drops to just under the stage pips it would otherwise cover |

Like `DebugLaunchState` it is wrapped in `#if DEBUG`, so it is compiled out of
release builds; `ContentView` swaps in `DebugGalleryView` when the variable is set
and otherwise shows the normal menu.

`TradingUpUITests/UIImprovementScreenshots` drives these hooks (plus
`TU_FORCE_UNLOCK` to open Gauntlet and `TU_TEST_STATE=almost-won` for a pack full
of duplicates) to capture one PNG per screen a UI change touched — the Classic
pack summary's inline keep/sell, the Gauntlet run HUD, the Continue / New Run
prompts, and the two galleries — attaching each frame to the result bundle:

```bash
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUpScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TradingUpUITests/UIImprovementScreenshots \
  -resultBundlePath /tmp/tu_ui.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool export attachments --path /tmp/tu_ui.xcresult \
  --output-path /tmp/tu_ui_shots
```

Like the other UI tests it runs on the `TradingUpScreenshots` scheme and is **not**
part of the CI test plan.

## Gauntlet decisions and playtesting

`GauntletDecisionTests.swift` covers exact whole-Showcase swap previews, broken and
completed lines, duplicate stages, foil/grade/Trainer/Catalyst modifiers, grading
affordability, discard-only swaps with no cash or cash-milestone gain, and stable
round earnings after a purchase. `EvolutionPipTests` distinguishes Showcase-owned,
pending-pack, and missing stages independently of the current-card gold outline
across every set, including held duplicates, unrelated lines, single cards, and
the matching VoiceOver descriptions. It also guards unchanged pip contexts outside
the Gauntlet summary. `EvolutionPipRenderTests` checks the real half-fill and
focus-outline rendering, including actual-size thumbnails in all five set colors.
`ShareImageRenderTests` also checks that win sharing contains exactly one rendered
image and no companion text or URL.
`GauntletDecisionStateTests` covers the last-pack recovery window, successful
and unsuccessful grades, deferred result dismissal, explicit loss, mid-grade
relaunch, Catalyst-first decisions, persisted discard swaps, duplicate decisions,
phase gates, and pip updates after keep/sell/swap decisions.

Run those alongside the existing Gauntlet regressions:

```bash
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:TradingUpTests/GauntletCoreTests \
  -only-testing:TradingUpTests/GauntletStateTests \
  -only-testing:TradingUpTests/GauntletMetaTests \
  -only-testing:TradingUpTests/GauntletProgressStoreTests \
  -only-testing:TradingUpTests/GauntletDecisionTests \
  -only-testing:TradingUpTests/GauntletDecisionStateTests \
  -only-testing:TradingUpTests/EvolutionPipTests \
  -only-testing:TradingUpTests/EvolutionPipRenderTests \
  -only-testing:TradingUpTests/ShareImageRenderTests \
  CODE_SIGNING_ALLOWED=NO
```

### Playable DEBUG fixtures

`DebugGauntletScenario` seeds **real resume snapshots**, not mock screens. It runs
once at application launch only when `TU_TEST_GAUNTLET` is explicitly set; Home /
Continue afterward uses normal persistence. It is entirely absent from Release
builds. Use a disposable Simulator: an explicit fixture replaces that install's
Gauntlet run and meta progress (not its Binder).

| Launch environment | Starting point |
| --- | --- |
| `TU_TEST_GAUNTLET=fresh` | Fresh Trainer selection, with the primer already seen |
| `TU_TEST_GAUNTLET=swap` | Full Medium Showcase with a complete and a partial evolution line |
| `TU_TEST_GAUNTLET=graded-swap` | The same Showcase with PSA 3, PSA 9, and foil keepers for current-price comparisons |
| `TU_TEST_GAUNTLET=catalyst` | A pending Bloom offer plus five Sprytes, for Catalyst-first summary decisions |
| `TU_TEST_GAUNTLET=shop` | Round-one payout with enough cash to choose a pack unlock or slots |
| `TU_TEST_GAUNTLET=last-pack` | Last pending card, zero rips, and an ungraded keeper below target |
| `TU_TEST_SEED=0` | The last-pack fixture's next grade is PSA 9, rescuing the round |
| `TU_TEST_SEED=7` | The same grade is PSA 7, demonstrating a genuine failed gamble |

`GauntletExperienceTests` plays a fresh Easy run from Trainer selection through all
five rounds and the Binder reward, rather than seeding a win. Its other cases
exercise swap cancellation/confirmation, line completion, stable purchase history,
unaffordable actions, save/resume and process relaunch, both grading outcomes,
the shared grading-result popup, declining the last chance, and large text. It
also follows the remaining-rip counter from the round through the sealed pack,
individual reveals, and summary, and verifies that removed controls/copy stay absent.
It checks action-only next-round labels, preserved earned-interest history,
swap-series progress and buff/debuff-aware current prices, Catalyst-first placement,
pending-linemate pip updates after keeping or selling, and opening/dismissing the
image-only system share sheet after a real win.
The share activity's Copy action must produce an image with no companion string;
`EndingFlowTests` checks that same contract for a Classic win.
Each relevant screen is attached as a real Simulator screenshot. The review pass
uses iPhone 17, iPhone SE (3rd generation),
and iPad mini (A17 Pro); the full-run case only needs to run once.

```bash
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUpScreenshots \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:TradingUpUITests/GauntletExperienceTests \
  -resultBundlePath /tmp/tu_gauntlet.xcresult CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool export attachments --path /tmp/tu_gauntlet.xcresult \
  --output-path /tmp/tu_gauntlet_screenshots
```

### Balance: reference versus playable cadence

The existing verify command also runs a paired **automatic-clear** comparison.
`GauntletCadence.fullBudget` retains the old reference and all its difficulty and
Trainer guardrails. `.automatic` settles every pull before testing the target,
banks unused rips, permits ordinary grading between packs, and offers normal-fee
last-chance grades before a loss. `.automaticWithoutLastChance` is the same policy
with the old premature-loss behavior. Optimized play tries affordable keepers when
out of rips; careless play still only tries its top keeper. Every run must resolve,
and enabling the optional recovery must not reduce that policy's prior wins.
Partial-line valuations sum in line-ID order so floating-point ties cannot change
a seeded run merely because a Dictionary iterates in a different order.
The harness is compiled with `-O` locally and in CI to keep the additional 4,800
automatic-clear runs practical; its explicit `check` calls remain active.

The earlier September 2026 review found that the full-budget reference overstated success
in the shipping flow. Using the neutral Trainer and 400 seeds per cell starting at
`0x6A17`, the automatic-clear **optimized-policy** results were:

| Tier | Original flow, original economy | Last-chance fix only | Before discard swaps, Hard ramp 1.64 |
| --- | --- | --- | --- |
| Easy | 99.2% | 99.8% | 99.8% |
| Medium | 69.2% | 75.2% | 75.2% |
| Hard | 26.0% | 36.0% | 41.2% |

That review's automatic-clear careless-policy rates were 97.2% / 3.8% / 3.2%, so higher
tiers still punished that policy's cash hoarding and weak curation. Its
historical reference checks also passed: at 200 trials its optimized rates were
99% / 84% / 69%, versus careless 98% / 40% / 20%. These are **heuristic-policy
estimates**, not human win probabilities, proof of optimal play, or interchangeable
measurements. In particular, that automatic-clear Hard estimate remained below
the historical reference's 45% floor; that older floor was calibrated against a
different cadence. Future balance work should improve and calibrate the live
policies across Trainers rather than silently relaxing the existing reference checks.

**Discard-only swap follow-up.** With the same seeds, policies, and trial counts,
removing swap sale proceeds changes the optimized automatic-clear estimates:

| Tier | Sold swaps, Hard ramp 1.64 | Discard swaps, Hard ramp 1.64 | Discard swaps, Hard ramp 1.61 |
| --- | --- | --- | --- |
| Easy | 99.8% | 99.8% | 99.8% |
| Medium | 75.2% | 65.0% | 65.0% |
| Hard | 41.2% | 34.5% | 44.5% |

The initial discard-only run failed the existing Trainer-sidegrade ceiling: at
120 seeds starting at `0x2C7`, Ash's Hard reference win rate exceeded the Rookie's
by about 41 points. The Hard ramp adjustment to **1.61** brings that gap back to
35 points without changing any harness assertions, Trainer skills, drop/grade
odds, rip budgets, or the other tiers' constants. The final full-budget reference
rates (200 seeds) are 98% / 74% / 67% optimized versus 98% / 21% / 16% careless;
the automatic-clear careless rates are 96.0% / 2.0% / 2.0%. All existing guardrails
remain in force. These are heuristic-policy estimates, not human win probabilities;
Medium's lower cash income is a real consequence of discarding rather than selling.
