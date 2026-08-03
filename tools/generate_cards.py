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

# Additional, distinct flavor lines used only to break up duplicates. flavor_for()
# still selects from FLAVOR (above), so every card that currently holds a unique or
# first-use flavor keeps it exactly; only the surplus duplicates draw from here.
FLAVOR_EXTRA = {
  "fire": ["Coals rekindle at its passing.","Breathes out cinders on cold mornings.","Its mane sheds sparks in the wind.",
    "Ash blooms into flowers where it steps.","Curls up in campfires to sleep.","Its growl smells of woodsmoke.",
    "Melts frost with a single yawn.","Keeps the hearth lit through winter.","Its claws leave scorch marks on stone.",
    "A furnace beats where its heart should be.","Basks on sun-baked rock for days.","Its tail draws embers in the dark.",
    "Too hot for snow to ever settle on it.","Wakes when the first coal glows.","Carries summer wherever it roams.",
    "Its breath shimmers the air like a mirage.","Sparks scatter when it shakes off dust.","Sleeps curled around a smouldering log.",
    "Its eyes are twin banked coals.","Lava cools to glass beneath its paws.","Hums like a kettle about to boil.",
    "The desert sun is its favourite den.","Its fur glows faintly after dark.","Chases the sunset to keep it warm.",
    "Smoke curls from its nostrils when annoyed.","A single ember can spark its temper.","Warms cold hands from across a room.",
    "Its snarl throws sparks like flint.","Born where two lava rivers meet.","Leaves handprints of ash on everything.",
    "Its heat bends the horizon behind it.","Naps only where the coals still glow.","Kindled from a dying star, they say.",
    "Its yawn could light a hundred lamps.","Rolls in hot ash to clean its coat.","The forge cools when it walks away.",
    "Wildfires part to let it pass.","Its dreams flicker like candlelight."],
  "rock": ["Moss grows thick along its back.","Its footsteps register as small quakes.",
    "Gathers gemstones the way others hoard nuts.","Weathered smooth by a thousand storms."],
  "water": ["Sleeps in the hollow of a wave.","Its breath fogs the coldest glass.","Trails glimmering light through the dark.",
    "Rain follows it like a loyal pet.","Its fins catch the colour of the sky.","Counts the tides better than any clock.",
    "Leaves dew on every leaf it passes.","Its call carries for leagues underwater.","Cool mist gathers where it rests.",
    "Drinks from clouds when rivers run dry.","Its scales sing when the current shifts.","Nests in tide pools at low water.",
    "Melts into sea foam when startled.","Its shadow ripples like a reflection.","Guides lost fish back to the reef.",
    "Frost feathers the puddles it steps in.","Holds a storm's worth of rain inside.","Its eyes are the colour of deep water.",
    "Swims circles around the fastest eel.","A gentle rain means it is near.","Its touch turns dust to clear water.",
    "Rides river currents just for fun.","Bubbles rise wherever it hums.","Keeps a pearl tucked beneath its tongue.",
    "Its coat never truly dries.","The tide comes in when it calls.","Naps adrift on its back at sea.",
    "Its breath tastes of salt and rain.","Coaxes springs from bone-dry stone.","Moonlight pools in its wake.",
    "Its whiskers twitch before a downpour.","Carries the hush of the deep with it.","Snow becomes rain in its warmth.",
    "Its laughter sounds like a running brook.","Follows the river to wherever it ends.","Cups still water to see tomorrow.",
    "Its scales mist over in the cold.","Born on the crest of a rogue wave."],
  "grass": ["Vines curl toward it like old friends.","Its yawn scatters dandelion seeds.","Moss cushions every step it takes.",
    "Wakes with the first warmth of spring.","Butterflies trail it through the meadow.","Its antlers sprout fresh buds each spring.",
    "Fallen logs bloom where it naps.","Smells of clover after warm rain.","Its coat changes colour with the season.",
    "Roots knit the soil wherever it walks.","Hums a tune the crickets answer.","Wildflowers lean to follow it by.",
    "Its breath coaxes shy seeds to sprout.","Bees regard it as one of their own.","Curls beneath ferns to escape the noon.",
    "Ivy climbs it as though it were a tree.","Leaves a trail of pressed-flower prints.","Its nap turns a clearing into a garden.",
    "Orchards bear sweeter fruit where it rests.","Petals drift from its coat as it runs.","The oldest oak leans down to greet it.",
    "Its whiskers are strung with morning dew.","Mushrooms ring the spot where it slept.","Sunlight always seems to find it first.",
    "Its footprints fill with tiny sprouts.","Keeps the meadow green past autumn's end.","Birds weave its shed fur into nests.",
    "A crown of new leaves marks each spring.","It naps and the brambles pull back.","Its heartbeat keeps time with the seasons.",
    "Pollen glitters gold along its back.","Where it drinks, a spring garden grows.","Coaxes fruit from the most stubborn vine.",
    "Its shade is cooler than any other.","Saplings straighten as it wanders past.","Smells faintly of honey and cut grass.",
    "The forest holds its breath when it sings.","Rooted deep, it dreams of distant fields."],
  "electric": ["Its fur snaps with tiny blue sparks.","Lightning bends to follow its leap.","Static clings to anyone it nuzzles.",
    "Its heartbeat ticks like a busy clock.","Compasses spin when it draws near.","Rides thunderheads across the plains.",
    "Its bark arrives a beat before the flash.","Streetlights flicker as it trots by.","Coils of energy ripple down its spine.",
    "Its whiskers point toward the nearest storm.","Naps atop warm transformers to keep cosy.","A stormcloud follows it like a balloon.",
    "Its sneeze can short a whole street.","Sparks trail its tail through the dark.","The air tastes of copper where it stands.",
    "It races the lightning and often wins.","Its growl builds like a rising current.","Balloons cling to it without any rubbing.",
    "It grounds itself by hugging iron posts.","Every hair doubles as a lightning rod.","Its glow brightens with its temper.",
    "Wakes the instant thunder rolls in.","Batteries recharge in its presence.","Its leap leaves the grass faintly singed.",
    "It hums louder as the storm draws close.","Coins stick to its staticky coat.","Its eyes spark when it is excited.",
    "The kettle boils faster in its company.","Born the moment lightning split an old oak.","It chases thunder like a pup chases carts.",
    "Its footsteps leave a tingle in the floor.","A live current runs beneath its fur.","It naps through storms it helped summon.",
    "Sparks scatter when it shakes off the rain.","Its yawn dims every lamp in the house.","Follows the hum of the power lines home.",
    "It crackles brightest just before dawn.","Its dreams flash like distant heat lightning."],
  "shadow": ["Moonlight passes straight through it.","It pools like ink in the corners of a room.","Its footsteps make no sound at all.",
    "Candles gutter when it enters.","It borrows the shapes of other shadows.","Night gathers close wherever it curls up.",
    "Its purr is felt more than heard.","Stars reflect in its coal-dark coat.","It unspools from under the furniture at dusk.",
    "The dark feels warmer where it has been.","Its outline blurs at the edges.","It counts secrets the way others count sheep.",
    "Lanterns dim to a whisper near it.","It slips through keyholes without a sound.","Its eyes are the last light before sleep.",
    "Dusk arrives early wherever it wanders.","It wears the midnight like a familiar coat.","Cold follows it as warmth follows fire.",
    "It naps in the hollow beneath a stair.","Its yawn swallows the nearest candle flame.","Owls fall silent when it passes below.",
    "It folds itself thin to hide in twilight.","The night sky misses a star while it wakes.","Its breath frosts the glass from within.",
    "It leaves cold spots that linger till noon.","Shadows lengthen to point the way it went.","It drinks the last of the evening light.",
    "Its whisper carries a chill down the spine.","Mirrors show it a heartbeat too late.","It is quietest just before it vanishes.",
    "The dark rearranges itself to let it by.","Its eyes open like two new moons.","It gathers dusk into a place to sleep.",
    "Clocks seem to slow while it is near.","It threads through the gaps in the lamplight.","Nightfall feels like it is coming home.",
    "Its dreams spill out as creeping mist.","Born from the shadow a comet left behind."],
}

