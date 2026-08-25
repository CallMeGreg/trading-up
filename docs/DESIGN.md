# Trading Up — Game Design Document

> A trading‑card‑game‑inspired **card collecting + economy** game for iOS (SwiftUI).
> Every creature, name, set and illustration is original to this project. No real
> trading‑card brand, character, or artwork is referenced, named, or reproduced —
> deliberately, because a trademark in the app or its metadata is a
> [Guideline 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)
> rejection risk.

---

## 1. Concept

You are a card **dealer** climbing **the Circuit**. You start a **Season** with
**$100** and a folding table at a local show; you win it by clearing your way up to
the **Masters Invitational**. Buy packs, open them in an exciting reveal, and turn
cards into value faster than the bar in front of you rises: sell duplicates back to
the shop, gamble on **card grading** for value swings, chase **foils** and **ultra
rares**, and complete **evolution lines**. Each **Show** sets a **Quota** — a
net‑worth bar you must reach within a budget of pack‑opens (**Rips**) to *Make the
Cut* and advance. Clear all **8 Shows** and you win the Season; run out of room to
grow before you hit a Quota and you **bust**.

Busting is not the end of the story. Every Season — win or bust — banks **Renown**
and can trip permanent **Milestones**, and both spend into permanent upgrades at the
**Collectors' Guild** that make your *next* Season stronger. That's the roguelite:
one Season is a single run; the meta‑progression carries between runs. The full
run‑structure — Shows, Quota, Rips, the Bazaar, the three new card types, Renown, the
Guild and Milestones — is **§9, "The Circuit."**

It's a *slot‑machine‑meets‑deckbuilder* loop: the pack opening is the dopamine, the
economy and your **Trainer** engine are the strategy, and the escalating Circuit is
the run.

> **This is v2.0.0.** v1 was a single terminal *completion* game — rip until you own
> all 250 Sprytes or go broke. v2 keeps that entire economy intact but wraps it in a
> replayable roguelite. Owning all 250 cards is now the **Master Collector**
> milestone (a permanent achievement), not the win condition.

### Art direction (important — read this)
We can't commission real creature art for 250 characters, and we must not copy
anyone else's. So every Spryte is **drawn in code**: `tools/generate_art.py` builds a
flat‑vector creature and stands it on a per‑set scene. It is deterministic,
name‑aligned, scales to 250 cards for free, and can be swapped for commissioned art
later without changing the game. The app icon is built from the same code, so the two
can't drift apart.

**No card is a recolour of another.** Each of the five sets has its own *design
language* that changes the actual geometry — silhouette, limbs, head, eyes, mouth,
crest, tail and surface treatment — not just the palette:

| Set | Design language |
| --- | --- |
| 1 · Emberfall | Cooling crust over living flame: fractured faceted plates, glowing fissures, blocky basalt limbs, ember motes. |
| 2 · Tidecaller | Current and freeze: streamlined teardrops, webbed fin crests, ice facets and gill arcs, flipper limbs, bubble rings. |
| 3 · Verdspire | Canopy growth: layered lobes, bark rings, leaf collars, root limbs, blossoms and spore caps, asymmetric sprouting. |
| 4 · Voltcrest | Charge and machine: chamfered plates, bolted armour, copper coil wraps, vents, visor eyes, antenna racks, zigzag pistons. |
| 5 · Umbral Reach | Void and starlight: bodies are windows onto a starfield cut by rifts, detached limbs, star‑core eyes, orbiting shards, eclipse haloes, comet trails. |

On top of that, every *slot* (canine, golem, dragon, moth…) gets a different concept
in every set, and every evolution stage adds real structure rather than scale.
`python3 tools/generate_art.py dupes` hashes each creature's geometry with palette and
elemental accents stripped out and fails if any two of the 250 cards resolve to the
same character design. The 15 ultra legendaries are fully bespoke compositions.

An earlier draft used **procedural elemental "sigils"** — deterministic geometric
emblems generated from a card's name and type. Those have been replaced by the
creatures; `SigilView` survives only as the fallback if an art asset ever goes
missing.

