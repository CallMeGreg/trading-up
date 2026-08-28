# Trading Up — Game Design Document

> A trading‑card‑game‑inspired **card collecting + economy** game for iOS (SwiftUI).
> Every creature, name, set and illustration is original to this project. No real
> trading‑card brand, character, or artwork is referenced, named, or reproduced —
> deliberately, because a trademark in the app or its metadata is a
> [Guideline 5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)
> rejection risk.

---

## 1. Concept

You are a card collector with **$100** starting cash. Buy packs, open them in an
exciting reveal, and try to **collect all 250 creatures** across 5 sets. Sell
duplicates back to the shop, gamble on **card grading** for value swings, and chase
**foils** and **ultra rares**. Run out of money with nothing left worth selling and
you lose. Complete the collection and you win.

It's a *slot‑machine‑meets‑collection* loop: the pack opening is the dopamine, the
economy is the strategy, the 250‑card completion is the goal.

As of **v2.0.0** this loop is **Classic Mode**, reached from a new main menu that also
hosts **Gauntlet Mode** and the **Binder** — see §13.

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
before they sell. A bigger set‑completion bonus was measured too and rejected: it fixes
winnability but pays reckless and thoughtful play equally, flattening the skill gap to
1–2 points.

This is deliberately a **tighter game than the boxes era**, which sat at a 69%
thoughtful win rate. The knob is sensitive — roughly 3 points of thoughtful win rate
per point of sell‑back (0.76 → 62%, 0.77 → 66%, 0.78 → 69%) — so the harness's
winnability floor is **55%**, not 60%. Move the rate in single points and re‑run
`tools/verify` in the same change.

### Foils
- **1% chance per card**, rolled independently for all 6 cards in a pack.
- A foil is worth **×3** its base value. Stacks with grading.

---

## 7. Grading (any card)

Send any card to be graded for a random PSA grade. The grade multiplies the
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

## 9. Bonuses

- **Complete an evolution line** → cash bonus:
  - 2‑stage line = **1.0× pack price** of its set · 3‑stage line = **2.0× pack price**.
- **Complete a full set (all 50)** → cash bonus = **15× that set's pack price**
  (S1 $150 … S5 $4,800) — a meaningful reward that helps toward the next set without
  fully bankrolling infinite spending (it was 30×, which snowballed too hard).

---

## 10. Win / lose & stats

- **Lose:** cash drops **below the cheapest pack price ($10)** and **no amount of
  selling could get you back to one**. You can never sell your **last copy** of a
  unique card (you'd lose collection progress), so what's left to raise is your
  duplicates — sold at the buylist price, or graded first when even the luckiest
  roll would more than cover its own fee. Once that optimistic total still falls
  short of $10, the run is provably finished and the loss screen appears
  immediately, rather than making you sell out card-by-card first. A loss screen
  shows: cards collected per set, and total unique cards.
  - **This is now genuinely reachable.** The **sell‑back spread** (§6), the **steep
    per‑set price curve** (§3), and the **trimmed set‑completion bonus** (§9) together
    mean careless play — spamming the cheapest set and dumping every dupe at 75% — can
    bleed you dry before a set completes. In simulation that reckless loop **busts ~61%**
    of the time.
- **Win:** collect all **250** unique creatures. A winner's screen shows full stats:
  per‑set completion, foils, best grades, peak cash, packs opened, etc.
  - Thoughtful play — pacing your buys, keeping a cash cushion, and **grading valuable
    dupes before selling** — still **wins ~59%** of the time. The gap between the two is
    the point: skill, not grinding, is what carries you through.
  - **Winning is not an exit.** The celebration is shown once; dismissing it keeps the
    completed collection intact and browsable. Starting over is always a separate,
    confirmed action — the reward for finishing shouldn't be losing what you finished.

**Difficulty target: moderate.** Thoughtful play usually wins; careless play can
bankrupt you. Balance knobs all live in `Economy.swift`; the simulations that hold this
target live in `tools/verify/main.swift` (strategy sims + economy‑knob assertions).

---

## 11. Monetization: free tier + full unlock

Trading Up ships **free**, with a single one-time **non-consumable** in-app
purchase — *Unlock the full collection* — that opens sets 2–5, the 250-card
Master Collector win, and **Gauntlet Mode** (§13). **Set 1 · Emberfall is free to
play in full**: the whole
loop (rip, sell, grade, evolution-line bonuses, the set-completion payout) plays
out across its 50 cards before the paywall is ever reached.

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
foil/grade state + counts), stats, and claimed bonuses. No account/server needed for v1.

