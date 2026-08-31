# App Store Connect listing — recommended values

Everything App Store Connect asks for when publishing **Trading Up**, with a
ready-to-paste recommendation for each field. Character limits are Apple's, and
every suggested string below is already inside its limit.

Copy is written for the app as it actually ships today: free to download with a
single optional one-time in-app purchase that unlocks sets 2–5 **and Gauntlet
Mode**, no ads, no accounts, no network access for gameplay. The app now has two
ways to play — the Classic 250-card completion economy and the Gauntlet roguelite —
plus a permanent **Binder** that keeps the best copy of every card across both.

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
Now with Gauntlet Mode: pick a Trainer, rip toward a rising Aura, and build a run. Every card you keep banks into a permanent Binder that remembers your best pulls.
```

*164/170.*

### Description (4000)

```
Start with $100. Build a 250-card collection - then run the Gauntlet.

Trading Up is a collecting-and-economy game built around the best part of trading cards: tearing open a fresh pack and turning it over one card at a time. Two ways to play, and one permanent Binder tying them together.

CLASSIC MODE

Buy a pack, rip it, and find out what you got. Six cards - three commons, two uncommons, and a rare or an ultra rare - with a 1% shot at a shimmering foil on any of them. New pulls go into your collection; extras become cash, at the shop's price rather than yours.

- Rip packs. Every pack opens card by card, and the hit slot is always saved for last.
- Sell your extras. The shop buys duplicates back at 75% of market value, and that spread is the thing that will bankrupt you.
- Grade your best. Pay a fee, roll a PSA score. A 10 is a 5x payday and a 1 is a freak 10x jackpot, but anything from 2 to 7 is worth less than the card you put in.
- Cash in bonuses. Complete an evolution line for a payout; complete a whole set for a much bigger one.

Collect all 250 cards across five sets and you're a Master Collector. Fall below the price of the cheapest pack with no way left to raise it and you're tapped out.

GAUNTLET MODE

A roguelite run built from the same DNA, distilled to its strategic spine. Pick a Trainer, then push a growing Showcase past a rising Aura target - round after round, on a limited number of rips. Keep a pull to score it or sell it to fund the next; run out of rips below the bar and the run ends.

- Earn a roster of six Trainers, each an archetype with its own five-skill graph, then clear Hard with them all to reveal a hidden seventh.
- Attune Catalysts - run-long buff cards across six element lanes that stack into real builds.
- Finish evolution lines in your Showcase for huge Aura multipliers.
- Climb three difficulty tiers, each unlocked per Trainer, to a boss round and a Collection Championship finale.
- Win and choose a Foil Extended Art card - a full-bleed alternate illustration - as your prize.

THE BINDER

A permanent trophy case: one slot per Spryte, each holding the single most valuable copy you've ever owned - across every Classic run and every Gauntlet run. Where a run resets, the Binder only ever grows: pull a foil, land a PSA 10, complete a set, and the best copy is stamped in for good.

FIVE SETS, 250 CARDS

Emberfall, Tidecaller, Verdspire, Voltcrest and Umbral Reach - the world of the Sprytes. Every creature is original, with its own art, flavor text, rarity and evolution line. Later sets cost steeply more and hold far more valuable cards.

NO CATCHES

- Set 1 - Emberfall is free to play in full in Classic Mode: rip, sell, grade and chase the set bonus across all 50 cards. One optional one-time purchase unlocks the other four sets, the 250-card finish and Gauntlet Mode - the only thing you can ever buy.
- No ads, no tracking, no subscriptions.
- No real-money packs and no gambling. You never spend real money on a random pull; the only currency inside the game is fictional.
- No account, no sign-in, and no data collected. Your collection lives on your device and nowhere else.
- Plays offline, on both iPhone and iPad.

Rip the first pack and see where $100 gets you.
```

*3,249/4,000.* Deliberately avoids naming any real trading-card brand — putting
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

### What's New (4000) — v1.2.0

Shown on the product page as the "What's New in This Version" release note. Leads
with Gauntlet Mode (the headline v1.2.0 feature), then the Binder, then Classic
polish. Written since **v1.1.0**, which only scaffolded the Classic/Gauntlet/Binder
main menu — v1.2.0 is where Gauntlet Mode and the permanent Binder actually ship.

```
Gauntlet Mode is here - a brand-new roguelite way to play - plus a permanent Binder that remembers your greatest pulls forever.