**Pack art** is drawn in code too, but it is *landscape*, not creature: each set
gets its own hand-built miniature scene in `SetArt.swift` (`SetEmblem`), so a
booster is recognisable by silhouette alone before you read the name —
**Emberfall** an erupting volcano over a magma pool, **Tidecaller** small islands
under a curling swell, **Verdspire** a stand of mossy jungle trees, **Voltcrest** a bolt
splitting a thunderhead above a ridge, **Umbral Reach** an eclipse over drifting
spirits. Every scene is drawn in a 100×100 design space and scaled to the pack,
the booster box and the 58 pt shop shelf; fine detail (embers, spray, rain,
pollen) is dropped below 64 pt so the small sizes stay legible.
`tools/generate_screenshots.py` redraws the same scenes in SVG so the marketing
screenshots match the app.

---

## 2. Brand / naming

- **App / game title:** **Trading Up**
- **Creatures are called:** **Sprytes** *(decided)*
- Tagline: *"Collect all 250 Sprytes."*

Creature-brand names considered before settling on `Sprytes`:
`Mythlings` · `Critterions` · `Fablings` · `Aurabeasts` · `Kindra`

---

## 3. The 5 sets (250 cards)

Each set = **50 cards**, themed as an elemental region. Later sets cost more per pack
but hold more valuable cards.

| # | Set name       | Theme            | Pack price | Card value scale |
|---|----------------|------------------|-----------:|-----------------:|
| 1 | **Emberfall**  | Fire / magma     |       $10  | ×1 (base)        |
| 2 | **Tidecaller** | Water / ice      |       $30  | ×3               |
| 3 | **Verdspire**  | Grass / nature   |       $75  | ×7.5             |
| 4 | **Voltcrest**  | Electric / storm |      $160  | ×16              |
| 5 | **Umbral Reach**| Shadow / cosmic |      $400  | ×40              |

The price curve is deliberately **steep** — the gap between sets widens ($20 → $45 →
$85 → $240), so each later set is a genuinely bigger‑stakes push, not a gentle step up.

---

## 4. Card structure per set

Each 50‑card set is built from a mix of evolution lines and standalone creatures:

- **6 three‑stage lines** (18 cards)
- **7 two‑stage lines** (14 cards)
- **18 single creatures** (18 cards)
- **= 50 cards**

**Rarity counts per set** (same for all 5 sets):

| Rarity     | Count | Notes |
|------------|------:|-------|
| Common     |  25   | mostly evolution bases + small singles |
| Uncommon   |  15   | mid evolutions + better singles |
| Rare       |   7   | final evolutions + strong singles |
| Ultra Rare |   3   | standalone "legendary" creatures (no evolution) |

That's **15 ultra rares total** across the game — the true chase cards.

Evolutions generally climb in rarity (e.g., common → uncommon → rare). Completing a
full evolution line pays a cash bonus (see §9).

---

## 5. Naming scheme + Set 1 sample

Names are original, evocative compounds themed to the set element. Evolution lines
share a root that "grows up" across stages.

**Set 1 · Emberfall — sample names (style preview):**

Three‑stage line (the fire "starter"):
`Emberpup` → `Cinderhound` → `Pyrewolf`

Three‑stage line (magma):
`Pebblit` → `Boulderkin` → `Magmalith`

Two‑stage lines:
`Ashling` → `Cendrake` · `Flicktail` → `Emberdon`

Single creatures (commons/uncommons):
`Sootmoth` · `Coalcrab` · `Wispfox` · `Flarebud` · `Torchfin` · `Ashhare`

The three Set 1 **ultra‑rare legendaries** (the "Emberfall Wardens"):
`Ignarok` · `Solmyr` · `Emberyx`

The remaining ~230 names follow the same recipe per set theme and will be generated
after you approve the style.

---

## 6. Economy: values, packs, foils

### Value bands (base value, ungraded, non‑foil)
Bands **never overlap** — the best common is worth less than the worst uncommon, etc.
Each tier has **1–2 outliers** priced near the top of its band (the "chase" cards of
that tier); the rest sit lower. Each set's values are scaled so its packs pay back the
target EV (see **Packs** below); absolute magnitude still climbs every set, so
higher‑set cards are always worth more. Approximate resulting bands:

