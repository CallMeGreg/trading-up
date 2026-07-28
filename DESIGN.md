# Trading Up — Game Design Document

> A Pokémon‑TCG‑inspired **card collecting + economy** game for iOS (SwiftUI).
> Original creatures, names, and art — **zero** Pokémon references, names, or images.

---

## 1. Concept

You are a card collector with **$100** starting cash. Buy packs, open them in an
exciting reveal, and try to **collect all 250 creatures** across 5 sets. Sell
duplicates back to the shop, gamble on **card grading** for value swings, and chase
**foils** and **ultra rares**. Run out of money with nothing left to sell and you
lose. Complete the collection and you win.

It's a *slot‑machine‑meets‑collection* loop: the pack opening is the dopamine, the
economy is the strategy, the 250‑card completion is the goal.

### Art direction (important — read this)
We can't ship real creature art for 250 characters on day one, and we must not copy
Pokémon art. Proposed MVP art direction: **procedural elemental "sigils."** Each
creature is rendered as a deterministic geometric emblem (mandala of rings, polygons,
and rays) generated from its name + type, over a themed gradient. It looks
intentional and premium, scales to 250 cards for free, and can be swapped for
commissioned art later without changing the game. The mockups show this style.

---

## 2. Brand / naming

- **App / game title:** **Trading Up**
- **Creatures are called:** **Mythlings** *(placeholder — alternatives below)*
- Tagline: *"Collect all 250 Mythlings."*

Creature-brand alternatives to pick from at review:
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
| 5 | **Umbral Reach**| Shadow / cosmic |      $320  | ×32              |

The price curve is deliberately **steep** — the gap between sets widens ($20 → $45 →
$85 → $160), so each later set is a genuinely bigger‑stakes push, not a gentle step up.

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
  | 5 Umbral Reach  | $320      | **0.60×** | ~$192  |

  Any single pack still has **lots of variance** — a foil or a top‑tier hit blows past
  the average, a cold pack falls below it. Foils (~+2% expected) and opt‑in grading are
  upside on top of these base‑value targets.

### Sell‑back spread (the shop lowballs the buylist)
Every card has a **market value** (`currentValue`) — that's what drives your collection
value, net worth, and the "Value" readouts. But when you **sell** a duplicate, the shop
only pays **65%** of that market value (`sellbackRate = 0.65`; `sellValue = 0.65 ×
currentValue`), exactly like a real card shop buylisting below market.

This spread is the **main source of losing risk**. Because liquidation is now
net‑negative, churning packs/boxes and dumping the dupes slowly **bleeds** cash — the
more you spam, the faster you bleed. As a set fills up and packs start pulling mostly
duplicates, the endgame of each set becomes a squeeze: gamble to complete it before you
run dry. Collection value / net worth stay at **full** market value (aspirational); the
spread only bites at the moment of sale.

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

## 8. Booster box

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

- **Lose:** cash drops **below the cheapest pack price ($10)** and you have **no
  sellable cards left**. You can never sell your **last copy** of a unique card (you'd
  lose collection progress), so "broke" means only singletons remain. A loss screen
  shows: cards collected per set, and total unique cards.
  - **This is now genuinely reachable.** The **sell‑back spread** (§6), the **steep
    per‑set price curve** (§3), and the **trimmed box/bonus payouts** (§8, §9) together
    mean careless play — spamming the cheapest box and dumping every dupe at 65% — can
    bleed you dry before a set completes. In simulation that reckless loop **busts ~44%**
    of the time.
- **Win:** collect all **250** unique creatures. A winner's screen shows full stats:
  per‑set completion, foils, best grades, peak cash, packs opened, etc.
  - Thoughtful play — pacing your buys, keeping a cash cushion, and **grading valuable
    dupes before selling** — still **wins ~77%** of the time. The gap between the two is
    the point: skill, not grinding, is what carries you through.
  - **Winning is not an exit.** The celebration is shown once; dismissing it keeps the
    completed collection intact and browsable. Starting over is always a separate,
    confirmed action — the reward for finishing shouldn't be losing what you finished.

**Difficulty target: moderate.** Thoughtful play usually wins; careless play can
bankrupt you. Balance knobs all live in `Economy.swift`; the simulations that hold this
target live in `tools/verify/main.swift` (strategy sims + economy‑knob assertions).

---

## 11. Persistence
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

---

## 12. Open questions for review
1. **Creature brand name** — keep `Mythlings` or pick another?
2. **Art direction** — approve procedural "sigil" art for v1 (real art later)?
3. **Grading fee** — ✅ *decided:* flat per‑set ramp **$2/$4/$6/$8/$10** (see §7).
4. **Card look** — thumbs‑up the mockup style, or tweak colors/frames/foil?
5. Set names / theme order OK? Any names to change?
