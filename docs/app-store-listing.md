# App Store Connect listing — recommended values

Everything App Store Connect asks for when publishing **Trading Up**, with a
ready-to-paste recommendation for each field. Character limits are Apple's, and
every suggested string below is already inside its limit.

Copy is written for the app as it actually ships today: free to download with a
single optional one-time in-app purchase that unlocks sets 2–5, no ads, no
accounts, no network access for gameplay, 250 cards across 5 sets.

---

## 1. App Information (set once, not per-version)

| Field | Recommended value | Notes |
| --- | --- | --- |
| **Name** (30) | `Trading Up TCG` | 14/30. **In use** — `Trading Up` was the first choice; the record was created as `Trading Up TCG`. The name is reserved the moment the record is created. |
| **Subtitle** (30) | `Rip packs, chase the rares` | 26/30. Indexed for search, so it earns its keywords. Alternates: `Open packs. Build the binder.` (29), `A card collecting economy sim` (29). |
| **Bundle ID** | `com.callmegreg.tradingup` | Must match `PRODUCT_BUNDLE_IDENTIFIER` in the project. Create the App ID in the Developer portal first. |
| **SKU** | `trading-up` | **In use.** Private, never shown to users, and can't be changed once the record exists. |
| **Apple ID** | `6792863289` | Assigned by App Store Connect; you'll need it for `altool` uploads and support requests. |
| **Primary Language** | `English (U.S.)` | |
| **Primary Category** | `Games` | |
| **Primary Subcategory 1** | `Card` | The most literal match — this is a trading-card game. |
| **Primary Subcategory 2** | `Simulation` | The economy/collection loop. `Casual` is the alternative if you'd rather not sit next to casino apps. |
| **Secondary Category** | *(leave blank)* | Optional and low value; `Entertainment` if you want one. |
| **Content Rights** | `No, it does not contain, show, or access third-party content` | True: all 250 creatures, names, art and flavour text are original to the Sprytes world. |
| **License Agreement** | Apple's standard EULA | No reason to supply a custom one. |
| **Custom Product Pages** | Not needed for 1.0 | |

---

## 2. Age Rating questionnaire

Apple replaced the old 4+/9+/12+/17+ tiers with **4+ / 9+ / 13+ / 16+ / 18+**,
and added questions about capabilities and in-app controls. Answers below are
grouped by topic so they map onto whichever wording you see on screen.

### Content questions

| Question | Answer |
| --- | --- |
| Cartoon or Fantasy Violence | **None** |
| Realistic Violence / Prolonged Graphic Violence | **None** |
| Sexual Content or Nudity | **None** |
| Profanity or Crude Humor | **None** |
| Alcohol, Tobacco, or Drug Use or References | **None** |
| Mature/Suggestive Themes | **None** |
| Horror/Fear Themes | **None** |
| Medical/Treatment Information | **None** |
| Violence Towards Human-Like Characters | **None** |
| **Gambling (real money)** | **No** |
| **Simulated Gambling** | **None** — see below |
| Contests | **No** |
| Unrestricted Web Access | **No** |

### Capabilities / controls questions

| Question | Answer |
| --- | --- |
| In-App Purchases | **Yes** — one non-consumable, "Unlock the full collection" (see §7) |
| Advertising | **No** |
| User-Generated Content | **No** |
| Messaging / communication between users | **No** |
| Location sharing | **No** |
| Parental controls in app | **No** |

**Expected result: 4+.**

### ⚠️ The Simulated Gambling call

Issue #5 flags this and it deserves a real answer rather than a guess.

Apple defines *Simulated Gambling* as **the ability to wager or bet**, including
poker, blackjack, slots, roulette, sports betting, and horse or dog racing.
Trading Up has none of those:

- There is **no wagering**. You buy a product (a pack) and always receive six
  cards. Nothing is staked and nothing can be lost on a roll.
- There is **no house, no payout table, no bet size, and no cash-out**.
- The only currency is fictional, is granted by the game, cannot be purchased,
  and cannot be converted to or from anything real.
