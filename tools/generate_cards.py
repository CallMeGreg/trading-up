#!/usr/bin/env python3
"""
Trading Up — card data generator.

Produces the 250-card database (5 sets x 50) with names, rarities, elements,
evolution metadata, base values, and flavour text. Emits:
  - data/cards.json          (human-readable reference / source of truth)
  - TradingUp/Generated/CardData.swift   (embedded, compiled into the app)

Also validates all design invariants and prints an economy report; exits non-zero
if anything is wrong. Run:  python3 tools/generate_cards.py
"""
import json, os, random, sys

random.seed(20260716)

# ------------------------------------------------------------------ curated names
# Each set: 6 three-stage lines, 7 two-stage lines, 18 singles
# singles order = 12 commons, 2 uncommons, 1 rare, 3 ultra (legendaries)
SETS = [
  {
    "name": "Emberfall", "element": "fire",
    "lines3": [
      ["Emberpup", "Cinderhound", "Pyrewolf"],
      ["Pebblit", "Boulderkin", "Magmalith"],
      ["Wickling", "Candloth", "Infernaya"],
      ["Emberchick", "Blazecrow", "Cindraven"],
      ["Flintling", "Scorchmaw", "Vulcanine"],
      ["Emberling", "Scaldrake", "Pyrothraxx"],
    ],
    "lines2": [
      ["Ashling", "Cendrake"], ["Flicktail", "Emberdon"], ["Sootcub", "Charbruin"],
      ["Smoldfin", "Searpike"], ["Kindlebug", "Flarebeetle"], ["Emberkit", "Flarelynx"],
      ["Torchbud", "Bloomfire"],
    ],
    "singles_common": ["Sootmoth","Coalcrab","Wispfox","Flarebud","Torchfin","Ashhare",
                       "Cindermite","Smokewisp","Charsnail","Emberfly","Warmtoad","Glowmoth"],
    "singles_uncommon": ["Magmaw","Blazehorn"],
    "singles_rare": ["Obsidra"],
    "singles_ultra": ["Ignarok","Solmyr","Emberyx"],
    "second_element": "rock",
    "rock_names": {"Pebblit","Boulderkin","Magmalith","Coalcrab","Charsnail","Obsidra"},
  },
  {
    "name": "Tidecaller", "element": "water",
    "lines3": [
      ["Dripling","Splashound","Tidalwolf"],
      ["Frostnib","Glacikin","Glacialith"],
      ["Bubblet","Coralad","Reeflord"],
      ["Mistchick","Fogcrane","Vaporegal"],
      ["Snowpup","Frostmaw","Blizzardine"],
      ["Rilling","Streamsnout","Torrentyx"],
    ],
    "lines2": [
      ["Puddlit","Marshark"],["Icktail","Frostdon"],["Sleetcub","Chillbruin"],
      ["Minnowisp","Anglerfright"],["Krillbug","Nautibeetle"],["Frostkit","Rimelynx"],
      ["Kelpbud","Bloomtide"],
    ],
    "singles_common": ["Dewmoth","Icecrab","Mistfox","Foambud","Coldfin","Snowhare",
                       "Frostmite","Vaporwisp","Shellsnail","Brinefly","Chilltoad","Glowjelly"],
    "singles_uncommon": ["Maelmaw","Frosthorn"],
    "singles_rare": ["Nacreon"],
    "singles_ultra": ["Abyssos","Glaciera","Maelstros"],
  },
  {
    "name": "Verdspire", "element": "grass",
    "lines3": [
      ["Seedling","Sprouthound","Thornwolf"],
      ["Budnib","Bloomkin","Bloomalith"],
      ["Vinelet","Bramblad","Canopylord"],
      ["Sporechick","Mosscrane","Verduregal"],
      ["Leafpup","Thornmaw","Sylvandine"],
      ["Rootling","Barksnout","Titanyx"],
    ],
    "lines2": [
      ["Spriglit","Bramblark"],["Ivytail","Petaldon"],["Ferncub","Timberbruin"],
      ["Tadseed","Lilypike"],["Aphidbug","Beetlebloom"],["Sporekit","Mosslynx"],
      ["Seedbud","Bloomthicket"],
    ],
    "singles_common": ["Pollmoth","Barkcrab","Fernfox","Petalbud","Reedfin","Cloverhare",
                       "Sporemite","Pollenwisp","Vinesnail","Dewfly","Mosstoad","Glowspore"],
    "singles_uncommon": ["Bramblehorn","Saproot"],
    "singles_rare": ["Verdanox"],
    "singles_ultra": ["Sylvareth","Floreon","Eldwyrm"],
  },
  {
    "name": "Voltcrest", "element": "electric",
    "lines3": [
      ["Sparkpup","Volthound","Thunderwolf"],
      ["Zapnib","Boltkin","Fulgralith"],
      ["Statlet","Arclad","Stormlord"],
      ["Fizzchick","Wattcrane","Voltregal"],
      ["Joltpup","Surgemaw","Galvandine"],
      ["Currentling","Coilsnout","Teslyx"],
    ],
    "lines2": [
      ["Buzzlit","Sparkshark"],["Ziptail","Voltdon"],["Staticub","Thunderbruin"],
      ["Sparkfin","Zappike"],["Mothbolt","Beetlesurge"],["Joltkit","Arclynx"],
      ["Sparkbud","Boltthicket"],
    ],
    "singles_common": ["Zapmoth","Voltcrab","Sparkfox","Fizzbud","Wattfin","Bolthare",
                       "Staticmite","Ozonewisp","Coilsnail","Amperefly","Buzztoad","Glowvolt"],
    "singles_uncommon": ["Surgehorn","Dynamaw"],
    "singles_rare": ["Voltanox"],
    "singles_ultra": ["Fulguros","Tempesta","Voltaeon"],
  },
  {
    "name": "Umbral Reach", "element": "shadow",
    "lines3": [
      ["Duskpup","Shadowhound","Nightwolf"],
      ["Voidnib","Umbrakin","Voidalith"],
      ["Gloamlet","Shadelad","Eclipselord"],
      ["Wispchick","Nebulacrane","Astregal"],
      ["Shadepup","Diremaw","Umbrandine"],
      ["Riftling","Starsnout","Cosmyx"],
    ],
    "lines2": [
      ["Murklit","Voidshark"],["Shadetail","Umbradon"],["Gloomcub","Nightbruin"],
      ["Inkfin","Voidpike"],["Mothshade","Beetlevoid"],["Duskkit","Shadelynx"],
      ["Starbud","Voidthicket"],
    ],
    "singles_common": ["Duskmoth","Voidcrab","Shadefox","Gloombud","Darkfin","Umbrahare",
                       "Shademite","Netherwisp","Voidsnail","Cometfly","Murktoad","Glowshade"],
    "singles_uncommon": ["Nebulahorn","Riftmaw"],
    "singles_rare": ["Umbranox"],
    "singles_ultra": ["Nyxaros","Astralon","Eclipsar"],
  },
]