| Tier       | Set 1       | Set 2        | Set 3        | Set 4          | Set 5           |
|------------|-------------|--------------|--------------|----------------|-----------------|
| Common     | $0.25–0.75  | $0.72–2.01   | $1.60–4.91   | $2.95–8.59     | $5.22–14.70     |
| Uncommon   | $0.98–2.38  | $2.87–6.80   | $6.15–13.74  | $11.34–26.45   | $20.25–48.33    |
| Rare       | $3.40–6.25  | $8.24–17.51  | $18.24–40.61 | $33.45–75.92   | $58.87–133.92   |
| Ultra Rare | $9.79–22.27 | $26.59–61.85 | $63.48–123.04| $122.93–230.57 | $198.81–394.42  |

### Packs
- **6 cards per pack:** 3 commons, 2 uncommons, 1 "hit."
- The **hit slot** is a Rare 80% of the time, Ultra Rare 20%.
- A pack's contents are worth, on average, a **per‑set multiple of the pack price**.
  The payout curve **shrinks as sets get pricier** — early packs are generous, later
  packs are a bigger gamble:

  | Set             | Pack price | Target EV | Avg pack contents |
  |-----------------|-----------|-----------|-------------------|
  | 1 Emberfall     | $10       | **1.00×** | ~$10   |
  | 2 Tidecaller    | $30       | **0.90×** | ~$27   |
  | 3 Verdspire     | $75       | **0.80×** | ~$60   |
  | 4 Voltcrest     | $160      | **0.70×** | ~$112  |
  | 5 Umbral Reach  | $400      | **0.60×** | ~$240  |

  Any single pack still has **lots of variance** — a foil or a top‑tier hit blows past
  the average, a cold pack falls below it. Foils (~+2% expected) and opt‑in grading are
  upside on top of these base‑value targets.

### Sell‑back spread (the shop lowballs the buylist)
Every card has a **market value** (`currentValue`) — that's what drives your collection
value, net worth, and the "Value" readouts. But when you **sell** a duplicate, the shop
only pays **75%** of that market value (`sellbackRate = 0.75`; `sellValue = 0.75 ×
currentValue`), exactly like a real card shop buylisting below market.

This spread is the **main source of losing risk**. Because liquidation is now
net‑negative, churning packs and dumping the dupes slowly **bleeds** cash — the
more you spam, the faster you bleed. As a set fills up and packs start pulling mostly
duplicates, the endgame of each set becomes a squeeze: gamble to complete it before you
run dry. Collection value / net worth stay at **full** market value (aspirational); the
spread only bites at the moment of sale.

**Why 75% and not 65%.** The rate was 65% while booster boxes were on the shelf. Boxes
were the faucet that paid for that spread: their guaranteed ultras and foils converted
cash into set progress fast enough that a 35% haircut on every sale was survivable.
Taking boxes off the shelf (§8) removed the faucet and left the drain, and measured
win rates collapsed — thoughtful play fell from 69% to 27%, and the gap between
thoughtful and reckless play shrank from 25 points to 7, i.e. the game stopped
rewarding skill. Narrowing the spread to 75% makes a packs‑only shop work again:
thoughtful play wins **~59%**, reckless spam‑and‑dump busts **~61%**, and the skill gap
is back to **20 points**.
Sell‑back rate is the right knob because the grading threshold is
`fee / (0.5 × sellbackRate)` — a higher rate raises the payoff of grading *and* lowers
the bar for which cards are worth grading, so it compounds for players who grade
before they sell. A bigger set‑completion bonus was measured too and rejected: it
fixed winnability but paid reckless and thoughtful play equally, flattening the skill
gap to 1–2 points. In v2 the set‑completion **cash** bonus is gone entirely (it's now
the *Set Master* milestone — §9); sell‑back and grading carry the skill expression.

This is deliberately a **tighter game than the boxes era**, which sat at a 69%
thoughtful win rate. The knob is sensitive — roughly 3 points of thoughtful win rate
per point of sell‑back (0.76 → 62%, 0.77 → 66%, 0.78 → 69%) — so the harness's
winnability floor is **55%**, not 60%. Move the rate in single points and re‑run
`tools/verify` in the same change.

### Foils
- **1% chance per card**, rolled independently for all 6 cards in a pack.
- A foil is worth **×3** its base value. Stacks with grading.

---

## 7. Grading (rares & ultra rares only)

Send a rare/ultra to be graded for a random PSA grade. The grade multiplies the
card's base value:

| Grade | Multiplier | Odds |
|------:|-----------:|-----:|
| 1     | **10×**    |  1%  |
| 2     | 0.10×      |  2%  |
| 3     | 0.25×      |  3%  |
| 4     | 0.40×      |  4%  |
| 5     | 0.55×      |  5%  |
| 6     | 0.70×      | 10%  |
| 7     | 0.85×      | 15%  |
| 8     | 1.00×      | 35%  |
| 9     | 2.00×      | 15%  |
| 10    | 5.00×      | 10%  |

(Grades 3–7 are the linear ramp between grade 2 = 0.10× and grade 8 = 1.00×.)
Grade 1 is so rare it's a collector's oddity worth **10×**. Odds sum to 100%.

**Grading fee — a shallow flat ramp, decoupled from pack price:**
**S1 $2 · S2 $4 · S3 $6 · S4 $8 · S5 $10** (`Economy.gradeFees`). With the odds above
grading is *positive* EV (~1.5× on average), so a fee is what makes it a **decision**
rather than a free action. Because the fee is small and flat while card values climb
steeply, grading a **high‑set** card is cheap relative to its worth (the fee is 0.2× the
pack price in S1 but only ~0.03× in S5) — so it's attractive to grade your valuable
dupes before selling them. But the **downside scales with the card**: a low PSA grade
multiplies value *down* (grade 2 = 0.10×), so grading a pricey card that tanks is a much
bigger absolute loss. Rule of thumb: grade before selling once a card's value clears
`fee / (0.5 × sellbackRate)`. Grading valuable duplicates before dumping them is the
clearest **skill edge** thoughtful play has over careless spamming.

Foil × grade stack, e.g. a foil rare that grades PSA 10 = base **×3 ×5 = ×15**.

---

## 8. Booster box — **currently off the shelf**

> **Status:** disabled via `FeatureFlags.removeBoosterBoxes`. The shop sells packs
> only. The rules below still describe the model exactly as `GameCore` and `Economy`
> implement it — the mechanics and their tests are deliberately kept intact so the
> feature can be re‑enabled or redesigned without rebuilding it. Anything below is
> **not** part of the shipping game today. Note that removing boxes is what forced the
> sell‑back rate from 65% to 75% (§6); re‑enabling them means re‑running the balance
> checks in `tools/verify`, not just flipping the flag.

A bulk buy with **guaranteed hits** — the reason to buy is the guaranteed chase cards
and one big multi‑pack open, **not** a bulk discount.

- **Box = 12 packs**, priced at **11× the pack price**.
  - S1 $110 · S2 $330 · S3 $825 · S4 $1,760 · S5 $3,520.
- **Guarantees:** at least **3 ultra rares** and **at least 2 foils**. If a freshly
  opened box falls short, extra hits are upgraded in.
- **Why 11× and not 10×:** at 10× (12 packs for the price of 10) a box was strictly
  cheaper‑per‑pack than singles *and* came with guaranteed hits — spamming boxes was a
  risk‑free money machine. At **11×** the box is a **variance play for guaranteed
  chase cards**, priced close to buying the packs outright, so it no longer dominates.

---

## 9. The Circuit (roguelite run structure)

v2 wraps the economy above in a replayable roguelite. All of its balance lives in
`Economy.swift` (run structure) and `Boosts.swift` (the card catalog); both are
guarded by `tools/verify`.

### 9.1 A Season is a climb through Shows
A **run** is a **Season**: a climb through **`seasonShows = 8`** escalating Shows,
from a local table up to **Show 8, the Masters Invitational**.

- **Quota(show)** — a **net‑worth** bar (cash **+** full collection value) you must
  reach to *Make the Cut* and advance. It escalates geometrically:
  `quota = 110 × 1.12^(show−1)`, rounded — **110, 123, 138, 155, 173, 194, 217, 243**
  across Shows 1–8. Using *net worth* (not banked cash) is deliberate: opening packs
  is ~EV‑neutral, so ripping neither trivially clears the bar nor tanks it; you climb
  by *adding value* — grading, foils, evolution lines, extra copies — faster than the
  bar rises.
- **Rips(show)** — the pack‑opens you may make this Show (`baseRipsPerShow = 7`, plus
  Trainer/Guild bonuses). Ripping a pack spends **one Rip and its cash price**;
  selling and grading are free actions. The finite Rip budget is the clock that stops
  a Show from being ground out.