The payload is wrapped in a small versioned envelope (`SaveFile`, see
`Models/Persistence.swift`) so future schema changes are detectable rather than guessed
at. Three rules keep a player's collection safe across updates:

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

The **Binder** (§13) is persisted the same way but in its **own** file
(`tradingup_binder.json`, `Models/BinderStore.swift`), deliberately separate from the
run save because it has to outlive a **New Game**. It follows the same envelope rules —
additive‑only, lenient decode, never destroy on a read failure, and refuse to overwrite
a newer‑schema file.

---

## 13. Modes & the Binder (v2.0.0)

v2.0.0 puts a **main menu** in front of the game (`Views/MainMenuView.swift`), with a
slow "parade" of Sprytes drifting behind it. It routes to:

- **Classic Mode** — the original loop above (buy → rip → sell → grade → complete 250).
  Unchanged; it just lives behind the menu now (`Views/ClassicModeView.swift`), and the
  way back out is the **Main Menu** button on the Settings tab.
- **Gauntlet Mode** — a roguelite mode, gated behind the full‑game unlock and **specced +
  shipped per §14**. `Views/GauntletView.swift` now hosts the real run loop (its Trainer
  select, pack rail, shop, and reward flow live in `Views/Gauntlet*Views.swift` over the
  `Models/Gauntlet*` engine), not a placeholder.
- **Binder** — see below.

The one‑time **full‑game unlock** (§11) now unlocks *both* the four paid sets **and**
Gauntlet Mode. Set 1 · Emberfall and Classic Mode stay free, and a locked Gauntlet tap
routes to the same paywall.

### The Binder
A permanent trophy case: one slot per Spryte, each holding the single **most valuable
copy ever owned** of it — across every Classic run and Gauntlet Mode.

Where a Classic run is a roguelike that empties on **New Game**, the Binder only ever
grows: pull a foil, land a PSA 10, complete a set, and the best copy of each Spryte is
stamped in for good. It's fed the current collection after every acquisition and keeps
the running per‑card maximum, so selling a card or starting a fresh run never erases the
record. Pure model in `Models/Binder.swift`; persisted separately from the run (§12).
For scaffolding the Binder screen (`Views/BinderView.swift`) is display‑only: a per‑set
grid of the best copy of each Spryte, with headline "filled / total" and total‑value
roll‑ups.

---

## 14. Gauntlet Mode

> **Status:** the **core mode now ships** — the run loop, rounds/rips/Aura engine,
> Catalysts, the Trainer roster with meta-unlocks, the three tiers, interest banking, the
> pack rail, and the choose-1-of-3 Extended-Art reward are all live in
> `Models/Gauntlet*` and `Views/Gauntlet*`, balance-verified by the Gauntlet `tools/verify`
> harness (§14.8) and covered by XCTest. What remains design-only are the §14.7 "other
> levers" (bounties, event nodes, the booster-box splurge, damaged/sealed pulls). The
> per-Trainer level scaling (§14.3) now ships too. Gauntlet is gated behind the full-game
> unlock (§11).

Gauntlet distils Classic to its strategic spine. Classic is, underneath, one tension:
**value vs. liquidity** under a completion deadline — a card is worth more kept than sold
(the 75% sell-back spread, §6), but you need cash to keep ripping, and grading (§7) is the
skill lever that wrings extra value from the same pulls. Gauntlet concentrates that
tension into a short, escalating, **engine-building run**: you rip toward a rising
Aura target, and every pull is a live **keep-for-score vs. sell-for-fuel** decision.
Same DNA as Classic, roguelite pacing.

