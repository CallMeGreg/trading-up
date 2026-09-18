# App Store submission

Everything needed to ship Trading Up to the App Store. The field‑by‑field
listing copy lives in [app-store-listing.md](app-store-listing.md); this page
covers the artifacts you have to *produce* before you can paste that in.

- [Screenshots](#screenshots)
- [App icon](#app-icon)
- [In-app purchase promo image](#in-app-purchase-promo-image)
- [In-app purchase App Review screenshot](#in-app-purchase-app-review-screenshot)
- [Privacy manifest](#privacy-manifest)
- [Build upload](#build-upload)
- [Separate test app (TestFlight)](#separate-test-app-testflight)
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

## In-app purchase promo image

```bash
python3 tools/generate_iap_promo.py     # -> docs/app-store/iap-full-unlock-1024.png
```

App Store Connect can show a single **1024×1024** image to represent the
["Unlock the Full Collection" purchase](app-store-listing.md#7-pricing): it's the
art used when you promote the IAP on the product page, when a customer redeems an
offer code, and on win-back offers. It's shown in every region, so the art carries
no localizable marketing sentence — it says *"unlock everything"* purely visually:
a fan of the five set signature legendaries, one per element (Emberfall fire →
Umbral Reach shadow), drawn with the **same art engine that draws the cards
in-game** (`tools/generate_art.py`), the same way the app icon reuses it. So the
promo can never drift from the real artwork.

Apple's rules for this image — JPG or PNG, 1024×1024, 72 dpi, RGB, flattened (no
alpha), **no rounded corners** — are all enforced by the generator before it
writes the file; it exits non-zero if any would fail. Uploading it is optional
(the IAP works without it), but it's required to *promote* the IAP or to use offer
codes / win-back offers.

## In-app purchase App Review screenshot

```bash
tools/capture_iap_review.sh                 # -> docs/app-store/iap-review-full-collection.png
tools/capture_iap_review.sh "iPhone 16 Pro Max"   # any other 6.9" device
```

Separate from the promo image, App Store Connect **requires** a review‑only
screenshot for the purchase — "a screenshot of the In‑App Purchase that clearly
shows the item or service being offered." It's shown to App Review, never on the
store. So this is one real frame of the shipping [`PaywallView`](../TradingUp/Views/PaywallView.swift),
reached exactly the way a player reaches it: the UI test opens the app on a fresh
save and taps a paid, locked set in the shop to raise the paywall, then captures
`XCUIScreen.main.screenshot()` — the same real‑device capture the marketing
screenshots use, not an SVG mock.

The only staged detail is the price string: a UI‑test host can't load a live
StoreKit product, so a **DEBUG‑only** `TU_FAKE_PRICE` launch override renders the
real `$2.99` the App Store Connect product (and `TradingUp.storekit`) is
configured for. The override is compiled out of release builds, so shipping code
only ever shows the price StoreKit returns.

Output is **1320×2868** (a valid iPhone 6.9" screenshot spec size); the script
validates the dimensions before it finishes. Upload it to the purchase's **App
Review Screenshot** slot. Note Apple lets you *update* that screenshot later but
not remove it once uploaded.

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

The commands in this section ship the **production** `TradingUp` scheme. For a
test app that coexists with the App Store installation, use
[the separate test-app workflow below](#separate-test-app-testflight).

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

Every upload needs a build number App Store Connect has never seen for that app.
Production and test share one build-number sequence: bump `CURRENT_PROJECT_VERSION`
in all four app configurations together, above both apps' project values,
Organizer archives, and any known uploads from another Mac. `/build` creates
the matching signed production/test pair from the same source commit.
`MARKETING_VERSION` stays equal across all four configurations and only changes
when the public version number does.

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

## Separate test app (TestFlight)

`TradingUpTest` builds **Trading Up Test**, bundle ID
`com.callmegreg.tradingup.test`. It installs alongside the unchanged production
app (`com.callmegreg.tradingup`) with independent saves and preferences.
**Do not change the existing App ID or production App Store Connect record.**
Creating another TestFlight group under the production record is not enough:
those builds still have the production bundle ID and replace that installation.

### One-time Apple setup

1. In [Apple Developer → Certificates, Identifiers & Profiles → Identifiers](https://developer.apple.com/account/resources/identifiers/list),
   click **+ → App IDs → App**. Name it **Trading Up Test**, choose an
   **Explicit** bundle ID, and enter **`com.callmegreg.tradingup.test`**. Register
   it under the same team as production. In-App Purchase is enabled by default
   for an explicit App ID; no shared App Group, iCloud container, or keychain
   group is needed. Registration requires Account Holder or Admin access.
2. In **App Store Connect → Apps → + → New App**, select **iOS** and enter
   **Trading Up Test** (or another available test-only store name), your primary
   language, bundle ID **`com.callmegreg.tradingup.test`**, and a unique SKU such
   as **`trading-up-test`**. Create the record. This does **not** publish an app
   to the App Store. Leave its public App Store version unsubmitted.
3. No test IAP setup is needed to exercise paid content: the isolated test app
   [automatically unlocks the full game](#test-app-purchases), even without an
   App Store connection. The existing production product is not shared with it.
4. In Xcode, select the **`TradingUpTest` scheme**, the `TradingUp` target, and
   your existing team under **Signing & Capabilities**. Use automatic signing
   for the test configurations. Select **Any iOS Device** and choose
   **Product → Archive**. In Organizer, confirm the archive's bundle ID is
   **`com.callmegreg.tradingup.test`** before choosing **Distribute App**.
   For just you and other App Store Connect users, choose **TestFlight Internal
   Only**. That upload cannot later be submitted to the public App Store or
   external testers. If you need external testers, use **App Store Connect →
   Upload** instead, still with the test bundle ID.
5. Once processing finishes, open the **new test app's TestFlight tab**. Supply
   its test information, create an **Internal Testing** group, add the uploaded
   build, and invite your own App Store Connect user. Enable automatic
   distribution if you want later uploads delivered to the group automatically.
   Accept the invitation in TestFlight on your phone and install **Trading Up
   Test**. Keep the production app installed.

Internal testing does not require Beta App Review. External testing requires
the TestFlight review flow, including review of the first external build.
TestFlight builds expire after **90 days**, so upload a newer test build before
expiry. You do not need to submit or release this duplicate app publicly.

### Test app purchases

`Debug-Test` and archived `Release-Test` builds automatically unlock the full
game, including Gauntlet Mode, without loading products or contacting StoreKit.
No test IAP record, sandbox purchase, or Restore Purchases step is needed.
The automatic grant is never saved as a purchase entitlement and does not skip
in-game progression.

This requires both the test-only compiler condition and the exact
`com.callmegreg.tradingup.test` bundle ID. Production builds, including
production-identity TestFlight builds, keep the normal StoreKit purchase gate.
See [the isolation safeguards](DEVELOPMENT.md#test-app-versus-production).

The separate `com.callmegreg.tradingup.test.fullunlock` ID and
`TradingUpTest.storekit` catalog remain available but are not used by the
automatically unlocked test app. A local catalog does not create products in
App Store Connect. To exercise purchase, restore, or refund behavior, use
[the production scheme's local StoreKit setup on a Simulator](DEVELOPMENT.md#in-app-purchase-full-version-unlock).

### Subsequent test builds

Use **`/build`** to choose the next shared build number, commit/PR/merge the bump,
and create **both** signed production and test archives in Organizer.
`/build test` and `/build production` use the same paired workflow. Matching
version/build numbers identify matching source, beginning with **1.2.2 (42)**.
Numbers already used by either app are never reused for a new release, including
uploads from another Mac that are absent from local archives.

For manual archives, first bump `CURRENT_PROJECT_VERSION` in **all four app
configurations** to the same next number and keep `MARKETING_VERSION` aligned.
Build production and test from that same commit, using the same `TEAM_ID` as
in [Build upload](#build-upload):

```bash
xcodebuild archive -project TradingUp.xcodeproj -scheme TradingUpTest \
  -configuration Release-Test -destination "generic/platform=iOS" \
  DEVELOPMENT_TEAM="$TEAM_ID" -allowProvisioningUpdates
```

Omitting `-archivePath` puts it in Organizer. **Never override the test scheme
with `-configuration Release`**: that configuration still belongs to production.
Before upload, inspect the archive's `Info.plist`:

```bash
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleIdentifier" \
  "/path/to/TradingUpTest.xcarchive/Info.plist"
# Must print com.callmegreg.tradingup.test
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" \
  "/path/to/TradingUpTest.xcarchive/Info.plist"
# Must match the production archive's build number.
```

Apple references: [register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/),
[add an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/),
[internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/),
[sandbox testing](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/overview-of-testing-in-sandbox/),
and [create a non-consumable](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/).

## Pre-submission checklist

The full checklist — App ID, age rating, metadata, privacy policy URL, export
compliance, build upload — is at the end of
[app-store-listing.md](app-store-listing.md#9-pre-submission-checklist).