- **Cash and binder carry between Shows** within a Season — only the *bar* resets
  upward. **Making the Cut** banks Renown, keeps your surplus, and sends you to the
  **Bazaar**. Clearing **Show 8** wins the Season (the **Season Champion** milestone).
- **Bust** if you run out of ways to grow before the Quota is met — no affordable Rip
  left, nothing left worth grading or playing. The Season ends and you keep your
  Renown. **Death is progress**, not v1's terminal Game Over.

### 9.2 Three new run‑scoped card types
None are Sprytes; none are pulled from packs (the reveal stays Sprytes‑only); none
count toward the 250; none persist past the Season. They come from the **Bazaar**.
Defined in `Boosts.swift`.

**Trainers — passive relics (the engine).** Always‑on for the whole Season; you hold
a limited number (**`baseTrainerSlots = 3`**, +1 per Guild *Trainer Slot*). Effects
are plain data that stack into builds.

| Trainer | Cost | Effect | Unlocked by |
|---|--:|---|---|
| Jeweler's Loupe | $90 | Grading is free. | — |
| Bulk Buyer | $110 | Shop buys dupes at 90% (vs 75%). | — |
| Hot Hands | $120 | +2 Rips every Show. | — |
| Evolutionist | $120 | Evolution‑line bonuses doubled. | — |
| Speculator | $140 | First pack each Show is free (no cash, no Rip). | — |
| Dynamo | $100 | +1 Energy at the start of each Show. | — |
| Gilder | $100 | +5% foil chance on every card. | *Gem Holo* |
| Appraiser | $130 | Every grade rolls one tier higher. | *Ace Grader* |
| The Whale | $150 | Every pack holds one extra hit. | *Hoarder* |
| Patron of the Set | $110 | +$2 per unique card owned, paid on Make the Cut. | *Set Master* |

**Power‑Ups — active consumables (the burst).** Single‑use, played anytime, spend
**Energy**. Copies can stack.

| Power‑Up | Cost | Energy | Effect | Unlocked by |
|---|--:|:--:|---|---|
| Market Tip | $25 | 1 | Instant cash, scaled to the Show (`quota × 0.10`). | — |
| Polish | $30 | 1 | Bump a graded card up two tiers. | — |
| Holo Press | $40 | 2 | Turn a chosen card foil (×3 value). | — |
| Fast‑Track Grade | $45 | 2 | Grade a card free — guaranteed PSA 8+. | — |
| Counterfeit | $50 | 3 | Add a second copy of a card you own. | *Hoarder* |
| Pack Search | $35 | 1 | Next pack's hit is a guaranteed ultra. | *Ultra Hunter* |

**Energy — the throttle.** A small persistent pool (`startingEnergy = 2`,
`baseMaxEnergy = 6`) that Power‑Ups spend. It refills **only** from **Energy cards**
and a few Trainers (Dynamo) — never automatically — so spending it is a real choice.
Energy cards: **Energy Cell** ($30, +2 now) and **Capacitor** ($45, +1 now, +2 max).

### 9.3 The Bazaar (between Shows)
After Making the Cut, before the next Show:
1. **Draft** — pick **1 of 3** offered boosts, **free**.
2. **Bazaar** — spend cash on **3** more offers, with a **reroll** that rises in
   price within a visit (`6 + 6 × rerolls`). Spending here competes directly with
   banking net worth toward the next, higher Quota — the core invest‑vs‑save tension.

The offer pool is gated by unlocked Milestones and hides unique Trainers you already
hold; Power‑Ups and Energy can repeat.

### 9.4 Twists (per‑Show modifiers)
Some Shows carry a **Twist** that forces adaptation: **Cold Snap** (buylist −15% this
Show), **Counterfeit Scare** (no foils pull this Show), **Rush Hour** (−2 Rips but the
bar drops 15%), **Bull Market** (the bar climbs 20%). Modeled as plain data in
`Boosts.swift`; a couple are wired into the UI this release, the rest are staged.

### 9.5 Renown & Milestones (meta‑progression)
**Renown** is the meta‑currency, banked every Season and spent at the Guild. A Season
pays `showsCleared × 2` (`renownPerShowCleared`) plus **+6** for a champion
(`renownChampionBonus`), plus one‑time Milestone awards.

**Milestones** fire **once, ever**. Each banks Renown and can permanently unlock new
Trainers/Power‑Ups into the Bazaar pool, so variety compounds run over run:

| Milestone | Trigger | Renown |
|---|---|--:|
| First Cut | Make the Cut at your first Show | 1 |
| Hoarder | Hold 8 copies of a single card | 3 |
| Ace Grader | Grade three cards PSA 9+ in one run | 3 |
| Ultra Hunter | Pull 10 ultra rares (all‑time) | 3 |
| Gem Holo | Own a foil graded PSA 10 | 4 |
| Deep Run | Reach Show 5 in a single Season | 4 |
| Set Master | Complete a full 50‑card set in one run | 5 |
| Centurion | Own 100 unique cards at once | 5 |
| Season Champion | Win a Season at the Masters Invitational | 8 |
| Master Collector | Own all 250 cards at once | 20 |

### 9.6 The Collectors' Guild (permanent, Renown‑bought)
Persistent upgrades, each a capped ladder (`guildCost` is the Renown price of the
*next* level):

| Upgrade | Effect | Max level | Cost (per next level) |
|---|---|:--:|---|
| Bigger Stake | +$30 starting cash per level | 5 | `2 × n` |
| Trainer Slot | Hold one more Trainer | 3 | `5 × n` |
| Extra Rip | +1 pack‑open every Show | 4 | `4 × n` |
| Energy Cell | +1 starting & max Energy | 4 | `3 × n` |

### 9.7 Bonuses (what's left of v1's cash rewards)
- **Complete an evolution line** → cash, the run's main *non‑sale* faucet (what lets
  an early Show grow without dumping cards at the 75% buylist): a **3‑stage** line pays
  **0.5× pack price**, a **2‑stage** line **0.25× pack price** of its set (doubled by
  the *Evolutionist* Trainer). These are trimmed from v1's 2.0×/1.0× because cash no
  longer has to bankroll a whole terminal collection — only a Season's climb.
- **Complete a full set (all 50)** → **no cash.** In v2 this fires the **Set Master**
  milestone (a permanent unlock + Renown), not a payout. This is the single biggest
  economy change from v1.

---

## 10. Win / lose & stats

The win and loss conditions are now **per‑Season**, and neither is terminal for the
save — both feed the meta‑progression.

- **Bust (lose the Season):** you have no way left to grow toward the current
  **Quota** before the room closes — no affordable Rip (cash *and* Rips remaining),
  no ungraded card worth grading, no Power‑Up you have the Energy to play — and your
  net worth is still under the bar. Because it's provable, the Season‑Over screen
  appears immediately rather than making you spend down first. It shows the Show you
  reached, the Quota you fell short of, the **Renown banked**, and your haul, then
  hands you to the **Guild** to spend Renown and launch a stronger new Season.
  - **Busting is genuinely reachable.** The **sell‑back spread** (§6), the **steep
    per‑set price curve** (§3), the **removed set‑completion cash** (§9) and the
    **rising Quota** together mean careless play — spamming the cheapest set, dumping
    every dupe at 75%, buying no engine — falls behind the bar and busts. The verify
    harness asserts a real bust rate for weak play.
- **Win (the Season):** clear all **8 Shows** — Make the Cut at the **Masters
  Invitational**. A **Season Champion** celebration shows full stats (per‑set
  completion this Season, foils, best grades, peak cash, packs opened) and mints the
  1‑of‑1 collector card for the Season. Thoughtful play — pacing buys, grading
  valuable dupes before selling, and building a Trainer engine whose return outruns
  the Quota — is what carries you there; the harness asserts a healthy win rate for
  strong play.
  - **Winning is not an exit.** The celebration is shown once; dismissing it (**Keep
    Browsing**) leaves the Season intact and browsable. Starting the **New Season** is
    always a separate, confirmed action, and it preserves all meta‑progression
    (Renown, Milestones, Guild) — only the binder and cash reset for the fresh climb.
- **Owning all 250** is no longer the win — it's the **Master Collector** milestone
  (§9.5), a permanent achievement worth a large one‑time Renown bounty.

**Difficulty target: moderate, over Seasons.** A first Season with no Guild upgrades
is meant to be a real, mostly‑losable climb; permanent upgrades make later Seasons
reach deeper. Run‑structure knobs live in `Economy.swift`, the card catalog in
`Boosts.swift`; the simulations that hold this target live in `tools/verify/main.swift`
(strategy sims + economy‑knob assertions).

---

