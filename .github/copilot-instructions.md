# Copilot instructions — Trading Up

Trading Up is a card‑collecting economy game for iPhone and iPad, written in
SwiftUI with **zero third‑party dependencies**. Open `TradingUp.xcodeproj`.

## Audience: who each document is written for

**The root [`README.md`](../README.md) is the app's front door and is written for
players, not developers.** Treat it as store‑page copy that happens to live in a
repo: what the game is, how it plays, what it looks like, and the promises it
makes (no ads, no IAP, no tracking, works offline).

- **Do not** add build steps, `xcodebuild` invocations, requirements tables,
  project layout, contributor workflow, architecture notes or tooling docs to the
  root README. That content belongs in `docs/`.
- The one developer‑facing part is the **Documentation** table near the bottom,
  which exists purely to route contributors into `docs/`. Link out; don't inline.
- Anything a player wouldn't care about is a signal it's in the wrong file.

Everything for developers lives in `docs/`:

| Doc | Scope |
| --- | --- |
| `docs/DEVELOPMENT.md` | Requirements, build and run, project layout, balance knobs, feature flags, regenerating content |
| `docs/DESIGN.md` | Game design: the world, sets, economy and grading tables, win/lose rules |
| `docs/TESTING.md` | The XCTest suite, the simulation harness, what CI runs |
| `docs/APP_STORE.md` | Submission artifacts: screenshots, icon checks, privacy manifest |
| `docs/app-store-listing.md` | Ready‑to‑paste App Store Connect metadata |

When you change behaviour, update the doc that owns that area — and only update
the README if the change is something a *player* would notice.

## Generated files — edit the generator, not the output

These are written by tooling and will be overwritten. Never hand‑edit them:

| Generated | Regenerate with |
| --- | --- |
| `TradingUp/Generated/CardData.swift`, `data/cards.json` | `python3 tools/generate_cards.py` |
| `TradingUp/Assets.xcassets/CardArt/` | `python3 tools/generate_art.py` (needs `rsvg-convert`) |
| `TradingUp/Assets.xcassets/AppIcon.appiconset/` | `python3 tools/generate_icon.py` (needs `rsvg-convert`) |
| `TradingUp/Assets.xcassets/TrainerArt/`, `docs/mockups/trainers/` | `python3 tools/generate_trainer_art.py` (needs `rsvg-convert`) |
| `docs/app-store/iap-full-unlock-1024.png` | `python3 tools/generate_iap_promo.py` (needs `rsvg-convert`) |
| `docs/app-store/iap-review-full-collection.png` | `tools/capture_iap_review.sh` (needs a Simulator) |
| `TradingUp/Audio/SFX/` | `python3 tools/generate_sfx.py` |
| `docs/screenshots/app/`, `site/screenshots/` | `tools/capture_screenshots.sh` then `tools/publish_screenshots.sh` |

Every generator in `tools/` is stdlib‑only Python 3 — no pip installs. The art,
icon and marketing renders shell out to `rsvg-convert` (`brew install librsvg`).

## Where the game lives

- `TradingUp/Models/` is pure, testable game logic (Foundation only, no SwiftUI).
  Keep it that way — the simulation harness compiles these files directly.
- **Almost all balance knobs live in `TradingUp/Models/Economy.swift`**: starting
  cash, pack prices and composition, foil chance, grade odds and multipliers,
  bonuses.
- `TradingUp/Views/` is SwiftUI only. Don't put game rules here.
- `TradingUp/Models/FeatureFlags.swift` holds build‑time switches. Flags are
  covered by tests in **both** states; keep it that way when adding one.

## Testing

Run the smallest thing that covers the change.

```bash
# Unit tests
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Simulation harness — no Xcode needed, runs in seconds
swiftc TradingUp/Models/Card.swift TradingUp/Models/Economy.swift \
  TradingUp/Models/FeatureFlags.swift TradingUp/Models/GameCore.swift \
  TradingUp/Models/Persistence.swift TradingUp/Models/GauntletEconomy.swift \
  TradingUp/Models/Trainer.swift TradingUp/Models/Catalyst.swift \
  TradingUp/Models/GauntletCore.swift TradingUp/Generated/CardData.swift \
  tools/verify/gauntlet_sim.swift tools/verify/main.swift -o /tmp/tu_verify && /tmp/tu_verify
```

**Any economy change must re‑run the verify harness.** It enforces the intended
difficulty curve statistically, not just correctness — unit tests won't catch a
balance regression. CI runs both on every push and PR.

## Saves

`Persistence.swift` uses a versioned save envelope. Schema changes must stay
**additive** and old saves must keep decoding; unreadable saves are quarantined
on disk, never deleted. `SaveFormatTests` and `SaveStoreTests` guard this.

## The website

`site/` is published to GitHub Pages by `.github/workflows/pages.yml` from that
folder only, so it needs its own copies of any asset — it can't reference files
from `docs/`. Like the README, it is player‑facing copy.