FLAVOR = {
  "fire": ["Its footprints smoulder for hours.","Warms the coldest winter cave.","A tail-flame that never gutters.",
    "Sneezes send up little sparks.","Said to nap inside active volcanoes.","Its heartbeat glows through its hide.",
    "Embers drift wherever it wanders.","Hot enough to boil a river dry.","Molten eyes see through smoke.",
    "Legends say it was born of the first flame.","Its roar melts steel.","Dreams in shades of orange and gold."],
  "rock": ["Older than the mountains it climbs.","Sleeps as still as a boulder.","Its shell turns aside avalanches.",
    "Grinds gemstones between its teeth.","Moves once a century, they say.","Skin like cooled lava.",
    "Weighs more than it has any right to.","Cracks the earth where it treads."],
  "water": ["Rides the tide by moonlight.","Its song calms the roughest sea.","Breathes in mist and out in rain.",
    "Colder than the deepest trench.","Scales shimmer like wet pearl.","Follows sailors home for company.",
    "Its wake freezes into lace.","Dives where light cannot reach.","Weeps salt when the ocean is far.",
    "Dances in the surf at dawn.","A single tear can fill a well.","Whispers of drowned kingdoms."],
  "grass": ["Blooms only under a full moon.","Its breath smells of spring rain.","Roots itself to nap in the sun.",
    "Petals close at the first frost.","Grows a new leaf with each friend made.","Older forests hum when it passes.",
    "Seeds ride the wind for miles.","Its shadow makes flowers grow.","Tends the woodland while others sleep.",
    "Sap sweet enough to lure bees.","A garden follows in its footsteps.","Green as the first day of the world."],
  "electric": ["Charges the air before a storm.","Its purr crackles with static.","Powers a village when it sleeps.",
    "Faster than the lightning it rides.","Hair stands on end near it.","Sparks leap from its whiskers.",
    "Hums the note of a live wire.","Its eyes flicker like a busted bulb.","Storms gather where it plays.",
    "Never needs to be plugged in.","A single touch can light a lantern.","Dances along power lines at night."],
  "shadow": ["Slips between one moment and the next.","Its eyes hold a piece of the night sky.","Casts no shadow of its own.",
    "Feeds on starlight and secrets.","Colder where it has recently stood.","Walks through walls when unwatched.",
    "Born in the space between stars.","Its whisper sounds like distant thunder.","Fades at dawn, returns at dusk.",
    "Older than the dark it came from.","Dreams leak out of it as fog.","Where it sleeps, the stars go dim."],
}

