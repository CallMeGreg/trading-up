# Trading Up — Game Design ("The Chase")

> **This is the design of record for Trading Up 2.0.** The game is a grail-hunter
> roguelite: the same 250 Sprytes and the same pack-rip reveal as 1.0, but the
> purpose of a run is reinvented — you no longer collect-them-all in one terminal
> run, you **trade up toward one dream card (a Grail)**, over and over, filling a
> permanent Binder across many runs. Sections are marked **Ships** vs **Staged for
> follow-up** in §13; anything staged is designed here but not yet wired.

---

## 0. What changes, and why

v1 is a **completion** game: rip packs until you own all 250 Sprytes, or go broke. One
long terminal run, no reason to replay after winning. The Circuit draft turned that into
a dealer-ladder climb toward escalating cash Quotas. This revision keeps the roguelite
bones but **changes the fantasy**:

- The competitive card-**show** circuit is gone.
- A run's purpose is no longer *"get richer / rank up."* It's **land a Grail** — one
  specific dream card you trade up toward.

The title finally reads literally: you start a Hunt with a fistful of commons and a
stake, and you **trade up** — rip, grade, foil, flip — until you can put the Grail in
your hands.

---

## 1. The run loop — a Hunt

- A **Hunt** is one run. It targets a **Grail**: a specific Spryte + condition. You **pick
  your Grail from 3 offers at the start — always one Easy, one Medium, and one Hard** (§2):
  a loose classifier, a set-plus-classifier, and a named-card/evolution target. A harder
  Grail pays more Renown but means a longer, meaner Hunt. The Grail is your win condition
  for the run.
- A Hunt is a chain of escalating **Leads** `L = 1, 2, 3, …` ending in **the Score**.
- **Leads** replace "Shows." A Lead is a *source* you chase the Grail through — an estate
  find, a shop's backstock, a convention floor, an online lot, a private collection.
  Flavor only: no competition, no ranking, no "making the cut."
- **Each Lead has:**
  - an **Ask** — the objective you must satisfy to **run the Lead down** and follow it to
    the next, hotter one. Asks **vary by type** (§1.1) — they are *not* always cash. This
    is the big change from the single escalating cash Quota.
  - an **Energy budget** — how many packs you may rip at this Lead (the round clock). Rip a
    pack = spend **1 Energy** *and* its cash price. Selling and grading **don't** cost
    Energy — only ripping does (grading still pays its cash fee). Energy **does not** carry
    between Leads.
  - optionally a **Complication** (§8) — a weather/market/authenticity modifier that
    forces adaptation.
- **Run the Lead down** the instant you satisfy its Ask → advance, bank Renown, keep your
  cash / stock / Items, **draft a reward**, visit the **Bazaar**.
- **The Score** — the final Lead. The Grail is on the table at a **price** (cash) and/or
  **condition**. Meet it → **the Grail is yours and the Hunt is won on the spot** — no
  gamble, no extra step. This is the terminal cash sink everything else was building toward.
- **Bust** — fail a Lead's Ask before its Energy runs out with no way there, or reach the
  Score but can't meet the Grail's price → the Grail slips away and the Hunt ends. This
  is a **summary**, not a punishment (§6). Death is progress.

Cash, stock and Items **persist across Leads within a Hunt**; only the Energy budget
refreshes and the Ask bar rises — the same escalating pressure as the Circuit draft, but
now the finish line is a *card*, not a number.

### 1.1 Asks — the varied objective (a strategy engine)

Where the Circuit had one thing (`cash ≥ Quota`), a Lead's **Ask** is drawn from a deck
of objective types, so every Lead asks a different question of your engine:

| Ask type | Satisfy by… | Consumes the card? |
| --- | --- | :---: |
| **Cash** | bank $X | no |
| **Grade** | possess a card graded ≥ N | no |
| **Handover** | give your contact a card meeting a spec (a rare, a foil, a graded 8+) | **yes** |
| **Set** | own K distinct cards from a named set | no |
| **Evolution** | complete a named evolution line | no |
| **Value** | own a single card worth ≥ $X | no |

You always see the **current Lead's Ask *and* the next Lead's Ask** (route foreknowledge),
so you can plan two moves ahead and draft/shop to fit. **Handover** Asks create a real
*spend-vs-keep* dilemma: pay your worst qualifying card, and protect the ones you need
for the Grail or a later Set/Evolution Ask.

### Why it's tense, not grindy