GAUNTLET MODE
Rip against the clock. Pick a Trainer, then push a growing Showcase past a rising Aura target - round after round, on a limited number of pack rips. Every pull is a live keep-for-score vs. sell-for-cash decision.
- A roster of six Trainers, each an archetype with its own five-skill graph: a Ripper who tears extra packs, a Curator who hoards a huge Showcase, a grader who bends PSA luck your way, and more. Most are earned by hitting lifetime milestones; clear Hard with them all to reveal a hidden seventh.
- Catalysts - run-long buff cards across six element lanes that stack into real builds: more foils, better grades, cheaper rips, evolution-line multipliers.
- Finish an evolution line in your Showcase for a huge Aura swing; later sets pay off far harder.
- Three difficulty tiers, each unlocked per Trainer, climbing to a boss round and a Collection Championship finale.
- Win a run and choose one of three Foil Extended Art cards - a full-bleed alternate illustration - as your prize.

THE BINDER
Your permanent showcase: one slot per Spryte, each holding the single most valuable copy you've ever owned - across every Classic run and every Gauntlet run. It only ever grows, so starting a fresh run never erases your greatest hits.

CLASSIC MODE POLISH
- A redesigned Stats dashboard with This Run and All Time views.
- Cleaner pack summaries with inline Keep / Sell and grading straight from the haul.
- A new main menu tying Classic, Gauntlet and the Binder together.

