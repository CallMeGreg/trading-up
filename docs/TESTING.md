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
| `DataIntegrityTests.swift` | The generated catalogue: 250 cards, unique names/ids, rarity splits |
| `EconomyRulesTests.swift` | The economy knobs are exactly as designed (prices, fees, sellback rate, evolution-line bonus — and no set-completion cash) |
| `GameplaySimulationTests.swift` | Buy/open/sell/grade flows and the Circuit bust thresholds against a seeded, reproducible RNG; milestones fire |
| `SaveFormatTests.swift` | Old saves decode, schema changes stay additive (v3 run + meta), retired cards are stripped |
| `SaveStoreTests.swift` | Unreadable saves are quarantined on disk, never deleted |
| `WinAndUnlockTests.swift` | Winning a Season (clearing the Championship) shows once and preserves meta-progression; set unlocks |
| `RunSignatureTests.swift` | The 1-of-1 Season-champion collector card is deterministic from the run |
| `FullUnlockGateTests.swift` | The free-tier/full-version IAP gate: Set 1 free, paid sets refuse a buy until unlocked, and the unlock never skips progression |
| `RevealFlowTests.swift` | The win/bust overlay waits for a pack reveal to finish; the DEBUG fast‑travel seed |

## The simulation harness (no Xcode needed)

Only the Swift toolchain from Command Line Tools is required:

```bash
swiftc TradingUp/Models/Card.swift \
       TradingUp/Models/Economy.swift \
       TradingUp/Models/FeatureFlags.swift \
       TradingUp/Models/Boosts.swift \
       TradingUp/Models/GameCore.swift \
       TradingUp/Models/Persistence.swift \
       TradingUp/Generated/CardData.swift \
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
  though the shop no longer sells one), evolution-line bonuses (and **no
  set‑completion cash** — that's the Set Master milestone now), and a **75%
  sell‑back rate**;
- the **sell‑back spread** works — a duplicate sells for 75% of market value, and
  buying into an already‑complete set then dumping the dupes is a **net loss** (the
  core losing risk);
- the **Circuit run structure** is sound — a Season is 8 Shows, the net-worth
  **Quota curve rises every Show**, rips/energy/Guild-upgrade ladders are well-formed,
  and a bigger Guild *Stake* means a bigger opening bankroll;
- the **boost catalog has integrity** — every Trainer/Power-Up/Energy id is unique
  and round-trips through the catalog, and milestone-gated boosts point at real
  milestones (so there's always something to unlock);
- the **milestone conditions** fire on exactly the right game states (first Cut,
  full set, 8 copies, PSA-10 foil, three PSA-9s, Show 5, Championship, 10 ultras,
  100 uniques, all 250);
- the **run loop** is correct — clearing a Show banks Renown, holdings at the bar
  make the Cut, clearing the final Show wins the Season and fires **Season Champion**,
  and a stalled Show with no affordable rip / gradeable dupe / playable Power-Up is a
  **bust** (`isGameOver` mirrors `isBust`);
- the **save format is forward‑compatible** — a payload missing newer keys (or missing
  every key) still decodes to sensible defaults, the envelope carries its schema
  version (now **v3**), a **v1 save migrates** without losing cash/collection, a
  pre‑envelope save still loads, retired card ids are stripped rather than crashing,
  and an unreadable (or newer-schema) save is **quarantined on disk, never deleted**;
- **winning a Season doesn't erase your collection** — the Season Champion celebration
  shows once, and dismissing it leaves the binder browsable;
- **strategy simulations over whole Seasons** hold the difficulty target — careless
  spam‑and‑dump play stalls at **~1.2 Shows** and **busts the opening Show ~44%** of
  the time, while thoughtful play (keep + grade valuable dupes) climbs **~2.5 Shows**
  and reaches the Championship on a no‑upgrade Season only **~12%** of the time — a
  clear skill gap, with permanent Guild upgrades being what make deep runs reliable.
  The simulated shop respects `FeatureFlags.removeBoosterBoxes`, so these numbers
  describe the game as it actually ships;
- selling protects your last copy; the bust check is correct;
- **owning all 250 no longer wins** — it fires the Master Collector milestone — and
  every evolution line pays its bonus exactly once while sets pay no cash.

That last cluster is the reason to run this harness after *any* balance change to
`Economy.swift` or `Boosts.swift`: it's the only thing that will tell you the game is
still winnable and still losable **over Seasons**.

## CI

`.github/workflows/ci.yml` runs three jobs on every push to `main` and every pull
request, on `macos-15` with Xcode 16.4:

1. **Verify harness** — compiles and runs `tools/verify/main.swift`.
2. **Build (iOS Simulator)** — `xcodebuild build` with code signing off.
3. **Unit tests (iOS Simulator)** — `xcodebuild test` against a simulator picked
   at runtime by `.github/scripts/pick_simulator.py`, so the workflow doesn't
   break when GitHub rotates the installed runtimes.

The UI screenshot pass is deliberately **not** in CI — it takes ~10 minutes and
lives on its own `TradingUpScreenshots` scheme so the unit‑test run stays fast.
See [APP_STORE.md](APP_STORE.md#screenshots).

### CodeQL code scanning

`.github/workflows/codeql.yml` runs CodeQL (code scanning) on every push to
`main`, every pull request to `main`, and weekly. It analyses three languages:
`actions` and `python` build‑free on Ubuntu, and `swift` on `macos-15` with
Xcode 16.4.

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

The Swift build is the whole cost of the scan (~20 min; init and analysis are
seconds). Two things keep it down, and one tempting thing does **not** work:

- **Single architecture.** The build passes `ARCHS=arm64` (the runner's native
  simulator slice) instead of the default arm64 + x86_64. CodeQL extracts each
  source file the traced build compiles, so building both arches extracts every
  file twice into an identical database. One arch roughly halves the build.
- **No build‑output caching.** Caching DerivedData across runs to skip the
  rebuild would break the scan: CodeQL only extracts files the traced build
  actually recompiles, so a warm/incremental build produces an empty or
  incomplete database. The CodeQL bundle itself is already cached by the runner
  toolcache, and `dependency-caching` only caches package‑manager dependencies —
  of which this project has none.

## Fast‑travel launch hooks (DEBUG only)

Climbing eight Shows (or finishing a 250‑card collection) by hand is far too slow to
exercise an *ending* in a test. A DEBUG‑only launch hook (`DebugLaunchState`)
fast‑travels straight into a late‑game state from a few launch‑environment variables:

| Variable | Effect |
| --- | --- |
| `TU_TEST_STATE=almost-champion` | Seed a Season sitting at **Show 8 (the Masters Invitational)** with net worth already past the Quota, so the shop opens with the **Make the Cut** CTA and a single tap wins the Season |
| `TU_TEST_STATE=almost-won` | Seed 249 of 250 cards, every other set already claimed, cash to spare (one card from the Master Collector milestone) |
| `TU_TEST_MISSING=<card id>` | Which card to hold out (e.g. `S1-047`, a rare, so the pack's *hit* is the last card revealed) |
| `TU_TEST_SEED=<n>` | Pin `AppRNG` to a fixed seed so the pull is reproducible |
| `TU_TEST_CASH=<amount>` | Override the seeded bankroll |

The whole mechanism is wrapped in `#if DEBUG`, so it is **compiled out of release
builds entirely** — a shipped App Store build has no code path that can grant
cash or cards. Seeds are found the same way the verify harness reproduces runs:
SplitMix64 over the frozen `CardData`.

`TradingUpUITests/EndingFlowTests` uses `almost-champion` to play the **Season win**
end‑to‑end: launch at the Championship, tap **Make the Cut**, assert the **Season
Champion** celebration takes the screen, then dismiss it with **Keep Browsing** and
land back in the shop. It runs on the `TradingUpScreenshots` scheme (Debug config)
and doubles as the pass `tools/capture_ending.sh` screen‑records for a demo video:

```bash
tools/capture_ending.sh                 # iPhone 17 Pro -> build/ending.mov
tools/capture_ending.sh "iPhone 17 Pro Max" build/ending.mov
```