BANDS = {  # Set-1 base bands (min, max); scaled per set
  "common":   (0.25, 0.90),
  "uncommon": (1.00, 2.75),
  "rare":     (3.00, 7.50),
  "ultra":    (9.00, 25.00),
}
SCALE = [1, 2, 4, 7, 12]           # per set value/price multiplier (pre-normalization magnitude)
PACK_PRICE = [10, 20, 40, 70, 120] # per set
OUTLIERS = {"common": 2, "uncommon": 2, "rare": 1, "ultra": 1}

# Target pack expected value as a multiple of the pack price, per set. The base
# values of a set are normalized so the average pack's base-value contents equal
# EV_TARGET x price. Later sets pay back less relative to their (much larger)
# price, forming a deliberate risk curve. Foils (~+2%) and opt-in grading are
# upside on top of this.
EV_TARGET = [1.50, 1.25, 1.10, 1.00, 0.90]

# Stable per-rarity RNG offsets. (Replaces Python's per-process-salted hash(),
# which made card values non-deterministic across runs.)
RARITY_SEED = {"common": 11, "uncommon": 23, "rare": 37, "ultra": 51}

def elem_of(card_name, s):
    if s.get("rock_names") and card_name in s["rock_names"]:
        return s["second_element"]
    return s["element"]

def flavor_for(name, element):
    pool = FLAVOR[element]
    return pool[sum(ord(c) for c in name) % len(pool)]

def assign_values(cards, set_idx):
    """Assign baseValue per card within its scaled band, with 1-2 high outliers/tier.
    Values are left unrounded here; normalize_set_ev scales then rounds them."""
    scale = SCALE[set_idx]
    by_rarity = {}
    for c in cards:
        by_rarity.setdefault(c["rarity"], []).append(c)
    for rarity, group in by_rarity.items():
        a, b = BANDS[rarity]
        a, b = a * scale, b * scale
        R = b - a
        idxs = list(range(len(group)))
        rng = random.Random(1000 * set_idx + RARITY_SEED[rarity])
        rng.shuffle(idxs)
        outlier_set = set(idxs[:OUTLIERS[rarity]])
        for i, c in enumerate(group):
            if i in outlier_set:
                frac = rng.uniform(0.80, 1.00)
            else:
                frac = rng.uniform(0.05, 0.35)
            c["baseValue"] = a + R * frac