Gauntlet Mode and the four paid sets are part of the one-time Full Collection unlock. Set 1 - Emberfall and Classic Mode stay free. Still no ads, no tracking, no accounts - and it all plays offline.
```

*1,822/4,000.*

### Other version fields

| Field | Recommended value |
| --- | --- |
| **Version** | `1.2.0` — must match `MARKETING_VERSION` in the project |
| **Build** | `28` — `CURRENT_PROJECT_VERSION`; bump on every upload, it can never repeat |
| **Copyright** | `2026 Greg Mohler` — year then holder, no `©` symbol (Apple adds it) |
| **What's New** | Use the v1.2.0 block above (Gauntlet Mode + Binder + Classic polish) |
| **Routing App Coverage File** | N/A |
| **Version Release** | `Manually release this version` — so you pick the launch moment after approval |
| **Phased Release for automatic updates** | On is fine for a 1.2.0 update; off if you want a hard launch |
| **App Preview video** | Optional. Screenshots carry this listing fine. |
| **Localizations** | English (U.S.) only |

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

Screenshots come from three passes (see `tools/capture_screenshots.sh`): the
Classic **playthrough** (`01`–`24`), the Classic **endgame** (`25`–`28`: win,
set-complete, all-sets-unlocked, gem-mint grade), and the new v1.2.0 **gauntlet**
pass (`30`–`39`: Binder + Gauntlet Mode). That's 38 numbered shots per device;
App Store Connect accepts a maximum of **10** per size.

**Recommended ten for v1.2.0**, in upload order. Because Gauntlet Mode and the
permanent Binder are the headline of this release, they lead alongside the
core pack-rip hook — the first three are what most people ever see:

1. `pack-reveal-rare-hit` — the rare flipping over (the hook that sells the app)
2. `gauntlet-run-building` (`38`) — a Gauntlet run mid-climb, Showcase vs. Aura target **(NEW)**
3. `binder-emberfall` (`30`) — the permanent Binder, one best copy per Spryte **(NEW)**
4. `pack-summary-all-new` — the six-card haul from a Classic rip
5. `gauntlet-trainer-select` (`33`) — choosing a Trainer and reading the skill graph **(NEW)**
6. `grading-gem-mint` — the PSA 10 jackpot, at ×5 the card's value
7. `gauntlet-share-card` (`39`) — the "Gauntlet Cleared" prize card **(NEW)**
8. `collection-grid` — the Classic collection filling in
9. `stats-run-summary` — the run stats dashboard
10. `win-master-collector` — the 250/250 win screen

This set spends four slots on what's new (Gauntlet run, Trainer select, Gauntlet
share card, Binder) and keeps six proven Classic shots. If you'd rather not lead
a returning-player update with the pack hook, swap slots 1 and 2 so Gauntlet Mode
is the first thing existing players see.

`grading-gem-mint` comes from the endgame pass, which grades rares out of the
seeded collection until a 10 rolls, so the jackpot is always in the set. The
playthrough's own `grading-psa-reveal` is whatever the run actually rolled —
usually a PSA 8 — and is the honest fallback if you'd rather not lead with the
best case.

Filenames carry a numeric prefix recording the order they were hit in that run.
The Classic **playthrough** (`01`–`24`) is unseeded, so those prefixes differ
slightly between the two device folders — match on the descriptive part, not the
number. The **endgame** (`25`–`28`) and **gauntlet** (`30`–`39`) passes both run
off a seeded save on a scripted path, so their prefixes stay put across devices.

**Picking the iPad ten.** The list above works as-is on iPad, but two notes from
reviewing the captures:

- The **pack summary** screens (`pack-summary-*`) put all six cards in a single
  row on a 13" display and leave the bottom half of the frame empty. They read
  much better on iPhone. If you want a tighter iPad set, swap
  `pack-summary-all-new` for `collection-set-complete` or `binder-umbral-reach`
  (`31`), both of which fill the frame.
- Some iPad captures are byte-identical to a neighbour, because screens that
  need scrolling on iPhone fit without it on iPad. Match on the descriptive part
  and drop exact duplicates; there are still far more than the 10 you can upload.

All were taken with the simulator status bar pinned to 9:41 / full bars /
charged, and `tools/check_screenshots.py` verifies the dimensions and confirms
there is no alpha channel.

### Curated marketing panels (the set to actually upload)

The raw captures above are the honest source, but the **committed** set that goes
on the store page is the curated one in `docs/screenshots/marketing/`, produced by
`tools/generate_marketing_shots.py`. Each panel keeps the house style of the
Classic renders in `docs/screenshots/0X_*.png` — a bold headline, a one-line
call-to-action in a lightened tint of the screen's accent colour (bright enough
to stay legible over the accent-tinted gradient), and the app gradient behind —
but
drops the phone bezel **and** the iOS status bar so the real screenshot floats
frameless as a rounded, soft-shadowed card. No pixels are painted over: the tool
embeds the untouched capture and crops the status bar with an SVG clip, so what
ships is the true UI.

Unlike the older generator (`tools/generate_screenshots.py`, which hand-draws
Classic screens in SVG and predates this release), this tool composites the actual
Gauntlet and Binder captures, so all three modes are covered with pixel-accurate
art. It reads the same gitignored capture output as the table above, so run
`tools/capture_screenshots.sh` **first**, then:

```bash
python3 tools/generate_marketing_shots.py        # all 9 scenes × both sizes
python3 tools/generate_marketing_shots.py --list  # show scenes without rendering
```

Output is 18 PNGs — the nine scenes below at **1242 × 2688** (iPhone 6.5") and
**2064 × 2752** (iPad 13"), RGB with no alpha, ready to upload as-is:

| # | Scene | Group | Headline |
| --- | --- | --- | --- |
| 01 | `pack-reveal-rare-hit` | General | Every pull is a thrill. |
| 02 | `pack-summary-new-and-dupes` | Classic | Keep it — or cash it in. |
| 03 | `grading-gem-mint` | Classic | Grade your best pulls. |
| 04 | `win-master-collector` | Classic | Collect them all. |
| 05 | `gauntlet-run-building` | Gauntlet | Run the Gauntlet. |
| 06 | `gauntlet-trainer-select` | Gauntlet | Seven Trainers, seven playstyles. |
| 07 | `gauntlet-share-card` | Gauntlet | Clear it, claim the prize. |
| 08 | `binder-emberfall` | Binder | Your best pulls, kept forever. |
| 09 | `binder-umbral-reach` | Binder | Five sets. 250 Sprytes. |

The set is ordered as a flow: a general pack-rip hook, then three Classic Mode
shots (keep-or-sell summary, grading, the win), then three Gauntlet Mode shots
(run, Trainers, prize), then the two permanent-Binder details. Each accent stays
tied to its screen's dominant colour and no two adjacent slots repeat one.
Captions live in the `SCENES` list at the top of the tool; edit them there, not on
the rendered PNGs.

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
| **Review screenshot** | `docs/app-store/iap-review-full-collection.png` — a real capture of the paywall, from `tools/capture_iap_review.sh` (required) |
| **Promotional Image** | `docs/app-store/iap-full-unlock-1024.png` (optional; needed only to promote the IAP or use offer codes / win-back offers) |
| **Cleared for Sale** | Yes |

The Product ID must match `PurchaseStore.fullUnlockProductID` in the app and the
`Products` entry in `TradingUp/TradingUp.storekit`. Because it's a
**non-consumable**, the paywall's **Restore Purchase** control — which Apple
requires for non-consumables — re-syncs it on a new device via `AppStore.sync()`.
Set 1 stays free whether or not it's ever bought, so the app is fully functional
before any purchase.

**Review notes** — paste into the purchase's *"Additional information about your
in-app purchase that could help us with our review"* field. This is scoped to the
one product; it deliberately doesn't repeat the app-level note in §6.

```
Product: "Unlock the Full Collection" (com.callmegreg.tradingup.fullunlock)
Type: Non-consumable, one-time $2.99 purchase. Not a subscription.