- The randomness is loot-box-shaped (randomised rewards) rather than
  casino-shaped. Apple governs that under **Guideline 3.1.1**, which requires
  publishing odds *for loot boxes bought with real money*. Trading Up's only
  in-app purchase is a one-time **content unlock** — it opens sets 2–5 and
  grants no currency and no randomised pull — so nothing random is ever bought
  with real money and 3.1.1 does not bite. The pack odds are published on the
  support page regardless.

So **"None" is the honest and defensible answer**, and it matches how comparable
pack-opening collection games are rated.

If you'd rather be maximally conservative, answering "Infrequent/Mild" pushes
the rating to the 16+/18+ band, blocks the app from several territories that
restrict simulated-gambling titles, and hurts discovery — a real cost for a
question you can answer "None" to truthfully. Either way, spell the mechanic out
in the App Review notes (§6) so the reviewer isn't surprised by it.

---

## 3. Version Information (per-version, localizable)

### Promotional Text (170) — editable without a new build

```
Every pack is a fresh 1% shot at a foil. Grade your best pulls, eat the buylist spread, and see if you can finish all five sets before you go broke.
```

*148/170.*

### Description (4000)

```
Start with $100. Finish with all 250.

Trading Up is a collecting-and-economy game built around the best part of trading cards: tearing open a fresh pack and turning it over one card at a time.

Buy a pack, rip it, and find out what you got. Six cards - three commons, two uncommons, and a rare or an ultra rare - with a 1% shot at a shimmering foil on any of them. New pulls go straight into your binder. Extras become cash, at the shop's price rather than yours.

THE LOOP

- Rip packs. Every pack opens card by card, and the hit slot is always saved for last.
- Sell your extras. The shop buys duplicates back at 75% of market value, and that spread is the thing that will bankrupt you.
- Grade your best. Pay a fee, roll a PSA score. A 10 is a 5x payday and a 1 is a freak 10x jackpot, but anything from 2 to 7 is worth less than the card you put in.
- Cash in bonuses. Complete an evolution line for a payout; complete a whole set for a much bigger one.

FIVE SETS, 250 CARDS

Emberfall, Tidecaller, Verdspire, Voltcrest and Umbral Reach - the world of the Sprytes. Every creature is original, with its own art, flavor text, rarity and evolution line. Later sets cost steeply more and hold far more valuable cards, and each one unlocks as your collection grows.

WIN OR GO BROKE

Collect all 250 cards and you're a Master Collector. Fall below the price of the cheapest pack with no way left to raise it and you're tapped out. Between those two ends is a real economy - pack odds, a buylist spread, grading variance and set bonuses - that you can actually play against instead of just watching.

NO CATCHES

- Set 1 - Emberfall is free to play in full: rip, sell, grade and chase the set bonus across all 50 cards. One optional one-time purchase unlocks the other four sets and the 250-card finish - the only thing you can ever buy.
- No ads, no tracking, no subscriptions.
- No real-money packs and no gambling. You never spend real money on a random pull; the only currency inside the game is fictional.
- No account, no sign-in, and no data collected. Your collection lives on your device and nowhere else.
- Plays offline, on both iPhone and iPad.

Every card, every price and every payout is already in the app the moment you download it. Rip the first pack and see where $100 gets you.
```

*2,297/4,000.* Deliberately avoids naming any real trading-card brand — putting
a trademark in your metadata is itself a Guideline 5.2 rejection risk.

### Keywords (100)

```
tcg,ccg,card,collector,binder,booster,grading,psa,foil,pull,set,completion,economy,sim,rip,chase
```

*96/100.* Rules that this respects: comma-separated with **no spaces**, singular
forms only (Apple stems automatically), and **no repeats of words already in the
app name or subtitle** — "trading", "up", "packs" and "rares" are already
indexed from those fields, so spending keyword characters on them is wasted.

### URLs