Same contract as v1: packs are ≤1.0× EV and dupes sell at 75%, so **buy-and-dump loses
money**; you grow only through *edges* — grade-before-sell, foils, evolution bonuses,
your Item engine. Energy caps each Lead so you can't grind. The new pressure is **varied
Asks**: no single strategy (hoard cash) solves every Lead, so your engine has to stay
flexible against whatever the next one demands.

---

## 2. Strategic decisions (expanded)

The redesign deliberately widens the decision space. Each Hunt is a stack of choices:

1. **Pick your Grail** *(Hunt start)* — the three offers are **always one Easy, one Medium,
   one Hard**. **Easy** = a loose classifier (any foil, any PSA 10, any ultra worth ≥ $X) —
   many cards qualify, so it's a fast Hunt for the least Renown. **Medium** = a **named set**
   plus a classifier (a *Voltcrest* foil, a graded-8+ *Tidecaller* ultra). **Hard** = a
   **specific named card** or an **evolution-line placement** plus a classifier
   (*Cinderling's final evo graded 9+*, the foil Set-5 legendary) — a one-in-250 target, the
   longest, meanest Hunt, the most Renown. Match your pick to your Guild upgrades and Trainer.
2. **Pick your Trainer** *(loadout)* — *(formerly "Patron.")* a starting specialist that
   bends the whole Hunt (e.g. *The Grader* opens with a Loupe; *The Digger* with +2 Energy
   each Lead; *The Speculator* with a free first pack). You **start with 1 Trainer** and
   unlock more options with Renown (§6), so every Hunt begins with a strategic identity.
3. **Route the Leads** — after each Lead you choose the next from **2–3 branches**, each
   shown up front with its **Ask type**, **Complication** and **reward**. Steer toward Asks
   you can already meet and rewards you need; steer around Complications that punish your
   build. *Example:* you're offered **(A)** *Cash $600* under *Cold Snap* → reward a passive
   Item, **(B)** *Grade ≥ 8* → reward +2 Energy, **(C)** *Handover: a foil* → reward cash.
   Holding a graded 9 but low on cash, you take **(B)** — you already satisfy it and pocket
   the Energy — and you dodge **(C)** if that foil is bait you need for your Grail.
4. **Read the Ask, plan two ahead** — you always see the current Ask **and** the next one,
   so buy and draft for the *next* Ask, not just this one. *Example:* this Ask is *Cash $500*
   and the next is *Set: 4 distinct Tidecallers* — hit the cash bar by selling your
   **Emberfall** dupes, **not** your Tidecallers, so you arrive already halfway to the Set
   Ask. Or the next Ask is *Grade ≥ 9*, so you bank a rare **now** and grade it while this
   Lead's Energy is still spare.
5. **Spend-vs-keep on Handover Asks** — which card do you surrender, and which do you
   protect for the Grail or a later Set/Evolution Ask?
6. **Invest vs save at the Bazaar** — every dollar spent on **Items** is a dollar not banked
   toward the Score's Grail price. The core roguelite tension, kept.
7. **Rip strategy** — each Lead's Energy is a fixed budget: spend it on **many cheap packs**
   (volume — more cards to sell, hand over, or complete sets with) or **fewer premium packs**
   (higher-value hits toward a Value/Grade Ask or the Grail itself)?

---

## 3. Your Trainer + run-scoped cards

Beside the Sprytes sit your **Trainer**, your **Items**, and **Energy**. None are Sprytes,
none count toward the 250, and **packs still contain only Sprytes, so the reveal is
untouched.** Items and Energy come from the post-Lead **draft** and the **Bazaar**.

### Trainers — your Hunt specialist (pick 1)

*(Formerly "Patron.")* At the start of every Hunt you pick **one Trainer** — a mentor who
gives the whole run a strategic identity. You **start with just 1 Trainer available**; the
rest are **options you unlock permanently with Renown** at the Guild (§6), so widening your
Trainer menu is the main long-haul Renown sink.

| Trainer | Bends the Hunt by… |
| --- | --- |
| **The Grader** | opening each Hunt with a **Loupe** (grading is free). |
| **The Digger** | **+2 Energy** every Lead — more packs to rip. |
| **The Speculator** | **first pack each Lead is free** (no cash, no Energy). |
| **The Financier** | a **bigger stake** (+starting cash) and cheaper Bazaar rerolls. |
| **The Curator** | **draft 2-keep-1** and +1 starting Item. |
| **The Foilhunter** | **+5% foil** all Hunt, and foils sell for more. |

### Items — bought with cash, used free (your engine + burst)

*(Formerly the "Trainer" relics **and** the "Power-Ups.")* Items are gear you collect
during a Hunt — some **passive** (always-on for the run), some **one-shot** (single use).
You **buy them with cash** at the Bazaar, or take one free from the post-Lead **draft**.
**Using an item costs nothing** — no Energy, no second fee; the only cost is the cash you
paid (and, for one-shots, that they're consumed). **Cash is the natural limiter** on how
big your engine grows.

| Item | Type | Effect |
| --- | --- | --- |
| **Loupe** | passive | Grading is free. |
| **Bulk Buyer** | passive | Duplicates sell at 90% (vs 75%). |
| **Gilder** | passive | +5% foil chance. |
| **Appraiser** | passive | Every grade rolls one tier higher (min bump). |
| **Whale** | passive | +1 card in every pack (7-card packs). |
| **Stipend** | passive | +$2 per unique card owned, paid when you run down a Lead. |
| **Holo Press** | one-shot | Turn a chosen card foil (×3 value). |
| **Fast-Track Grade** | one-shot | Grade a card free, guaranteed 8+. |
| **Pack Search** | one-shot | Next pack's hit is guaranteed an ultra. |
| **Market Tip** | one-shot | Instant +$X cash (scaled to the current Lead). |
| **Counterfeit** | one-shot | Add a second copy of a card you own. |
| **Polish** | one-shot | Bump a graded card up two grade tiers. |

### Energy — the pack-ripping fuel (the throttle)

Energy is what you **spend to rip packs**. Each Lead grants an **Energy budget** (base +
your Trainer + Guild upgrades); **each pack you rip costs 1 Energy plus the pack's cash
price.** Energy is the **round clock** — it caps how many packs you can open at a Lead so
you can't grind — and it **doesn't carry between Leads.** *(This replaces the old "Rips.")*

---

## 4. The Bazaar (kept) + the draft

You liked it — it stays, between Leads:

1. **Draft** — pick **1 of 3** offered cards (an **Item** or **Energy**), free.
2. **Bazaar** — spend cash on **Items** (and Energy) + **reroll**. Spending here competes
   with banking toward the Score's Grail price — the invest-vs-save squeeze, now pointed at
   a *card* instead of a quota.

---

## 5. Currencies & resources — what each is for

The redesign runs on **three spendable things** — plus a permanent collection (your
**Binder**, §6) that's never spent:

| Resource | Scope | Earn it by | Spend it on | In one line |
| --- | --- | --- | --- | --- |
| **Cash ($)** | per-Hunt | selling dupes (75%, more if graded/foil), evolution bonuses, cash Items (Market Tip), Stipend payouts | **ripping packs** (each pack's cash price), **buying Items** at the Bazaar, Cash/Value Asks, and the **Grail's price at the Score** | moment-to-moment fuel; starts each Hunt at your **stake** |
| **Energy** | per-Lead | granted fresh each Lead (base + your Trainer + Guild) | **ripping packs** (1 Energy + the pack's cash each) | the round clock — paces your ripping, stops you grinding a Lead |
| **Renown** | **permanent** | running down Leads, landing Grails, Discoveries, Prestige surplus | permanent upgrades at the **Collectors' Guild** — including unlocking more **Trainer options** | the meta-progression currency; the *only* thing you spend that lasts |

**Rules of thumb:** *Cash* is short-term fuel (gone when the Hunt ends) and now the **only**
cost of Items — you buy them, then use them free. *Energy* paces your ripping, one Lead at
a time. *Renown* is the only thing you *spend* that lasts. Your **Binder** is the only
thing you *keep* — a permanent collection, not a resource (§6).

---

## 6. Meta-progression & the main menu (persists across Hunts)

Everything permanent lives behind a **main menu** with four destinations:

| Menu item | What it opens |
| --- | --- |
| **New Run** | The **Collectors' Guild** — the between-run hub where you spend **Renown** on permanent unlocks, pick your **Trainer** and **Grail**, then launch a Hunt. |
| **Binder** | Your **permanent collection** — the long-term goal (below). |
| **Stats** | Lifetime totals, records, **Discoveries**, and **Grails landed**. |
| **Settings** | Existing app settings (audio, data, restore purchase…). |

### The permanent Binder — the long-term goal

The **Binder** is a persistent album with **one slot per Spryte — all 250**. When a Hunt
ends — **win *or* bust** — the **best (highest-value) version of each card you were
holding** is deposited into its slot if it beats the copy already there. **Foil and grade
count**, so a slot is never "done" at first ownership: you keep chasing a *foil*, then a
*9*, then a *Gem-Mint 10* to upgrade it. Collection becomes a **quality chase**, not a
checkbox.

- It's **read-only** — a museum of your best copies. You never spend from it and it never
  feeds a Hunt (so it can't trivialise Asks); it is pure progress and prestige.
- **Binder completion** (weighted by grade/foil) is the headline endgame number: a raw
  copy of all 250 is **Master Collector**; a *Gem-Mint foil* of all 250 is true 100%.
- Because **every** Hunt — even a bust — deposits its best copies, **no run is wasted**:
  you always advance the Binder. *Death is progress*, literally.

### Long-term goals (why you keep playing)

1. **Fill the Binder** — best version of all 250, then **upgrade every slot** toward
   foil / Gem-Mint. The deep, effectively endless chase.
2. **Unlock every Trainer** — spend Renown to permanently add specialists to your pick list
   (you start with just one), turning Renown into build variety.
3. **Buy out the Guild** — every permanent upgrade (Trainer options, stake, Energy, Bazaar).
4. **Land the marquee Grails** — the hardest chase cards (a Set-5 foil-10), logged in Stats.
5. **Climb Ascension** — escalating difficulty tiers for prestige once the rest is in reach.

### Renown & the Guild

- **Renown** — earned per Hunt = `Leads run down × base + Grail bounty + Discovery
  bonuses + Prestige surplus`. Spent at the **Collectors' Guild** (reached via **New Run**).
- **Guild upgrades** (Renown-bought, permanent, incremental): **unlock Trainer options**
  (widen your pick list from the starting **1**) · +**stake** · +1 starting **Energy** per
  Lead · +**Bazaar slot** / cheaper rerolls · **discount or unlock Items** in the Bazaar ·
  unlock **Ascension** (harder Hunts for more Renown — the long tail).

### Discoveries (re-themed Milestones)

One-time achievements that permanently unlock content, so variety compounds Hunt over
Hunt. They're a *second* unlock path alongside the Renown shop — a few signature **Items
and Trainers** are **earned** this way rather than bought:

| Discovery | Trigger | Unlocks |
| --- | --- | --- |
| **First Lead** | run down your first Lead | the Guild itself |
| **First Grail** | land your first Grail | Prestige/endless + a new Trainer |
| **Set Master** | complete a full 50-card set in a Hunt | strong Item into the pool + big Renown |
| **Hoarder** | hold 8 copies of one card | *Counterfeit* + *Whale* |
| **Gem Holo** | own a foil graded 10 | *Gilder* + *Polish* |
| **Ace Grader** | grade 3 cards 9+ in a Hunt | *Appraiser* |
| **Deep Chase** | reach the Score on a Set-4+ Grail | Ascension tiers + a new Trainer |
| **Ultra Hunter** | pull 10 ultras (lifetime) | *Pack Search* |
| **Centurion** | 100 unique cards in the Binder (lifetime) | a new Trainer |
| **Master Collector** | all 250 in the Binder (lifetime) | huge Renown + prestige cosmetic |

### Win / loss

- **Win:** landing a Grail = a **Grail Landed** celebration (reuse v1's 1-of-1
  `RunSignature`, minted as a **Grail plate**); the card itself lands in your **Binder**
  with a special Grail frame, and the Grail is logged in **Stats**. Then **Prestige** (a
  bonus Grail appears) or cash out.
- **Loss:** failing a Lead or the Score ends the Hunt with a **summary** (Leads run down,
  Renown earned, Discoveries hit, **cards deposited to the Binder**) → back to the Guild.
  **Death is progress**, the roguelite contract — not v1's terminal Game Over.

---

## 7. Base economy & tuning (base $$ adjusted)

- **Starting stake: `$120`** per Hunt — up from v1's **`$100`**. Rationale: the new
  **varied Asks** add early-game friction the Circuit draft's single cash Quota didn't, so
  a slightly bigger cushion keeps **Lead 1–2 genuinely gentle** (critique #2) while the
  escalating Asks and the Grail's price at the Score re-tighten the vise. It's a
  Guild-upgradable knob (`+$ stake`), so *felt* starting cash rises with meta-progress.
- **Pack prices unchanged:** `[10, 30, 75, 160, 400]`. The reveal and the set-value curve
  players already know are untouched.
- **Cash Asks** scale **~×1.5 per Lead** from a low base (Lead 1 ≈ **`$80`**, comfortably
  under a `$120` stake so the opener breathes), **interleaved** with non-cash Asks so cash
  is never a monotonic wall.
- **Grail price at the Score** scales by the Grail's set × condition — a Set-1 ungraded
  Grail is a few hundred; a Set-5 foil-9 Grail is several thousand — which is exactly what
  the deep, escalating Leads exist to fund.
- All numbers above are **illustrative**. The real values live in `Economy.swift` and are
  owned by the **verify harness**, which must assert a real bust rate for weak play and a
  healthy win rate for strong play across Hunts (same statistical contract as v1). The
  **set-completion cash bonus stays removed**; **evolution-line bonuses stay** as the key
  early growth lever and a non-sale cash source.

---

## 8. Complications (variety / bosses) — re-themed Twists

Some Leads (and a **boss Lead** every 4th) carry a **Complication** that forces
adaptation. Because you see it while routing (§2, *Route the Leads*), it's a *pre-committed
strategic wager*, not a random gotcha:

*Cold Snap* (sellback 60%) · *Backlog* (grading 2×) · *Counterfeits* (no foils this Lead)
· *Rush* (−2 Energy, −20% Ask) · *Bull Market* (+20% pack value, +25% Ask) · **Boss — The
Authenticator** (Ask requires a graded 9+). Your Trainer and your Items are the counters.

---

## 9. Updating to 2.0 — fresh start + a "What's New" explainer

Because the game **fundamentally changes shape**, a v1 completion save has no faithful
mapping onto a grail-hunt (no Hunt, no Renown, no Trainers, no Leads). Rather than
silently fabricate a half-migrated state, **updating to 2.0 resets the game to a clean
slate and shows the player exactly why.** On first launch of 2.0:

1. **The old save is quarantined, never deleted** — reusing `Persistence.swift`'s existing
   move-aside mechanism. The v1 collection is preserved on disk, recoverable, exactly like
   a corrupt or newer-schema save today.
2. **A fresh roguelite game begins** — Guild at zero, first Hunt ready, stake at base.
3. **A full-screen "Welcome to Trading Up 2.0 — What's New" explainer** appears: what a
   Hunt / Lead / Grail is, the Bazaar and your Trainer / Items / Energy, Renown and the Guild,
   **why your old game was reset**, and reassurance that the old collection file is kept in
   Documents. Gated on a stored `lastSeenMajorVersion`, so it shows **once**.
4. **Your old v1 collection seeds the new permanent Binder** — the best copy you owned of
   each Spryte is imported as that slot's starting version, so *years of collecting aren't
   erased; they become your Binder*. That's the **only** carryover: **nothing
   gameplay-affecting transfers** (no cash, no run, no Renown), and the Binder is read-only
   (§6), so it can't skew the fresh economy. Player-friendly and honest.

Implemented as a new `SaveLoadIssue` case (e.g. `.resetForNewVersion(previousSave
QuarantinedAs:)`) that the UI renders as the What's-New screen, and covered by
`SaveFormatTests` / `SaveStoreTests` — the never-delete contract stays a tested invariant.

---

## 10. Free tier / IAP (principle unchanged)

Set 1 (Emberfall) stays **free to play in full**: the whole loop — Hunts, Leads, the
Bazaar, Trainers, Items, Energy, Renown, the Guild, Discoveries — runs on Set-1 packs,
with Set-1 Grails. The one-time **full unlock** opens Sets 2–5 (whose higher-value cards
fuel the deep Grails and the biggest Scores) and the Master Collector goal.
`freeSetCount = 1` and the StoreKit gate in `GameState` are unchanged; the economy knobs
(which the harness guards) stay out of the entitlement path. Tune so a Set-1-only player
still gets a satisfying multi-Lead Hunt and can land Set-1 Grails.

---

## 11. Architecture / persistence

- Pure model stays Foundation-only. New `Models/Boosts.swift` (Trainer / Item / Energy
  defs + effect model + catalog). New `RunState` (the Hunt: Grail, Lead index, Ask, route,
  **stock**, cash, **chosen Trainer**, **Items**, Energy) and `MetaState` (Renown, the
  **permanent Binder** — best copy per card, 250 slots — **unlocked Trainer options**,
  Discoveries, Guild upgrades, Grails landed, lifetime). `GameCore` gains the Lead loop,
  Ask evaluation, effect application, Discovery checks and Renown accrual. **All balance in
  `Economy.swift`.**
- Save envelope → **v3**. The reset-and-explain flow (§9) *replaces* the Circuit draft's
  "seed a fresh Season from the old collection" migration: v1/v2 saves are quarantined,
  the old collection is imported into the permanent Binder (§9), everything else fresh.
  Lenient decode + corrupt-save quarantine unchanged.
- `verify` harness rewritten to enforce the new balance (losable / winnable / skill gap
  across Hunts, varied-Ask satisfiability) + integrity of the new card types. CI unchanged.

---

## 12. Critique (as a game critic) + resolutions

1. **"It's Balatro with cards."** Still an ante/joker skeleton. *Resolution:* the
   **grail-hunt purpose** and **varied Asks** pull it toward the game's own fantasy —
   *trading up toward a specific card* — powered by pre-existing systems (grading variance,
   buylist spread, evolution lines) that aren't Balatro's. Naming stays original.
2. **Snowball knife-edge.** Cash carryover + rising Asks still compounds. *Resolution:*
   varied (non-cash) Asks + route branching + Ask foreknowledge give more ways to recover
   than a single cash wall did; early Leads gentle; harness asserts both bust and win
   rates.
3. **Selling at 75% feels bad.** *Resolution:* intended squeeze; Bulk Buyer +
   grade-before-sell are the counters, evolution bonuses a non-sale cash source. And a
   Handover or Value **Ask** can suddenly want a card you'd have dumped, so selling is a
   *judgement call*, not a reflex.
4. **Scope explosion.** Grail, Leads, Asks, route map, Trainers, the permanent Binder +
   main menu, Items, Energy, Bazaar, Guild, Discoveries, Ascension, Complications.
   *Resolution:* ship a **rock-solid core** (§13); design and stage the rest, marked in
   DESIGN.md.
5. **Free tier could feel gutted.** *Resolution:* on-brand; Set-1-only must still deliver a
   real multi-Lead Hunt with Set-1 Grails, Renown and Discoveries. The paywall sells
   *depth*, never the loop.
6. **Reveal shares the stage.** *Resolution:* the point — and packs stay Sprytes-only, so
   the dopamine is intact; the new strategy wraps around it.
7. **Resetting saves is hostile.** *(new)* *Resolution:* the reset is **explained,
   one-time, and non-destructive** — old save quarantined, and your old collection
   imported into the new Binder (§9). Honesty plus a real What's-New beats a silently
   broken half-migration.
8. **Enough long-term goal? Does a bust matter?** *(new)* *Resolution:* the **permanent
   Binder** is the spine — best copy of all 250, then upgraded toward Gem-Mint foil, an
   effectively endless *quality* chase — and **every Hunt, win or bust, deposits its best
   copies** and can hit Discoveries or Renown unlocks, so no run is wasted. Renown's
   roster / Guild buildout and Ascension stack on top.

---

## 13. What ships in this PR (the core) vs designed-for-later

**Ships (fully modeled, tested, playable):**

- Hunt → Lead → **Ask** → **Score** loop; run-down / bust; **Grail selection** (pick 1 of
  3); Renown; run-summary loss.
- **Main menu** (New Run · Binder · Stats · Settings) + the **permanent Binder** (best
  copy of all 250, weighted completion %), seeded from any v1 collection on update.
- **Varied Asks** (all six types) with evaluation + a basic **branching route** (2–3
  choices per Lead).
- Your **Trainer** pick + an **Items** catalog (~12 Items: passive + one-shot) + **Energy**,
  with a working **effect engine**.
- **Draft (1 of 3) + Bazaar** with reroll; **Items bought with cash, used free**.
- A starter set of **Trainers** (specialists): you **start with 1**, and Renown at the Guild
  **unlocks more Trainer options** — the main permanent Renown sink.
- **Discoveries** (§6) + a **Collectors' Guild** (reached from **New Run**) with a starter
  set of Renown upgrades (Trainer options / stake / Energy / Bazaar).
- **Update reset + "What's New" explainer** (§9); persistence **v3**; verify harness +
  unit tests rewritten; DESIGN / DEV / TESTING / README updated; `MARKETING_VERSION → 2.0`.
- **Light Complications** (a couple wired into UI).

**Designed, staged for follow-up:** full Complication/boss deck; deep Ascension / Circuit
tiers; richer route maps; Bazaar economy depth; more Trainers and Items; bespoke Grail-plate
art. Marked as such in DESIGN.md.
