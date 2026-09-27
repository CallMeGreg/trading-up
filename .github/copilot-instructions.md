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
- **Core Classic balance knobs live in `TradingUp/Models/Economy.swift`**: starting
  cash, pack prices and composition, foil chance, grade odds and multipliers,
  bonuses.
- `TradingUp/Models/Collector.swift` owns Classic request
  rewards, trade bundles, and per-set deal limits. Gauntlet keeps its independent
  sell-back rate in `GauntletEconomy.swift`; do not move it with Classic tuning.
- `TradingUp/Views/` is SwiftUI only. Don't put game rules here.
- `TradingUp/Models/FeatureFlags.swift` holds build‑time switches. Flags are
  covered by tests in **both** states; keep it that way when adding one.

## Testing

Run the smallest thing that covers the change.

```bash
# Unit tests
xcodebuild test -project TradingUp.xcodeproj -scheme TradingUp \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO

# Simulation harness — no Xcode needed
swiftc -O TradingUp/Models/Card.swift TradingUp/Models/Economy.swift \
  TradingUp/Models/Collector.swift \
  TradingUp/Models/FeatureFlags.swift TradingUp/Models/GameCore.swift \
  TradingUp/Models/Persistence.swift TradingUp/Models/GauntletEconomy.swift \
  TradingUp/Models/Trainer.swift TradingUp/Models/Catalyst.swift \
  TradingUp/Models/GauntletCore.swift TradingUp/Generated/CardData.swift \
  tools/verify/classic_sim.swift tools/verify/gauntlet_sim.swift \
  tools/verify/main.swift -o /tmp/tu_verify && /tmp/tu_verify
```

**Any economy change must re‑run the verify harness.** It enforces the intended
difficulty curve statistically, not just correctness — unit tests won't catch a
balance regression. CI runs both on every push and PR.

## Pull requests and releases

**Every PR, including documentation-only PRs, must increment the shared app
build number.** Follow [the build skill](skills/build/SKILL.md): choose a number
above both apps' project settings, local Organizer archives, and any higher
known App Store Connect uploads. Change `CURRENT_PROJECT_VERSION` in all four
**app-target** configurations together; leave XCTest/UI-test targets and
`MARKETING_VERSION` unchanged unless a version change was requested.
Include the bump in the work's existing PR, not a separate release PR. Recheck
before merging in case another PR consumed that number; do not bump on every
push or again merely because the PR merged.

**Every merged PR must produce a new matched pair of signed archives and upload
the test app to TestFlight.** Once GitHub confirms the merge, follow the build
skill's archive/upload steps from a clean worktree matching the merged source:
`TradingUp` / `Release` and `TradingUpTest` / `Release-Test`, using the PR's
shared version/build. Keep both archives in Xcode Organizer, but upload **only**
`com.callmegreg.tradingup.test` **through Organizer's Distribute App → App Store
Connect flow** for internal TestFlight, not the **TestFlight Internal Only**
option. Uploading to App Store Connect does not authorize a public release.
Preserve the committed build number and verify that the
same local archive shows Organizer's successful distribution status/checkmark.
An accepted upload without that Organizer record is not the desired completed
workflow. Do not silently substitute `xcodebuild -exportArchive`, `altool`,
Transporter, or another headless uploader. If UI automation is unavailable,
leave the verified local archives ready and report that the Organizer upload
needs to be completed.
Never upload production or submit either app for public release unless explicitly
requested. Verify Apple's upload acceptance; distinguish processing from tester
availability, and report any signing, authentication, or upload blocker.
If resuming after a merge, continue the same release rather than creating another
bump/PR; retry failed steps without duplicating a successful archive or upload.
Do not re-upload a build already accepted by Apple just to obtain a checkmark,
or edit archive metadata to fabricate one; apply the Organizer flow to the next
new build instead.
These are agent workflow instructions, not a hosted CI distribution service:
post-merge work needs this Mac's Xcode and Apple account access.

## Saves

`Persistence.swift` uses a versioned save envelope. Schema changes must stay
**additive** and old saves must keep decoding; unreadable saves are quarantined
on disk, never deleted. `SaveFormatTests` and `SaveStoreTests` guard this.

## The website

`site/` is published to GitHub Pages by `.github/workflows/pages.yml` from that
folder only, so it needs its own copies of any asset — it can't reference files
from `docs/`. Like the README, it is player‑facing copy.