| Field | Recommended value | Required? |
| --- | --- | --- |
| **Support URL** | `https://callmegreg.github.io/trading-up/support/` | **Yes.** Must be a live page where a user can get help. The repo's Issues page also qualifies; the Pages one answers the common questions up front and links to Issues anyway. |
| **Marketing URL** | `https://callmegreg.github.io/trading-up/` | Optional. |
| **Privacy Policy URL** | `https://callmegreg.github.io/trading-up/privacy/` | **Yes — required for every app, including ones that collect nothing.** |

All three are served from `site/` by `.github/workflows/pages.yml`. Edit the
HTML there, merge to `main`, and the deploy runs itself. The policy wording
that used to live in §5 of this file is now the page itself — `site/privacy/index.html`
is the single source of truth, so it can't drift out of sync with what's
published.

### Other version fields

| Field | Recommended value |
| --- | --- |
| **Version** | `1.0` — must match `MARKETING_VERSION` in the project |
| **Build** | `1` — `CURRENT_PROJECT_VERSION`; bump on every upload, it can never repeat |
| **Copyright** | `2026 Greg Mohler` — year then holder, no `©` symbol (Apple adds it) |
| **What's New** | Not shown for a first release; leave blank |
| **Routing App Coverage File** | N/A |
| **Version Release** | `Manually release this version` — so you pick the launch moment after approval |
| **Phased Release for automatic updates** | Off for 1.0 |
| **App Preview video** | Optional, skip for 1.0. Screenshots carry this listing fine. |
| **Localizations** | English (U.S.) only for 1.0 |

---

## 4. Screenshots

Real captures from an actual playthrough land in `docs/screenshots/appstore/`,
produced by `tools/capture_screenshots.sh`.

> **These are deliberately not in git.** They're build output — ~65 MB of PNGs
> per capture that git can't delta-compress, in a repo that's otherwise under a
> megabyte. Regenerate them when you need them; App Store Connect holds the set
> you actually submit. `.gitignore` has the full reasoning.
>
> Note the playthrough is *not* seeded, so a re-run pulls different cards. Any
> good roll works for marketing, but if you want to keep a specific set, archive
> it outside the repo (a zip on the GitHub Release is the tidy option).

**All three of these are required**, because the app ships
`TARGETED_DEVICE_FAMILY = "1,2"` (universal iPhone + iPad), and App Store
Connect keeps the 6.5" iPhone as its own upload that rejects a 6.9" image:

| Display class | Size | Folder |
| --- | --- | --- |
| iPhone 6.9" | 1320 × 2868 | `docs/screenshots/appstore/iphone-17-pro-max/` |
| iPhone 6.5" | 1242 × 2688 | `docs/screenshots/appstore/iphone-11-pro-max/` |
| iPad 13" | 2064 × 2752 | `docs/screenshots/appstore/ipad-pro-13-inch-m5/` |

The 6.5" slot also accepts 1284 × 2778 (and either size rotated to landscape),
but the capture uses 1242 × 2688 because that's what the simulator shoots
natively — don't resize a 6.9" image to fill it, the aspect ratios differ.

28 numbered screenshots are available per device; App Store Connect accepts a
maximum of **10** per size. Recommended ten, in upload order — the first three
are what most people ever see, so they lead with the hook:

1. `pack-sealed` — a sealed pack, "tap to tear it open"
2. `pack-reveal-rare-hit` — the rare flipping over
3. `pack-summary-all-new` — the six-card haul
4. `collection-grid` — the binder filling in
5. `grading-gem-mint` — the PSA 10 jackpot, at ×5 the card's value
6. `card-detail-evolution-line` — a card's detail + evolution chain
7. `shop-fresh-start` — the shop and the $100 you start with
8. `duplicate-keep-or-sell` — the keep-or-sell decision
9. `stats-run-summary` — the run stats
10. `win-master-collector` — the win screen

`grading-gem-mint` comes from the endgame pass, which grades rares out of the
seeded collection until a 10 rolls, so the jackpot is always in the set. The
playthrough's own `grading-psa-reveal` is whatever the run actually rolled —
usually a PSA 8 — and is the honest fallback if you'd rather not lead with the
best case.

