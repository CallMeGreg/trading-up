# App Store submission

Everything needed to ship Trading Up to the App Store. The field‑by‑field
listing copy lives in [app-store-listing.md](app-store-listing.md); this page
covers the artifacts you have to *produce* before you can paste that in.

- [Screenshots](#screenshots)
- [App icon](#app-icon)
- [Privacy manifest](#privacy-manifest)
- [Pre-submission checklist](#pre-submission-checklist)

---

## Screenshots

The screenshots you actually upload are captured by *playing the game*.
`TradingUpUITests/ScreenshotTests.swift` starts from a wiped app container, buys
packs with the $100 the game gives you, rips them card by card, sells the
duplicates, grades a rare and browses the collection it built — taking
full‑resolution device screenshots along the way. A second short pass seeds a
completed collection (`tools/seed_save.py`) so the win screen, a finished set and
a booster box are covered too.

```bash
tools/capture_screenshots.sh                      # all required sizes, ~15 minutes
tools/capture_screenshots.sh "iPhone 17 Pro Max"  # just one device
tools/capture_screenshots.sh --only endgame       # refresh shots 25-29 only
```

Output lands in `docs/screenshots/appstore/<device>/` — 29 numbered PNGs per
device at **1320×2868** (iPhone 6.9"), **1242×2688** (iPhone 6.5") and
**2064×2752** (iPad 13"). All three are required: the target ships
`TARGETED_DEVICE_FAMILY = "1,2"`, so App Store Connect asks for an iPad set as
well as an iPhone set, and it keeps the 6.5" iPhone as a separate upload that
rejects a 6.9" image. `tools/check_screenshots.py <dir>` re‑validates sizes and
alpha channels, and the capture script runs it for you.

Xcode ships simulators for the 6.9" iPhone and 13" iPad but not the 6.5" one, so
the script creates that simulator on first run.

Those PNGs are **gitignored on purpose** — they're build output, and ~65 MB a
capture would dwarf the rest of the repo. Regenerate on demand; the set you
submit lives in App Store Connect. `--only playthrough|endgame` re‑shoots just
one pass, which is handy when a change only affects part of the game.

The capture uses the `TradingUpScreenshots` scheme, deliberately separate from
the `TradingUp` scheme so CI's unit‑test run stays fast.

See [app-store-listing.md §4](app-store-listing.md#4-screenshots) for which ten
to upload and in what order.

### Marketing renders (different thing)

`docs/screenshots/*.png` are captioned, device‑framed scenes composited as SVG
rather than captured from a running app. They're small enough to check in, they
regenerate anywhere, and the README uses them — but they are **not** what you
submit.

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_screenshots.py        # -> docs/screenshots (6.9" + 6.5")
```

## App icon

```bash
python3 tools/generate_icon.py
python3 tools/check_icon.py
```

`check_icon.py` is what proves the icon is submittable: exactly 1024×1024, 8‑bit,
**no alpha channel**, and full‑bleed to the edges (iOS applies the rounded‑corner
mask itself, so a baked‑in one shows up as dark wedges). Details in
[DEVELOPMENT.md](DEVELOPMENT.md#app-icon).

## Privacy manifest

`TradingUp/PrivacyInfo.xcprivacy` declares no tracking and no data collection,
plus the one required‑reason API the app touches: `UserDefaults` (the mute
preference), under reason `CA92.1`.

Apple bounces uploads that use such an API without declaring it — you get an
automated **ITMS-91053 "Missing API declaration"** email and the build can't go
to review. Keep the manifest in sync if the app ever grows a new dependency or
starts talking to the network; it has to agree with the App Privacy answers in
[app-store-listing.md §5](app-store-listing.md#5-app-privacy).

## Pre-submission checklist

The full checklist — App ID, age rating, metadata, privacy policy URL, export
compliance, build upload — is at the end of
[app-store-listing.md](app-store-listing.md#9-pre-submission-checklist).
