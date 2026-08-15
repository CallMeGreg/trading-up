# App Store submission

Everything needed to ship Trading Up to the App Store. The field‑by‑field
listing copy lives in [app-store-listing.md](app-store-listing.md); this page
covers the artifacts you have to *produce* before you can paste that in.

- [Screenshots](#screenshots)
- [App icon](#app-icon)
- [Privacy manifest](#privacy-manifest)
- [Build upload](#build-upload)
- [Pre-submission checklist](#pre-submission-checklist)

---

## Screenshots

The screenshots you actually upload are captured by *playing the game*.
`TradingUpUITests/ScreenshotTests.swift` starts from a wiped app container, buys
packs with the $100 the game gives you, rips them card by card, sells the
duplicates, grades a rare and browses the collection it built — taking
full‑resolution device screenshots along the way. A second short pass seeds a
completed collection (`tools/seed_save.py`) so the win screen, a finished set and
the PSA 10 grading jackpot are covered too.

```bash
tools/capture_screenshots.sh                      # all required sizes, ~15 minutes
tools/capture_screenshots.sh "iPhone 17 Pro Max"  # just one device
tools/capture_screenshots.sh --only endgame       # refresh shots 25-28 only
```

Output lands in `docs/screenshots/appstore/<device>/` — 28 numbered PNGs per
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

### Publishing five to the README and the website

The README and [the landing page](https://callmegreg.github.io/trading-up/) show
real screenshots too, so they can't drift from the app. Five frames from the
6.5" capture get shrunk and checked in:

```bash
brew install webp                            # one-time: provides cwebp
tools/publish_screenshots.sh                 # defaults to the 6.5" capture
```

That writes `docs/screenshots/app/*.png` (621×1344, embedded by `README.md`) and
`site/screenshots/*.webp` (480 px wide, embedded by `site/index.html`) from the
same capture, in the game's own order: shop, rip, keep‑or‑sell, grade, collect.
Re‑run it after any capture that changes how those five screens look.

### Marketing renders (different thing)

`docs/screenshots/*.png` are captioned, device‑framed scenes composited as SVG
rather than captured from a running app. They're small enough to check in and
they regenerate anywhere — but they are **not** what you submit, and they're not
what the README shows.

```bash
brew install librsvg                         # one-time: provides rsvg-convert
python3 tools/generate_screenshots.py        # -> docs/screenshots (iPhone 6.5" + iPad 13")
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
preference and the cached full‑version entitlement hint), under reason `CA92.1`.

Apple bounces uploads that use such an API without declaring it — you get an
automated **ITMS-91053 "Missing API declaration"** email and the build can't go
to review. Keep the manifest in sync if the app ever grows a new dependency or
starts talking to the network; it has to agree with the App Privacy answers in
[app-store-listing.md §5](app-store-listing.md#5-app-privacy).

## Build upload

App Store Connect only accepts a **Distribution**-signed build, but you don't
have to make that certificate by hand — `-allowProvisioningUpdates` lets Xcode
issue a cloud-managed one and build the matching store provisioning profile on
demand. A Developer Program membership is what makes that work; a free Apple ID
can run the app on a device but cannot produce an App Store build.

The project doesn't hard-code `DEVELOPMENT_TEAM`, so the command line has to
supply it. Your Team ID is the 10-character code on the
[membership page](https://developer.apple.com/account); if Xcode has already
built the app for a device, a provisioning profile has it too:

```bash
TEAM_ID=$(for p in ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/*.mobileprovision; do
  security cms -D -i "$p" 2>/dev/null \
    | plutil -extract Entitlements.com\\.apple\\.developer\\.team-identifier raw - 2>/dev/null
done | head -1)
```

Don't read it off an `Apple Development` certificate — the code in parentheses
there is the individual's ID, which is a different value and will fail to sign.
(On an `Apple Distribution` certificate it *is* the Team ID.)

Every upload needs a build number App Store Connect has never seen — bump
`CURRENT_PROJECT_VERSION` first if you're re-uploading. `MARKETING_VERSION` only
changes when the public version number does.

```bash
xcodebuild archive -project TradingUp.xcodeproj -scheme TradingUp \
  -destination "generic/platform=iOS" \
  -archivePath build/TradingUp.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates

xcodebuild -exportArchive -archivePath build/TradingUp.xcarchive \
  -exportOptionsPlist tools/ExportOptions.plist \
  -exportPath build/export -allowProvisioningUpdates
```

`-archivePath` puts the archive exactly where you asked, which also means
**Xcode Organizer won't list it** — see the note below if you plan to upload
that way.

That leaves `build/export/TradingUp.ipa`. Confirm it really is a store build
before spending an upload on it — the export writes a summary next to the
`.ipa` recording which certificate signed it:

```bash
plutil -p build/export/DistributionSummary.plist | grep '"type"'
# => "Cloud Managed Apple Distribution"
```

`codesign` can't read the `.ipa` directly (it's a zip — you'll get "code object
is not signed at all", which is not a real failure). To inspect the signature
itself, unpack it first:

```bash
unzip -q build/export/TradingUp.ipa -d /tmp/ipa
codesign -dvv /tmp/ipa/Payload/TradingUp.app 2>&1 | grep Authority
# => Authority=Apple Distribution: ...
```

Checking the *archive* instead won't tell you anything useful: it's signed with
`Apple Development`, and the switch to `Apple Distribution` happens during
export.

Then send it up, whichever way suits:

- **Xcode Organizer** — Window ▸ Organizer ▸ select the archive ▸ Distribute
  App. Authenticates with the Apple ID already signed into Xcode, so there's
  nothing else to set up. Easiest for a first submission, and it skips the
  export step above.

  Organizer only scans `~/Library/Developer/Xcode/Archives/<date>/`, so an
  archive built to `-archivePath build/…` is invisible there no matter how
  cleanly it built. Drop `-archivePath` and xcodebuild writes straight to that
  folder under the name Xcode would have given it:

  ```bash
  xcodebuild archive -project TradingUp.xcodeproj -scheme TradingUp \
    -destination "generic/platform=iOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates
  ```

  To rescue one you already built to `build/`, move it across:

  ```bash
  DEST=~/Library/Developer/Xcode/Archives/$(date +%F)
  mkdir -p "$DEST"
  mv build/TradingUp.xcarchive \
    "$DEST/TradingUp $(date '+%-m-%-d-%y, %-I.%M %p').xcarchive"
  ```

  The filename is cosmetic — Organizer reads each `Info.plist` for the version
  and date it displays — but matching the convention keeps the folder tidy.

- **Command line** — needs an App Store Connect API key (Users and Access ▸
  Integrations ▸ App Store Connect API). Put the `.p8` in
  `~/.appstoreconnect/private_keys/`, then:

  ```bash
  xcrun altool --upload-app -f build/export/TradingUp.ipa -t ios \
    --apiKey "$KEY_ID" --apiIssuer "$ISSUER_ID"
  ```

- **[Transporter](https://apps.apple.com/app/transporter/id1450874784)** — drag
  the `.ipa` in. Useful when a large upload keeps failing and you want the retry
  handling.

Uploading is not submitting. The build processes for a few minutes, then has to
be attached to the 1.0 version in App Store Connect and submitted for review —
see the checklist below.

Export compliance is already answered: `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`
is set in the project, so the "does your app use encryption" prompt doesn't
appear on each upload.

## Pre-submission checklist

The full checklist — App ID, age rating, metadata, privacy policy URL, export
compliance, build upload — is at the end of
[app-store-listing.md](app-store-listing.md#9-pre-submission-checklist).