def pack_base_ev(cards):
    """Expected base-value of one pack from a set: 3 common + 2 uncommon +
    1 hit (80% rare / 20% ultra). Base values only (foil/grade are upside)."""
    def avg(r):
        v = [c["baseValue"] for c in cards if c["rarity"] == r]
        return sum(v) / len(v)
    return 3 * avg("common") + 2 * avg("uncommon") + 0.8 * avg("rare") + 0.2 * avg("ultra")

def normalize_set_ev(cards, set_idx):
    """Uniformly scale a set's base values so the pack's base-value EV equals
    EV_TARGET x price, then round to cents. Uniform scaling shifts only the mean,
    preserving relative spread, outliers, and non-overlapping tiers."""
    target = EV_TARGET[set_idx] * PACK_PRICE[set_idx]
    f = target / pack_base_ev(cards)
    for c in cards:
        c["baseValue"] = round(c["baseValue"] * f, 2)

def build():
    all_cards = []
    for set_idx, s in enumerate(SETS):
        set_no = set_idx + 1
        ordered = []  # (name, rarity, line_id, stage, stage_count)
        # 3-stage lines
        for li, line in enumerate(s["lines3"]):
            lid = f"S{set_no}-E3-{li+1}"
            for st, nm in enumerate(line):
                rarity = ["common", "uncommon", "rare"][st]
                ordered.append((nm, rarity, lid, st + 1, 3))
        # 2-stage lines
        for li, line in enumerate(s["lines2"]):
            lid = f"S{set_no}-E2-{li+1}"
            for st, nm in enumerate(line):
                rarity = ["common", "uncommon"][st]
                ordered.append((nm, rarity, lid, st + 1, 2))
        # singles
        def add_singles(names, rarity):
            for nm in names:
                ordered.append((nm, rarity, f"S{set_no}-S-{nm}", 1, 1))
        add_singles(s["singles_common"], "common")
        add_singles(s["singles_uncommon"], "uncommon")
        add_singles(s["singles_rare"], "rare")
        add_singles(s["singles_ultra"], "ultra")

        set_cards = []
        for i, (nm, rarity, lid, stage, sc) in enumerate(ordered):
            number = i + 1
            cid = f"S{set_no}-{number:03d}"
            element = elem_of(nm, s)
            set_cards.append({
                "id": cid, "set": set_no, "number": number, "name": nm,
                "element": element, "rarity": rarity, "lineId": lid,
                "stage": stage, "stageCount": sc,
                "evolvesFromId": None, "evolvesToId": None,
                "flavor": flavor_for(nm, element),
            })
        # link evolutions by lineId order
        by_line = {}
        for c in set_cards:
            by_line.setdefault(c["lineId"], []).append(c)
        for lid, chain in by_line.items():
            chain.sort(key=lambda c: c["stage"])
            for j, c in enumerate(chain):
                if j > 0:
                    c["evolvesFromId"] = chain[j - 1]["id"]
                if j < len(chain) - 1:
                    c["evolvesToId"] = chain[j + 1]["id"]
        assign_values(set_cards, set_idx)
        normalize_set_ev(set_cards, set_idx)
        all_cards.extend(set_cards)
    return all_cards