Filenames carry a numeric prefix recording the order they were hit in that run,
and because each device plays its own randomised run those prefixes differ
slightly between the two folders (`11-duplicate-keep-or-sell.png` on iPhone is
`12-duplicate-keep-or-sell.png` on iPad). Match on the descriptive part.

**Picking the iPad ten.** The list above works as-is on iPad, but two notes from
reviewing the captures:

- The **pack summary** screens (`pack-summary-*`) put all six cards in a single
  row on a 13" display and leave the bottom half of the frame empty. They read
  much better on iPhone. If you want a tighter iPad set, swap
  `pack-summary-all-new` for `collection-set-complete` or
  `shop-all-sets-unlocked`, both of which fill the frame.
- Three iPad captures are byte-identical to a neighbour, because screens that
  need scrolling on iPhone fit without it on iPad:
  `02-shop-fresh-start` = `03-shop-locked-sets`,
  `22-stats-run-summary` = `23-stats-set-progress`, and
  `10-pack-summary-evolution-bonus` = `11-pack-summary-new-and-dupes` (one pack
  happened to satisfy both conditions). 26 of the 29 iPad shots are distinct,
  which is still more than the 10 you can upload.

All were taken with the simulator status bar pinned to 9:41 / full bars /
charged, and `tools/check_screenshots.py` verifies the dimensions and confirms
there is no alpha channel.

---

## 5. App Privacy

Answer the questionnaire as **"Data Not Collected"** — the app makes no network
calls of its own, has no analytics or crash SDK, no third-party frameworks, and
the only persistence is `tradingup_save.json` inside the app's own container. The
one-time in-app purchase doesn't change this: StoreKit and the App Store handle
the transaction, so the app never sees or stores any payment data.

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **No** |
| Tracking (ATT) | **No** — no `NSUserTrackingUsageDescription` needed |
| Third-party SDKs | **None** |

### Privacy manifest (`TradingUp/PrivacyInfo.xcprivacy`)

Separate from the questionnaire, and easy to miss: Apple requires a bundled
privacy manifest declaring any **required-reason API** the app calls. Ship
without one and the upload is accepted but you get an automated
**ITMS-91053 "Missing API declaration"** email, and the build can't go to review.