### 14.1 The run: rounds, rips, a rising Aura

A run is a sequence of **rounds**. Each round sets a **Target Aura** — a collection
value you must reach — and gives you a fixed number of
**rips** (pack opens) to reach it.
Clear it and you advance through a **shop** to a higher target; miss it and the run ends.
The Showcase (the cards you keep) **carries across rounds and compounds**, so it's an
engine you grow, not a fresh hand each round. It's a **per-run** construct — like a Classic
run's collection the Showcase itself is discarded when the run ends. What outlives it is the
**Binder**: the run's Extended-Art reward (§14.6) *and* the value-best of every card the run
pulled or graded, folded into the all-time collection along the way.

Three resources, each generating a *different* decision:

| Resource | Scope | Decision it forces |
| --- | --- | --- |
| **Rips** | Per round; a hard count that resets each round | Tempo — is *this* rip worth spending? The "last rip, need a hit" crunch. |
| **Aura** | Value of the cards you **keep**; must clear the round's Target | Which pulls to bank; whether to gamble-grade a keeper to clear the line. |
| **Cash** | Across the run; earned by selling (at the spread), spent in the **shop** between rounds | Sell now for shop power later, vs. keep for this round's target. |

Because the Showcase carries over, **selling a kept card is a real sacrifice** — it drops
Aura you'll still need next round. That knife-edge keeps the loop strategic instead
of a slot machine. Running out of rips below target with no legal play ends the run — the
same "provably stuck" logic as Classic's `isGameOver` (§10), but per-round and escalating,
so optimisation becomes *mandatory* on the higher tiers rather than optional.

(The two constraints — a hard **rip count** and **cash** — are deliberate: the rip count
creates tempo pressure, cash creates the economy. A single blended currency was considered
and rejected as mushier — it collapses two distinct decisions into one.)

**Banking.** Cash you *don't* spend in the shop earns **20% interest** between rounds — a
compounding return on what you've banked — so saving toward a pricier set's packs or a
booster-box splurge (§14.7) is a live alternative to spending now. It's a deliberate third
force: the Aura engine pushes you to *keep* cards, the sell-back spread punishes
*selling* them, and interest rewards *not spending* the cash you do raise. Three pulls
working against each other is where the optimisation lives — and the knob (rate + ceiling)
is tuned by the Gauntlet harness (§14.8) alongside targets and rip counts.

**Targets & faucets.** A round's Target is a **cumulative** bar: it measures your whole
standing Showcase's Aura, not just what you added this round, so *selling a keeper
drops you back toward the line* — the sacrifice that keeps selling honest. Bars rise each
round and spike on the Hard **boss** round (§14.5). The round **auto-clears the moment the
Target is met** — no "end round" button to press — firing a confetti cue and, once the
current pack is resolved, advancing to the shop. Cash for the shop comes from three
faucets: **selling** pulls mid-round (at the spread), a **round-clear payout that
scales with how far you overshoot** the Target — so pushing *past* the bar, not stopping
exactly on it, is the keep-heavy player's way to fund Catalysts — and **leftover rips**,
each banked at **$5 × the cleared round number** so unused tempo isn't simply wasted.
Per-tier counts (rounds, rips, starting slots) live in §14.5.

### 14.2 The Aura engine (where the strategy lives)

For a run to reward **builds** rather than luck, kept cards must **multiply each other**.
Gauntlet extends Classic's value formula — `Economy.value(base × foil × grade)` — into a
scoring engine you assemble mid-run:

> **aura(card) = base × foil × grade , then × _evolution-line bonus_ × _run multipliers_**

The two new terms are what a build is *made of*:

- **evolution-line bonus** — completing a full evolution line held in the Showcase (every
  stage of a `lineId` present) lifts *that line's* whole Aura by a bonus factor
  (`baseEvoLineBonus`, plus any Trainer/Catalyst boost). Partial lines pay nothing, so the
  build goal is to *finish chains*, not just hoard high-value singles — a knapsack pull
  against limited slots. (This replaced the earlier same-element "synergy" multiplier: a
  completion bonus is RNG-gated on pulling a line's whole chain, which rewards planning over
  passively stacking one element.)
- **run multipliers** — global effects from Catalysts (§14.4) and your Trainer (§14.3).

This yields replayable identities — line-completionist, foil-chaser, grade-gambler,
value-singles — the reason to replay. Surface the build-up on screen
(base → ×foil → ×grade → ×line bonus) so players *learn* the engine; it doubles as the
reveal dopamine.

**Keep-slots.** The Showcase holds a **run-long capacity** of *N* cards (a starting count
per tier, §14.5, raisable in the shop). Once it's full, keeping a new card means **swapping
one out** — the knapsack question "is this rare better than my current worst keeper?" —
instead of "keep everything good." Because widening the Showcase competes with Catalysts for
shop cash, *how big to build it* is itself a decision, and it's the main lever the
difficulty tiers squeeze.

### 14.3 Trainers — the meta progression

A **Trainer** is the run's starting **archetype** (like a Classic character), chosen
before the run. Instead of a hand-written perk, each Trainer is defined by a **Madden-style
five-skill graph** — a dot ladder of **1…5 pips** on each of five axes — and those pips *are*
its identity: they derive the run advantage, so a Trainer's card and its mechanics can never
drift apart. **3 is the neutral baseline** (a flat-3 profile is exactly `RunMods.none`); above
3 is a specialty, below 3 a real weakness. The model is **symmetric**, so a spiky Trainer
trades strength in its lane for weakness elsewhere — a *sidegrade*, never a strict upgrade.

The five skills and what each drives (`TrainerSkillAxis` → `GauntletSkillTuning`):

| Skill | Icon | Governs |
| --- | --- | --- |
| **Energy** | `bolt.fill` | Pack rips per round (a bonus-rip chance) |
| **Aura** | `sparkles` | Default Aura every card scores (global multiplier) |
| **Selling** | `dollarsign.circle.fill` | Cash back when you sell — sell-back, round stipend, seed cash |
| **Grading** | `checkmark.seal.fill` | Grading luck and fees |
| **Inventory** | `square.grid.2x2.fill` | Showcase + Catalyst capacity |

**Only the Rookie is free; the other five are earned** by hitting a lifetime Gauntlet
milestone (tracked in `GauntletProgress.stats`), so meta progression is about *earning the
roster*, and each milestone is phrased to teach the lane it unlocks. Profiles are roughly
balanced on a **weighted** budget — Energy and Aura are worth more per pip than
Selling/Grading/Inventory, so a strong pip there is paid for with a bigger cut elsewhere. The
shipped roster (`Models/Trainer.swift`), as `Energy / Aura / Selling / Grading / Inventory`:

| Trainer | Leans | E | A | S | G | I | Unlocked by |
| --- | --- | :-: | :-: | :-: | :-: | :-: | --- |
| **Rookie** | — (neutral) | 3 | 3 | 3 | 3 | 3 | Free starter |
| **Ripper** | Energy | 5 | 2 | 2 | 1 | 4 | Rip **100** packs across runs |
| **Curator** | Inventory/Aura | 2 | 4 | 1 | 3 | 5 | Build a **12-card** Showcase in one run |
| **Farmer** | Aura | 2 | 5 | 2 | 2 | 3 | Reach a round Aura of **500** |
| **Grader** | Grading | 2 | 3 | 2 | 5 | 3 | Grade **100** cards across runs |
| **Merchant** | Selling | 3 | 2 | 5 | 2 | 3 | Hold **$250** cash at once in a run |