## 11. Monetization: free tier + full unlock

Trading Up ships **free**, with a single one-time **non-consumable** in-app
purchase — *Unlock the full collection* — that opens sets 2–5, the deep Circuit they
fuel, and the 250-card **Master Collector** milestone. **Set 1 · Emberfall is free to
play in full**: the entire roguelite loop — Shows, Quota, Rips, the Bazaar,
Trainers/Power-Ups/Energy, Renown, the Guild and Milestones — runs on Set-1 packs, so
a free player gets a real, satisfying multi-Show climb before the paywall is ever
reached. The purchase sells the game's *depth* (higher-value sets reach deeper Shows
and put a Season win in range), never the roguelite itself.

**What the purchase changes — and, deliberately, what it doesn't:**

- It lifts a *paywall*, not a *progression gate*. Buying into sets 2–5 requires
  the entitlement **and** the existing unique-count threshold
  (`Economy.uniquesToUnlock`), so the unlock removes the paywall but never
  *skips* the collection milestones a free player would also have to clear.
- It grants **no in-game currency and no randomised pull**. Because no real
  money ever buys a random reward, the loot-box-odds rule (App Store Guideline
  3.1.1) doesn't apply and the app stays rated 4+ — see
  [`app-store-listing.md`](app-store-listing.md).
- It touches **no balance knob**. The entitlement is a gate layered *around* the
  economy in `GameState`, not a value inside `Economy.swift`, so the tuned
  difficulty curve — and the `tools/verify` harness that guards it — is
  unchanged. Cards already owned in paid sets stay viewable in the Collection
  regardless; only *buying* packs in those sets needs the unlock.

**Where it lives.** StoreKit 2 is the source of truth (`PurchaseStore`, kept
outside `Models/` so the game logic stays Foundation-only): it verifies
`Transaction.currentEntitlements` on launch and on every transaction update, then
pushes the verified flag into `GameState.isFullVersionUnlocked`. Product id
`com.callmegreg.tradingup.fullunlock`; the size of the free slice is the single
knob `GameState.freeSetCount`. The gate is covered in both states by
`FullUnlockGateTests`.

---

## 12. Persistence
Local save (Codable → JSON in the app's Documents dir): cash, owned cards (with
foil/grade state + counts), stats, claimed bonuses, and — new in v2 — the current
**run** (Show, Quota progress, Rips, Energy, held Trainers/Power-Ups, the pending
Bazaar) and the persistent **meta** (Renown, fired Milestones, Guild upgrade levels).
No account/server needed.

The payload is wrapped in a small versioned envelope (`SaveFile`, see
`Models/Persistence.swift`), now at **version 3**, so future schema changes are
detectable rather than guessed at. The v2 additions are **purely additive** — a v1/v2
save still decodes: its collection and stats load, `run`/`meta` fall back to their
defaults, and the next launch simply starts a fresh Season around the existing binder.
Three rules keep a player's collection safe across updates:

- **Additive changes are free.** `GameCore` decodes every key independently, so a field
  added in a later build falls back to its default instead of failing the whole decode.
  (Swift's synthesized `Codable` would otherwise throw on the missing key and — with the
  old `try?` fallback — silently reset the game.)
- **Retired cards degrade, they don't crash.** If a save references a card id that's no
  longer in the catalogue, those copies are dropped on load, any bonus the player no
  longer qualifies for is un‑claimed, and the player is told what changed.
- **A bad save is never deleted.** An undecodable file is moved to
  `tradingup_save.corrupt-<timestamp>.json` and the player gets an explanation, so a bug
  or a botched migration can't quietly erase a collection.

---

## 13. Open questions for review
1. **Creature brand name** — ✅ *decided:* **Sprytes** (see §2).
2. **Art direction** — ✅ *decided:* hand-built flat-vector creatures, one per card,
   generated by `tools/generate_art.py` (see §1). Every card has its own character
   design — no recolours — enforced by `generate_art.py dupes`. The earlier
   procedural "sigil" emblems are retired; `SigilView` survives only as the fallback
   if an art asset is ever missing.
3. **Grading fee** — ✅ *decided:* flat per‑set ramp **$2/$4/$6/$8/$10** (see §7).
4. **Card look** — thumbs‑up the mockup style, or tweak colors/frames/foil?
5. Set names / theme order OK? Any names to change?