The app trips exactly one of those categories — `UserDefaults`, for the sound
on/off preference in `SoundManager` and the cached full-version entitlement hint
in `PurchaseStore` — declared with reason **`CA92.1`** ("access info from the app
itself"), which is all we do. The save file lives in Documents and uses no
file-timestamp APIs, and there are no third-party SDKs, so nothing else needs
declaring.

The manifest also repeats "no tracking / no data collected" in machine-readable
form, so **it has to stay in sync with the table above** — if the app ever gains
analytics or a network call, both change together.

The privacy *label* being "no data" does **not** waive the privacy *policy URL*.
The policy is published at
[`callmegreg.github.io/trading-up/privacy/`](https://callmegreg.github.io/trading-up/privacy/)
and its source is [`site/privacy/index.html`](../site/privacy/index.html) —
edit it there rather than copying the wording into this file, so the published
page and the declared label can only ever change together.

---

## 6. App Review Information

| Field | Value |
| --- | --- |
| **Sign-in required** | **No** — uncheck it; there is no account system |
| **Contact First/Last Name, Phone, Email** | Your own, reachable during review |
| **Attachment** | None needed |

**Notes** — paste this, it pre-empts every question a reviewer is likely to have:

```
Trading Up is a single-player, fully offline collecting game. No account, no
sign-in and no network connection are required; launch the app and tap "Start
Collecting" to begin.

There is one in-app purchase: a single non-consumable, "Unlock the full
collection," that opens sets 2-5 and the 250-card completion. Set 1 is free to
play in full without it. The purchase unlocks existing bundled content only - it
grants no in-game currency and no randomised pull, and there is no advertising
and no other real-money transaction. The "$" figures in the app are a fictional
in-game currency that is granted by the game, cannot be purchased, and cannot be
exchanged for anything outside the app.

Regarding the age-rating gambling questions: the app has no wagering, betting,
casino games or cash-out. Buying a pack always delivers six cards, so nothing is
staked or lost on a roll. The randomised elements are the contents of a pack and
a card's grade, both of which are randomised rewards rather than a bet, and
neither is ever bought with real money (the only real-money purchase is the
fixed content unlock above). The pack odds are published at
https://callmegreg.github.io/trading-up/support/.

All 250 creatures, their names, artwork, flavour text and set names are original
works created for this app. No third-party or licensed content is used.

To reach the end state quickly: buy and rip packs from set 1, sell the duplicates
to fund the next set, and the Collection and Stats tabs show progress at any time.
```

---

## 7. Pricing and Availability

| Field | Recommended value |
| --- | --- |
| **Price** | `Free` (Tier 0) — the app itself is free to download |
| **Availability** | All countries and regions |
| **Pre-Orders** | Off |
| **Distribution on Apple Vision Pro** | Off (untested on visionOS) |
| **Distribute on Mac (Designed for iPad)** | Optional; off for 1.0 unless you've tested it |
| **Educational discount / Volume purchase** | N/A for a free app |

### In-App Purchase — "Unlock the full collection"

One product, created under **Features → In-App Purchases**:

| Field | Recommended value |
| --- | --- |
| **Type** | Non-Consumable |
| **Reference Name** | Full Collection Unlock |
| **Product ID** | `com.callmegreg.tradingup.fullunlock` |
| **Price** | **$2.99** (Tier 3) |
| **Display Name** | Unlock the Full Collection |
| **Description** | Unlocks sets 2–5 and the 250-card Master Collector finish. A one-time purchase, not a subscription. |
| **Review screenshot** | A capture of the in-app paywall (the "Unlock the full game" sheet) |
| **Cleared for Sale** | Yes |

The Product ID must match `PurchaseStore.fullUnlockProductID` in the app and the
`Products` entry in `TradingUp/TradingUp.storekit`. Because it's a
**non-consumable**, the paywall's **Restore Purchase** control — which Apple
requires for non-consumables — re-syncs it on a new device via `AppStore.sync()`.
Set 1 stays free whether or not it's ever bought, so the app is fully functional
before any purchase.

---

## 8. Export compliance

The app uses no encryption beyond what iOS itself provides, so the answer to
*"Does your app use encryption?"* is **No**.

Rather than answering that on every single upload, the project now declares it
up front — `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is set on both the
Debug and Release configurations of the app target, which writes
`ITSAppUsesNonExemptEncryption = false` into the built `Info.plist`. App Store
Connect reads it and stops asking.

---

## 9. Pre-submission checklist

- [ ] App ID `com.callmegreg.tradingup` created in the Developer portal
- [ ] App record created in App Store Connect with the name reserved
- [ ] App Information filled in (§1) and Age Rating answered (§2)
- [ ] Version 1.0 metadata pasted in (§3)
- [ ] 10 iPhone 6.9", 10 iPhone 6.5" **and** 10 iPad 13" screenshots uploaded (§4)
- [x] Privacy policy, support and marketing pages live on GitHub Pages
      (`site/`, deployed by `.github/workflows/pages.yml`)
- [ ] App Privacy published as "Data Not Collected" in App Store Connect (§5)
- [ ] `TradingUp/PrivacyInfo.xcprivacy` present in the built bundle (§5) — without it
      the upload draws an automated ITMS-91053 rejection email
- [ ] App Review notes and contact filled in (§6)
- [ ] Price set to Free, availability confirmed (§7)
- [ ] Non-consumable `com.callmegreg.tradingup.fullunlock` created at **$2.99**,
      "Cleared for Sale," with its review screenshot, and submitted with the
      build (§7). Verify the Product ID matches `PurchaseStore.fullUnlockProductID`
- [ ] `python3 tools/check_icon.py` passes — 1024×1024, opaque, square (§ issue #5 step 4)
- [ ] `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION` bumped
- [ ] Archive built with a Distribution signing identity and uploaded
      ([APP_STORE.md § Build upload](APP_STORE.md#build-upload))
- [ ] Build finished processing and is attached to the 1.0 version
- [ ] "Manually release this version" selected, then Submit for Review
