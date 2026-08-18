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
| `EconomyRulesTests.swift` | The economy knobs are exactly as designed (prices, fees, sellback rate) |
| `GameplaySimulationTests.swift` | Buy/open/sell/grade flows against a seeded, reproducible RNG |
| `SaveFormatTests.swift` | Old saves decode, schema changes stay additive, retired cards are stripped |
| `SaveStoreTests.swift` | Unreadable saves are quarantined on disk, never deleted |
| `WinAndUnlockTests.swift` | Winning shows once, doesn't erase the collection; set unlocks |
| `FullUnlockGateTests.swift` | The free-tier/full-version IAP gate: Set 1 free, paid sets refuse a buy until unlocked, and the unlock never skips progression |
| `RevealFlowTests.swift` | The win/Game Over overlay waits for a pack reveal to finish; the DEBUG fast‑travel seed |

## The simulation harness (no Xcode needed)

Only the Swift toolchain from Command Line Tools is required:

```bash
swiftc TradingUp/Models/Card.swift \
       TradingUp/Models/Economy.swift \
       TradingUp/Models/FeatureFlags.swift \
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