Locked cards show the requirement and a live progress bar (e.g. "60 / 100 packs ripped"),
and the just-unlocked Trainers are celebrated on the selection screen after a run banks its
stats. Thresholds are meta-pacing knobs, **not** a difficulty lever — the harness still
proves a neutral Rookie clears Hard, so the roster stays gravy rather than a gate.

**Skill → advantage, and why the numbers are pending.** `GauntletSkillTuning` (in
`GauntletEconomy.swift`, the balance seam) turns a profile into a `RunMods` symmetrically:
each pip above 3 grants a per-pip bonus on that skill's lever, each pip below 3 an equal-shaped
penalty. **The per-pip magnitudes are intentionally all `0` today** (`TODO(balance)`), so every
Trainer currently resolves to `RunMods.none` — mechanically the Rookie. The graphs are fully
wired but *unmagnituded*: a dedicated tuning pass sets these numbers and re-runs `tools/verify`
to keep the intended Hard curve (a spiky Trainer must stay a sidegrade), plus, where the design
calls for it, two new **downside** levers — low Energy risking a lost rip, low Grading rolling
with disadvantage. Until then the wiring is real and honest; only the numbers wait.

**Accomplishment badges.** Every Trainer card carries three difficulty badges — **E / M / H** —
lit for the tiers that Trainer has *cleared* and dimmed for the rest, read straight from
`GauntletProgress.clearedTiersByTrainer` (the same per-Trainer record that gates its tier
ladder). Badges are per-Trainer, so mastery is shown Trainer by Trainer, not as one global
flag.

**The mystery Trainer — Red.** A seventh Trainer sits on the roster concealed as **"???"**
with hidden pips and a "beat Hard mode with every other Trainer" progress line. Clearing **Hard
with all six of the others** reveals **Red** — a glass cannon with **5 Energy / 5 Aura** and the
bare minimum (**1**) in Selling, Grading and Inventory. The reveal is evaluated in
`GauntletProgress.ingest` right after a clear banks, so the last required Hard win unlocks Red
immediately and announces it once on the results screen.

> **No levels.** Trainers no longer gain XP or levels — that system was removed. A Trainer's
> pips are fixed; progression is *earning the roster*, *earning badges*, and *unlocking Red*,
> not dialling a single Trainer stronger. (Historic note: earlier builds scaled a Trainer's
> advantage from a level-1 baseline to a level-10 ceiling; that meta was cut in favour of the
> locked skill graph.)

⚠️ **Guardrail — a Trainer is a sidegrade, never raw power.** Classic's whole thesis (§10) is
*skill, not grinding, carries you*, so a Trainer **deepens an identity** without becoming a win
button. The Gauntlet `tools/verify` sims (§14.8) enforce this: a **neutral** run must clear Hard
with optimal play, *and* every Trainer is re-simulated to prove none trivialises Hard (best
≤ 97%). While magnitudes are unset the harness also asserts every Trainer tracks the neutral
Rookie; once they're tuned, a spiky Trainer that *requires* its specialty to win — or
trivialises the mode — has overstepped and gets retuned.

### 14.4 Catalysts — the run-long buff cards

New non-Spryte cards that grant run-long effects — the piece originally sketched as
"Energy cards" (increased foil chance, increased ultra chance, better grading luck, more
pack-opening power, …). Two design choices turn them from a buff pile into a system:

1. **Slot scarcity.** You may attune only *N* at once; a better one forces a **swap**.
   Scarcity is what makes them a build decision, not a checklist.
2. **Element lanes** so they combo — aligned to the game's existing six elements
   (`Element`: fire, rock, water, grass, electric, shadow), *not* a new set:

| Lane | Fantasy | Example effects |
| --- | --- | --- |
| Fire | Variance / aggro | +ultra chance, reroll a pack, "hot streak" per new card |
| Water | Economy | better spread, cheaper rips, dupe refunds |
| Grass | Scaling | Aura grows per rip, evolution-line multipliers |
| Electric | Tempo | +rips, +card per pack, chain multipliers |
| Rock | Defence / floors | guarantee a rarity floor, protect a grade roll |
| Shadow | Gambling | grading luck, high-roll multipliers with a downside |