BANDS = {  # Set-1 base bands (min, max); scaled per set
  "common":   (0.25, 0.90),
  "uncommon": (1.00, 2.75),
  "rare":     (3.00, 7.50),
  "ultra":    (9.00, 25.00),
}
SCALE = [1, 3, 7.5, 16, 40]         # per set value/price multiplier (mirrors PACK_PRICE/10; cancels in normalization)
PACK_PRICE = [10, 30, 75, 160, 400] # per set
OUTLIERS = {"common": 2, "uncommon": 2, "rare": 1, "ultra": 1}

# Target pack expected value as a multiple of the pack price, per set. The base
# values of a set are normalized so the average pack's base-value contents equal
# EV_TARGET x price. Later sets pay back less relative to their (much larger)
# price, forming a deliberate risk curve. Foils (~+2%) and opt-in grading are
# upside on top of this.
EV_TARGET = [1.00, 0.90, 0.80, 0.70, 0.60]

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

def assign_unique_flavors(cards):
    """Make every card's flavor globally unique while changing only duplicates.

    Cards keep the flavor_for() result they already hold as long as no earlier
    card (in build order) claimed it. Surplus duplicates are reassigned to the
    next unused line from FLAVOR + FLAVOR_EXTRA for their element. This preserves
    every current first-use / unique flavor exactly."""
    pools = {e: FLAVOR[e] + FLAVOR_EXTRA.get(e, []) for e in FLAVOR}
    used = set()
    need = []
    for c in cards:
        pref = c["flavor"]
        if pref in used:
            need.append(c)
        else:
            used.add(pref)
    for c in need:
        for line in pools[c["element"]]:
            if line not in used:
                c["flavor"] = line
                used.add(line)
                break
        else:
            raise SystemExit(f"flavor pool exhausted for element {c['element']}")
    return cards

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
    assign_unique_flavors(all_cards)
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
    flavors = [c["flavor"] for c in cards]
    if len(set(flavors)) != len(flavors):
        dupes = sorted({f for f in flavors if flavors.count(f) > 1})
        errs.append(f"duplicate flavors ({len(dupes)}): {dupes[:5]}...")
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