def validate(cards):
    errs = []
    if len(cards) != 250:
        errs.append(f"expected 250 cards, got {len(cards)}")
    names = [c["name"] for c in cards]
    if len(set(names)) != len(names):
        dupes = sorted({n for n in names if names.count(n) > 1})
        errs.append(f"duplicate names: {dupes}")
    ids = [c["id"] for c in cards]
    if len(set(ids)) != len(ids):
        errs.append("duplicate ids")
    for set_no in range(1, 6):
        sc = [c for c in cards if c["set"] == set_no]
        counts = {r: sum(1 for c in sc if c["rarity"] == r) for r in ["common","uncommon","rare","ultra"]}
        if counts != {"common":25,"uncommon":15,"rare":7,"ultra":3}:
            errs.append(f"set {set_no} rarity counts wrong: {counts}")
        # non-overlapping bands: max(tier) < min(next tier)
        order = ["common","uncommon","rare","ultra"]
        maxes = {r: max((c["baseValue"] for c in sc if c["rarity"] == r), default=0) for r in order}
        mins  = {r: min((c["baseValue"] for c in sc if c["rarity"] == r), default=0) for r in order}
        for lo, hi in zip(order, order[1:]):
            if not maxes[lo] < mins[hi]:
                errs.append(f"set {set_no}: {lo} max {maxes[lo]} !< {hi} min {mins[hi]}")
        # 1-2 outliers per tier: top value strictly above 2nd-highest by a margin
        for r in order:
            vals = sorted((c["baseValue"] for c in sc if c["rarity"] == r), reverse=True)
            if len(vals) >= 3 and not vals[0] > vals[-1]:
                errs.append(f"set {set_no} {r}: no spread")
    # evolution integrity
    idmap = {c["id"]: c for c in cards}
    for c in cards:
        if c["evolvesToId"] and c["evolvesToId"] not in idmap:
            errs.append(f"{c['id']} bad evolvesToId")
        if c["evolvesFromId"] and c["evolvesFromId"] not in idmap:
            errs.append(f"{c['id']} bad evolvesFromId")
    return errs

def economy_report(cards):
    print("\n=== Economy report (pack EV vs price) ===")
    ok = True
    for set_idx in range(5):
        set_no = set_idx + 1
        sc = [c for c in cards if c["set"] == set_no]
        base_ev = pack_base_ev(sc)
        price = PACK_PRICE[set_idx]
        target = EV_TARGET[set_idx]
        ratio = base_ev / price
        realized = base_ev * 1.02  # ~1% foil chance per card adds ~+2% on top
        flag = "" if abs(ratio - target) <= 0.02 else "  <-- OFF TARGET"
        print(f"Set {set_no} {SETS[set_idx]['name']:<13} price ${price:<4} "
              f"base EV ${base_ev:7.2f}  ratio {ratio:.3f} (target {target:.2f})"
              f"  realized ~${realized:7.2f}{flag}")
        if abs(ratio - target) > 0.02:
            ok = False
    return ok

def swift_literal(c):
    def s(x): return "nil" if x is None else f"\"{x}\""
    fl = c["flavor"].replace("\"", "\\\"")
    return (f'    Card(id: "{c["id"]}", set: {c["set"]}, number: {c["number"]}, '
            f'name: "{c["name"]}", element: .{c["element"]}, rarity: .{c["rarity"]}, '
            f'lineId: "{c["lineId"]}", stage: {c["stage"]}, stageCount: {c["stageCount"]}, '
            f'evolvesFromId: {s(c["evolvesFromId"])}, evolvesToId: {s(c["evolvesToId"])}, '
            f'baseValue: {c["baseValue"]}, flavor: "{fl}"),')

def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cards = build()
    errs = validate(cards)
    econ_ok = economy_report(cards)
    if errs:
        print("\nVALIDATION FAILED:")
        for e in errs:
            print("  -", e)
        sys.exit(1)
    if not econ_ok:
        print("\nECONOMY OUT OF RANGE")
        sys.exit(2)

    with open(os.path.join(root, "data", "cards.json"), "w") as f:
        json.dump(cards, f, indent=2)

    lines = ["// AUTO-GENERATED by tools/generate_cards.py — do not edit by hand.",
             "import Foundation", "",
             "extension CardDatabase {", "    static let all: [Card] = ["]
    lines += [swift_literal(c) for c in cards]
    lines += ["    ]", "}", ""]
    with open(os.path.join(root, "TradingUp", "Generated", "CardData.swift"), "w") as f:
        f.write("\n".join(lines))

    print(f"\nOK: generated {len(cards)} cards -> data/cards.json + TradingUp/Generated/CardData.swift")

if __name__ == "__main__":
    main()