Split them into **persistent attunements** (occupy a slot, last the run — the
"one-time-use, lasts-the-run" idea) and **instants** (no slot, consumed on use, e.g.
"guarantee a foil next rip"). Same-element pairs and cross-element combos (Fire + Shadow =
"meltdown": big ultra odds, worse spread) supply the depth. They drop from packs (competing
with Sprytes for the slot — real opportunity cost) *and* stock the shop (deterministic
acquisition).

⚠️ **Naming (Guideline 5.2) — decided.** "Energy cards" typed **Fire / Water / Grass /
Electric / Dark** is very close to a specific real TCG's terminology — exactly the
trademark-echo risk this doc opens by warning about (§1, §11). So the buff cards are
**Catalysts**, and the gambling lane is the game's own **Shadow**, never "Dark," staying on
the six shipped elements (`Element`). The word "Energy" is retired from the design; it
survives above only as a note of what the concept was first sketched as.

### 14.5 Difficulty tiers

Each tier **adds a mechanic**, not just bigger numbers, and each is unlocked **per Trainer**
by clearing the previous one *with that same Trainer* (Easy → Medium → Hard). The ladder is
walked once per Trainer — clearing Easy with the Ripper unlocks Medium for the Ripper, but a
different Trainer still starts at Easy — so switching archetypes means re-earning the climb.
The counts below are **starting points for the harness** (§14.8) — the shape is fixed, the
magnitudes get tuned:

| Tier | Rounds | Rips / round | Showcase slots (start) |
| --- | --- | --- | --- |
| **Easy** | 5 | 6 | 8 |
| **Medium** | 7 | 6 | 6 |
| **Hard** | 9 (last = **boss**) | 4 (boss 5) | 5 |

Target-Aura bars rise per round and spike on the boss round; absolute dollar
values are harness-tuned (§14.2, §14.8). **Rounds are single-life** — miss the bar at any
tier and the run ends (there are no reprints). Medium leans on an extra rip each round,
rather than a retry, to stay winnable with focused play. What each tier *adds* on top:

| Tier | Adds | Win reward (§14.6) |
| --- | --- | --- |
| **Easy** | The gentle tier: the fewest rounds, the lowest target ramp, and the widest Showcase soften the loop while it's being learned. | Foil Extended Art **common** |
| **Medium** | A steeper target ramp and a tighter Showcase (6 slots), leaning on the extra rip each round rather than a retry — you must build more efficiently to keep pace. | Foil Extended Art **uncommon** |
| **Hard** | The most aggressive target ramp, the fewest rips, the narrowest Showcase, and a **boss Aura** spike on the final round. | Foil Extended Art **rare / ultra** |

### 14.6 Rewards & the Binder

Winning a run grants a card's **Extended Art** — a full-bleed alternate illustration — and
files it in the **Binder** (§13). Extended Art is **purely cosmetic: it overwrites only the
artwork layer, never the value.** A card's worth still comes entirely from its base value ×
foil × grade, exactly as in Classic (§6–§7), and the Binder still keeps the
**highest-value** copy per card across **both** modes — so earning Extended Art never raises
or lowers a slot's value.

**Every Gauntlet pull and grade feeds the Binder too**, exactly like Classic: each card a
run rips or grades is folded into the all-time Binder and only ever raises a slot's
value-best (`GameState.recordGauntletCards`, called from the rip and grade paths). The
run's own Showcase is still discarded when the run ends — but the *collection value* a card
earned along the way persists, so a lucky Gauntlet foil or a GEM-MINT grade counts toward
the Binder even if you never win the run. Extended Art remains a separate cosmetic layer
over whatever value-best copy you hold.

