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
  **78% sell‑back rate**;
- the **sell‑back spread** works — a duplicate sells for 78% of market value, and
  buying into an already‑complete set then dumping the dupes is a **net loss** (the
  core losing risk);
- the **save format is forward‑compatible** — a payload missing newer keys (or missing
  every key) still decodes to sensible defaults, the envelope carries its schema
  version, a pre‑envelope save still loads, retired card ids are stripped rather than
  crashing, and an unreadable save is **quarantined on disk, never deleted**;
- **winning doesn't erase your collection** — the celebration shows once, and dismissing
  it leaves the finished collection browsable;
- **strategy simulations** hold the "moderate" difficulty target — reckless
  spam‑and‑dump play **busts ~53%** of the time, while thoughtful play (pace buys, grade
  valuable dupes before selling) still **wins ~69%**, a clear skill gap. The simulated
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