WHAT IT UNLOCKS
A single one-time unlock of already-bundled content. It opens the four
remaining card sets — Set 2 Tidecaller, Set 3 Verdspire, Set 4 Voltcrest and
Set 5 Umbral Reach (200 additional cards) — plus the 250-card "Master
Collector" win and the set-completion/evolution bonuses beyond Set 1. Set 1
Emberfall is free to play in full, so the app is completely functional before
any purchase. The unlock grants NO in-game currency and NO randomized pull —
it only removes the gate on existing content.

HOW TO REACH THE PURCHASE (for review)
1. Launch the app and tap "Start Collecting" on the welcome screen. No account,
   sign-in, or network connection is required — the app is fully offline.
2. You land on the Shop tab. Set 1 (free) is at the top.
3. Scroll down to any locked set (Set 2 and below). Each shows an
   "Unlock the full game" button.
4. Tap it. The purchase sheet ("Keep collecting past Emberfall") appears,
   showing the $2.99 one-time price and a "Restore purchase" control.
Completing the purchase immediately unlocks sets 2-5 and dismisses the sheet;
the previously locked sets become playable right away.

RESTORE
Because it's a non-consumable, the paywall includes a "Restore purchase"
button (StoreKit 2 AppStore.sync). It re-enables the unlock on a new device or
after reinstall with no sign-in required.

NOTES FOR COMPLIANCE
- One-time purchase only; there are no subscriptions, no ads, and no other
  real-money transactions anywhere in the app.
- The "$" amounts shown in-game are a fictional currency earned purely by
  playing. It cannot be bought with real money and cannot be cashed out.
- All 250 creatures, artwork, names, and set names are original works created
  for this app; no licensed third-party content is used.
- Pack odds are published at https://callmegreg.github.io/trading-up/support/.

An App Review screenshot of this purchase (the paywall) is attached in the
screenshot slot.
```

The optional 1024×1024 promotional image is generated by
`python3 tools/generate_iap_promo.py` — see
[APP_STORE.md](APP_STORE.md#in-app-purchase-promo-image) for what it is and the
requirements it enforces.

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
- [ ] IAP App Review screenshot uploaded — `tools/capture_iap_review.sh` writes
      `docs/app-store/iap-review-full-collection.png` (1320×2868, required)
- [ ] IAP review notes pasted into the purchase's "Additional information" field (§7)
- [ ] `python3 tools/check_icon.py` passes — 1024×1024, opaque, square (§ issue #5 step 4)
- [ ] *(optional)* IAP promo image uploaded if promoting the purchase —
      `python3 tools/generate_iap_promo.py` writes `docs/app-store/iap-full-unlock-1024.png`
- [ ] `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION` bumped
- [ ] Archive built with a Distribution signing identity and uploaded
      ([APP_STORE.md § Build upload](APP_STORE.md#build-upload))
- [ ] Build finished processing and is attached to the 1.0 version
- [ ] "Manually release this version" selected, then Submit for Review