What changes is *which illustration renders* that slot: the base art is swapped for its
Extended Art composition — a **generated, full-card `{id}-ext` asset** (one per Spryte,
authored in `tools/generate_art.py`: the card's own creature re-staged in a taller, richer,
per-card-unique set scene) — and **the foil shimmer and the PSA grade slab layer on top of
it** (`CardView(extendedArt:)`). So a foil PSA-10 you pulled in Classic keeps its value *and*
its effects; once you've also won that card's Extended Art in Gauntlet, the slot is drawn as
a foil, graded, Extended-Art card — all three finishes stacked. It renders on the **Binder**
(the permanent showcase) and in the reward picker; the live-run Collection still shows base
art. The tier's reward arrives as a **Foil** Extended Art copy (a guaranteed foil is the
sweetener), but the durable prize is the **art unlock**, which sticks regardless of which
copy is your value-best.

Two notes:

- **It's an art layer, not a value tier.** Extended Art is *not* a value multiplier and
  touches no `Economy` knob; it needs new renders from `tools/generate_art.py` and a
  compositor that stacks the existing foil/grade effects over them. Model it as a per-card
  **cosmetic record on the Binder** (e.g. the set of card ids whose Extended Art is earned),
  kept **separate** from the value-best `CardInstance` snapshot and added **additively**
  (§12) so old Binder files keep decoding.
- **The pull — decided.** The reward is **choose 1 of 3**, not a blind drop. Each option is
  a Foil Extended Art card at the tier's rarity — **Easy → common, Medium → uncommon,
  Hard → rare with a 20% chance to be ultra** (reusing `Economy.ultraHitChance`). Options
  are weighted toward cards whose Extended Art is still **unearned**; if every card at that
  rarity is already earned the pull promotes to the next rarity up, and if the whole
  catalogue's Extended Art is complete it pays a cash-and-Catalyst consolation instead.
  Choosing rather than rolling makes the reward one last decision and defuses the dupe.

### 14.7 Other strategic levers on the table

Curated, highest-leverage first; not all need to ship in v1:

- **Pack choice — ✅ shipped as the pack rail.** The run screen shows a tile per element
  set; you rip **whichever unlocked set you like** each rip, and locked sets are **bought
  open mid-round with cash** (a within-run tech tree — the five sets have distinct
  value/rarity curves, §3, §6, so which to unlock and when is a real lever). Set 1 starts
  unlocked; every other set shows **its own unlock price** and can be bought open **in any
  order** — each is priced independently off its Classic pack price (`GauntletEconomy.packUnlockCost`),
  so a run can splurge straight to a rich set or ladder up cheaply. This replaced the old
  single "rip a pack" button and the shop's "upgrade packs" line — packs are now a *round*
  decision, not a *shop* one.
- **Optional bounties** — per-round side goals ("keep 2 foils," "complete a Fire line")
  paying Catalysts or cash; rewards flexible, risky play.
- **Event nodes** between rounds — *The Appraiser* (pay for a guaranteed minimum grade, or
  gamble for GEM MINT), *Black Market* (buy an ultra outright — deterministic score),
  deal-with-the-devil **curse trades** for a strong Catalyst.
- **Reuse the booster box** (§8) as a high-variance shop splurge — its model, guarantees
  and tests already exist behind `FeatureFlags.removeBoosterBoxes`; Gauntlet is a natural
  home for it.
- **Damaged / sealed pulls** — cards worth little until graded, or hidden until appraised —
  extra per-pack decisions.

### 14.8 Guardrails & implementation notes

