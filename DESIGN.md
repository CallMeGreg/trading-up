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
| 2 | **Tidecaller** | Water / ice      |       $20  | ×2               |
| 3 | **Verdspire**  | Grass / nature   |       $40  | ×4               |
| 4 | **Voltcrest**  | Electric / storm |       $70  | ×7               |
| 5 | **Umbral Reach**| Shadow / cosmic |      $120  | ×12              |

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
that tier); the rest sit lower.

| Tier       | Set 1        | Set 2 (×2)   | Set 3 (×4)   | Set 4 (×7)    | Set 5 (×12)    |
|------------|--------------|--------------|--------------|---------------|----------------|
| Common     | $0.25–0.90   | $0.50–1.80   | $1–3.60      | $1.75–6.30    | $3–10.80       |
| Uncommon   | $1.00–2.75   | $2–5.50      | $4–11        | $7–19.25      | $12–33         |
| Rare       | $3.00–7.50   | $6–15        | $12–30       | $21–52.50     | $36–90         |
| Ultra Rare | $9.00–25.00  | $18–50       | $36–100      | $63–175       | $108–300       |

### Packs
- **6 cards per pack:** 3 commons, 2 uncommons, 1 "hit."
- The **hit slot** is a Rare 80% of the time, Ultra Rare 20%.
- A pack's total contents are worth on average **~1.1× the pack price** (positive but
  with lots of variance — good pulls net big, bad pulls lose a little).

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

> **⚠ Open question — grading fee.** With the odds above, grading is *positive* EV
> (~1.5× on average), so with no cost you'd always grade everything and there's no
> decision. I propose a **flat grading fee per set** (S1 $2, S2 $4, S3 $8, S4 $14,
> S5 $24) so grading a low rare is a real gamble but grading an ultra is usually worth
> it. **Confirm whether you want a fee, and this amount.**

Foil × grade stack, e.g. a foil rare that grades PSA 10 = base **×3 ×5 = ×15**.

---

## 8. Booster box

A cheaper‑per‑pack commitment with guarantees above the statistical average.

- **Box = 24 packs**, priced at **20× the pack price** (24 packs for the cost of 20).
  - S1 $200 · S2 $400 · S3 $800 · S4 $1,400 · S5 $2,400.
- **Guarantees:** at least **6 ultra rares** (avg ≈ 4.8) and **at least 4 foils**
  (avg ≈ 1.4). If a freshly opened box falls short, extra hits are upgraded in.

---

## 9. Bonuses

- **Complete an evolution line** → cash bonus:
  - 2‑stage line = **0.5× pack price** of its set · 3‑stage line = **1.0× pack price**.
- **Complete a full set (all 50)** → **huge** cash bonus = **30× that set's pack price**
  (S1 $300 … S5 $3,600). Roughly funds a booster box of the next set.

---

## 10. Win / lose & stats

- **Lose:** cash hits **$0** and you have **no sellable cards left**. You can never
  sell your **last copy** of a unique card (you'd lose collection progress), so "broke"
  means only singletons remain. A loss screen shows: cards collected per set, and total
  unique cards.
- **Win:** collect all **250** unique creatures. A winner's screen shows full stats:
  per‑set completion, foils, best grades, peak cash, packs opened, etc.

---

## 11. Persistence
Local save (Codable → JSON in the app's Documents dir): cash, owned cards (with
foil/grade state + counts), stats, and claimed bonuses. No account/server needed for v1.

---

## 12. Open questions for review
1. **Creature brand name** — keep `Mythlings` or pick another?
2. **Art direction** — approve procedural "sigil" art for v1 (real art later)?
3. **Grading fee** — add the proposed flat fee (recommended) or make grading free?
4. **Card look** — thumbs‑up the mockup style, or tweak colors/frames/foil?
5. Set names / theme order OK? Any names to change?