- **Own knobs, own harness.** Gauntlet gets its **own** balance constants (separate from
  `Economy.swift`'s Classic curve) and its **own** `tools/verify` simulations, held to the
  same statistical bar Classic is: an optimised build clears Hard, careless play busts, and
  a **level-0 Trainer can still win** (grinding is not required). Do not fold Gauntlet
  tuning into the Classic EV / win-rate assertions — they guard a different game.
- **Foundation-only model.** Gauntlet logic lives in `Models/` like `GameCore`, so the
  headless harness can compile it. Views stay SwiftUI-only.
- **Additive persistence** (§12). Trainer XP/levels, unlocked tiers, and the per-card
  Extended-Art cosmetic record (on the Binder, *not* `CardInstance`) are all new optional
  fields; old saves and the Binder file must keep decoding, and a bad file is quarantined,
  never destroyed.
- **Free vs. paid.** Gauntlet stays behind the full-game unlock (§11); it grants no
  in-game currency for real money and no randomised *paid* pull, so the 4+ rating and
  Guideline 3.1.1 stance are unchanged.

### 14.9 Design decisions & remaining tuning

The **shape** of the mode is now decided; what's left is numeric tuning the harness owns
(§14.8).

1. **Naming** — ✅ Catalysts + Shadow (never "Energy" / "Dark"), for the Guideline 5.2
   reason (§14.4).
2. **Interest** — ✅ banking between rounds at a **20% rate** (§14.1); the ceiling 🔧 harness-tuned.
3. **Run length** — ✅ Easy 5 / Medium 7 / Hard 9-with-boss rounds; 6 / 6 / 4 rips a round;
   **single-life at every tier — no reprints** (§14.5). Absolute target-dollar bars 🔧 harness-tuned.
4. **Rip model** — ✅ a hard **rip count per round + cash in the shop** (two currencies); the
   single-blended-currency option is dropped (§14.1).
5. **Reward pull** — ✅ **choose 1 of 3**, rarity by tier (common / uncommon /
   rare-with-20%-ultra), weighted toward unearned Extended Art (§14.6).
6. **Showcase carry-over** — ✅ one **compounding standing Showcase** per run, with a
   run-long capacity raisable in the shop, discarded at run's end — only the Binder reward
   persists (§14.1–§14.2).
7. **Meta ceiling** — ✅ **10 levels** that **smoothly scale each Trainer's advantage**
   (a ~20% level-1 baseline → level-10 ceiling, a likelihood or rate, never a raw new ability),
   plus horizontal roster unlocks; a level-0 Trainer *and* a maxed Trainer must both stay inside
   the Hard curve (§14.3).
8. **Trainer roster** — ✅ **earned, not just levelled**: only the **Rookie** is free; the
   five specialists each unlock on a lifetime Gauntlet milestone shown with a live progress
   bar (§14.3). Milestone thresholds are meta pacing, not a difficulty knob.
9. **Pack rail** — ✅ pick **which unlocked element** to rip each rip; every locked set is
   bought open mid-round with cash, **independently priced and in any order** (not a forced
   ladder). Replaced the single rip button and the shop's pack upgrade (§14.7).
10. **First-run explainer** — ✅ a one-time intro screen (re-openable from the ⓘ button)
    walks the target, scoring & evolution lines, Trainers, Catalysts, the shop, and prizes
    before the first run, so the loop is legible without a tutorial mode. Gated on a
    `hasSeenIntro` flag in `GauntletProgress`.

🔧 **Left for the harness** (§14.8): the magnitudes — target-dollar bars per round, the
interest ceiling, the round-clear payout curve, and each Trainer's per-level stat budget —
tuned so an optimised build clears Hard, careless play busts, and grinding is never required.

---

## 15. Open questions for review
1. **Creature brand name** — ✅ *decided:* **Sprytes** (see §2).
2. **Art direction** — ✅ *decided:* hand-built flat-vector creatures, one per card,
   generated by `tools/generate_art.py` (see §1). Every card has its own character
   design — no recolours — enforced by `generate_art.py dupes`. The earlier
   procedural "sigil" emblems are retired; `SigilView` survives only as the fallback
   if an art asset is ever missing.
3. **Grading fee** — ✅ *decided:* flat per‑set ramp **$2/$4/$6/$8/$10** (see §7).
4. **Card look** — thumbs‑up the mockup style, or tweak colors/frames/foil?
5. Set names / theme order OK? Any names to change?
6. **Gauntlet Mode** — full design drafted in §14; decisions and remaining tuning in §14.9.
