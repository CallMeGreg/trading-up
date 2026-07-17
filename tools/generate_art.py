#!/usr/bin/env python3
"""Mythling card art — deterministic creature illustrations for all 250 cards.

Sets are perfectly parallel (same 13 evolution lines + 18 singles in the same
structural roles), so we define one creature archetype per slot and restyle it per
element (palette + accents) + per-set scene + evolution stage. The 15 ultra
legendaries are bespoke. Art is name-aligned: the archetype for each slot matches
the card names (canine line -> pup/hound/wolf, etc.).

Commands (needs `rsvg-convert` from librsvg: `brew install librsvg`):
  python3 tools/generate_art.py assets   # (re)render the 250 card assets + mockup SVGs
  python3 tools/generate_art.py qa [n]    # QA contact sheet(s) to /tmp for review

Outputs:
  - asset PNGs  TradingUp/Assets.xcassets/CardArt/<id>.imageset/<id>.png  (864x600)
  - mockup SVGs design/mockups/art/<id>.svg
  - QA sheets   /tmp/qa_set{n}.png  (all 50 of a set in a grid)
The app (CardView) shows these via UIImage(named: card.id); SigilView is the fallback.
"""
import json, os, math, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.dirname(os.path.abspath(__file__))
VB_W, VB_H = 216, 150

# --------------------------------------------------------------- element palettes
ELE = {
    "fire":     dict(pal=["#ffe08a","#ff8a2a","#e01f1f","#4a0f04"], glow="#ffd15c", acc="fire"),
    "rock":     dict(pal=["#f4cf94","#c98a3c","#7a4a24","#2c1a0c"], glow="#ffcf8a", acc="rock"),
    "water":    dict(pal=["#c2f0ff","#4bb6ff","#1e5bd6","#08245c"], glow="#bff0ff", acc="water"),
    "grass":    dict(pal=["#dcffa8","#78dd63","#2f9e44","#123f1e"], glow="#eaffb4", acc="grass"),
    "electric": dict(pal=["#fff6b0","#ffd21a","#f5a300","#5a3d00"], glow="#fff6b0", acc="electric"),
    "shadow":   dict(pal=["#e2c8ff","#a06cf6","#5b2bb3","#160a2e"], glow="#ecd8ff", acc="shadow"),
}

def H(s):
    return int(hashlib.md5(s.encode()).hexdigest(), 16)

def vary(name):
    h = H(name)
    return dict(
        spots=(h & 3),                 # 0..3
        earv=(h >> 2) & 1,
        eyes=(2 if (h >> 3) & 7 == 0 else 2),  # mostly 2
        horns=1 + ((h >> 4) & 1),      # 1..2
        jitter=((h >> 5) & 7) - 3.5,   # -3.5..3.5
        flip=(h >> 8) & 1,
        seed=h,
    )

# ------------------------------------------------------------------------ helpers
def defs(uid, e):
    pal, glow = e["pal"], e["glow"]
    return f"""
  <defs>
    <linearGradient id="body{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="{pal[0]}"/><stop offset="55%" stop-color="{pal[1]}"/>
      <stop offset="100%" stop-color="{pal[2]}"/>
    </linearGradient>
    <linearGradient id="body2{uid}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="{pal[1]}"/><stop offset="100%" stop-color="{pal[3]}"/>
    </linearGradient>
    <linearGradient id="belly{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#ffffff" stop-opacity=".92"/><stop offset="100%" stop-color="{pal[0]}"/>
    </linearGradient>
    <radialGradient id="stage{uid}" cx="50%" cy="62%" r="55%">
      <stop offset="0%" stop-color="{glow}" stop-opacity=".55"/><stop offset="70%" stop-color="{glow}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="orb{uid}" cx="42%" cy="38%" r="65%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity=".95"/>
      <stop offset="45%" stop-color="{pal[0]}"/><stop offset="100%" stop-color="{pal[2]}"/>
    </radialGradient>
  </defs>"""

def eye(cx, cy, r, glow="#fff", look=0.6, angry=False, glowy=False):
    base = glow if glowy else "#ffffff"
    pupil = "#1a1020"
    s = f'<ellipse cx="{cx}" cy="{cy}" rx="{r}" ry="{r*1.14}" fill="{base}"/>'
    s += f'<circle cx="{cx+look}" cy="{cy+r*0.12}" r="{r*0.6}" fill="{pupil}"/>'
    s += f'<circle cx="{cx-r*0.24+look}" cy="{cy-r*0.36}" r="{r*0.24}" fill="#fff"/>'
    if angry:
        s += f'<path d="M{cx-r*1.3},{cy-r*1.5} L{cx+r*1.1},{cy-r*0.5}" stroke="{pupil}" stroke-width="{r*0.5}" stroke-linecap="round"/>'
    return s

def star(x, y, r, c="#fff", op=0.9):
    return (f'<path d="M{x},{y-r} L{x+r*0.28},{y-r*0.28} L{x+r},{y} L{x+r*0.28},{y+r*0.28} '
            f'L{x},{y+r} L{x-r*0.28},{y+r*0.28} L{x-r},{y} L{x-r*0.28},{y-r*0.28} Z" fill="{c}" opacity="{op}"/>')

# ---- element accent motif: a small decorative "tuft" pointing up at (cx,cy) ----
def tuft(el, cx, cy, s, e, rot=0):
    pal, glow, stroke = e["pal"], e["glow"], e["pal"][3]
    g = f'<g transform="rotate({rot} {cx} {cy})" stroke="{stroke}" stroke-width="1.1" stroke-linejoin="round">'
    a = el
    if a == "fire":
        g += (f'<path d="M{cx},{cy+s} C{cx-0.8*s},{cy+0.2*s} {cx-0.5*s},{cy-0.4*s} {cx},{cy-s} '
              f'C{cx+0.5*s},{cy-0.4*s} {cx+0.8*s},{cy+0.2*s} {cx},{cy+s} Z" fill="{glow}"/>')
        g += (f'<path d="M{cx},{cy+0.5*s} C{cx-0.4*s},{cy+0.1*s} {cx-0.25*s},{cy-0.25*s} {cx},{cy-0.6*s} '
              f'C{cx+0.25*s},{cy-0.25*s} {cx+0.4*s},{cy+0.1*s} {cx},{cy+0.5*s} Z" fill="{pal[1]}" stroke="none"/>')
    elif a == "water":
        g += f'<path d="M{cx},{cy-s} L{cx+0.72*s},{cy+s} Q{cx},{cy+0.45*s} {cx-0.72*s},{cy+s} Z" fill="{pal[0]}"/>'
        g += f'<line x1="{cx}" y1="{cy-0.5*s}" x2="{cx}" y2="{cy+0.7*s}" stroke="{pal[2]}" stroke-width="0.9"/>'
    elif a == "grass":
        g += f'<path d="M{cx},{cy-s} Q{cx+0.7*s},{cy} {cx},{cy+s} Q{cx-0.7*s},{cy} {cx},{cy-s} Z" fill="{pal[0]}"/>'
        g += f'<line x1="{cx}" y1="{cy-0.7*s}" x2="{cx}" y2="{cy+0.7*s}" stroke="{pal[2]}" stroke-width="0.9"/>'
    elif a == "electric":
        g += (f'<polygon points="{cx-0.2*s},{cy-s} {cx+0.5*s},{cy-s} {cx+0.05*s},{cy-0.05*s} '
              f'{cx+0.45*s},{cy-0.05*s} {cx-0.35*s},{cy+s} {cx-0.02*s},{cy+0.05*s} {cx-0.5*s},{cy+0.05*s} {cx},{cy-0.2*s}" '
              f'fill="{glow}"/>')
    elif a == "rock":
        g += f'<path d="M{cx},{cy-s} L{cx+0.55*s},{cy-0.1*s} L{cx},{cy+s} L{cx-0.55*s},{cy-0.1*s} Z" fill="{pal[0]}"/>'
        g += f'<line x1="{cx}" y1="{cy-s}" x2="{cx}" y2="{cy+s}" stroke="{pal[2]}" stroke-width="0.8"/>'
    else:  # shadow
        g += star(cx, cy, s, glow, 1)
        g = g.replace("<path", '<path stroke="'+stroke+'" stroke-width="1"', 1)
    return g + "</g>"

def spots(el, pts, e):
    """small surface marks appropriate to the element at [(x,y,r),...]"""
    pal, glow = e["pal"], e["glow"]
    out = ""
    for (x, y, r) in pts:
        if el == "shadow":
            out += star(x, y, r*1.2, glow, .9)
        elif el == "electric":
            out += star(x, y, r*1.1, glow, .85)
        elif el == "grass":
            out += f'<path d="M{x},{y-r} Q{x+r},{y} {x},{y+r} Q{x-r},{y} {x},{y-r} Z" fill="{pal[3]}" opacity=".5"/>'
        elif el == "water":
            out += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{pal[0]}" opacity=".6"/>'
        elif el == "rock":
            out += f'<path d="M{x},{y-r} L{x+r*.6},{y} L{x},{y+r} L{x-r*.6},{y} Z" fill="{pal[3]}" opacity=".45"/>'
        else:  # fire ember
            out += f'<circle cx="{x}" cy="{y}" r="{r}" fill="{glow}" opacity=".7"/>'
    return out

# --------------------------------------------------------------------------- scenes
def scene_fire(uid):
    return f"""
  <defs>
    <linearGradient id="sky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#3a0d05"/><stop offset="55%" stop-color="#7a1c06"/><stop offset="100%" stop-color="#20060a"/>
    </linearGradient>
    <radialGradient id="lava{uid}" cx="50%" cy="100%" r="80%">
      <stop offset="0%" stop-color="#ffd15c"/><stop offset="35%" stop-color="#ff6a1a"/><stop offset="100%" stop-color="#7a1c06" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  <path d="M0,150 L0,96 L34,110 L70,88 L104,104 L150,86 L186,106 L216,92 L216,150 Z" fill="#2a0a06"/>
  <path d="M56,150 L56,74 L74,56 L92,150 Z M150,150 L142,68 L162,52 L182,150 Z" fill="#1c0705" opacity=".8"/>
  <g stroke="#ff7a1a" stroke-width="1" opacity=".5" fill="none">
    <path d="M28,150 L34,120 L28,104 L38,84"/><path d="M120,150 L116,118 L126,100"/><path d="M176,150 L172,120 L182,102"/>
  </g>
  <rect x="0" y="118" width="{VB_W}" height="32" fill="url(#lava{uid})"/>
  <path d="M0,150 L0,138 Q54,128 108,138 T216,136 L216,150 Z" fill="#ffb24d" opacity=".9"/>
  <path d="M0,150 L0,144 Q54,136 108,144 T216,142 L216,150 Z" fill="#fff0b0" opacity=".7"/>
  {''.join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#ffcf6a" opacity="{op}"/>' for x,y,r,op in [(30,52,1.8,.9),(70,34,1.3,.8),(120,60,1.6,.85),(160,30,1.2,.7),(188,66,1.7,.8),(50,84,1.2,.7),(96,26,1.1,.7)])}
  <ellipse cx="108" cy="118" rx="86" ry="30" fill="url(#stage{uid})"/>"""

def scene_water(uid):
    rays = ""
    for x, w in [(24,16),(70,22),(120,14),(168,26)]:
        rays += f'<polygon points="{x},0 {x+w},0 {x+w+34},150 {x+18},150" fill="#bfeaff" opacity=".08"/>'
    bubbles = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#dff6ff" opacity="{op}"/>' for x,y,r,op in
                      [(34,44,2.4,.5),(58,80,1.6,.4),(180,40,2.8,.5),(150,96,1.8,.4),(196,110,2.2,.45),(90,30,1.4,.4),(120,120,1.6,.4)])
    return f"""
  <defs>
    <linearGradient id="sky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#0e5aa8"/><stop offset="55%" stop-color="#0b336e"/><stop offset="100%" stop-color="#03102e"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  {rays}
  <path d="M0,150 L0,120 Q40,132 78,122 Q120,110 150,124 Q186,136 216,122 L216,150 Z" fill="#06255a"/>
  <path d="M0,150 L0,134 Q52,144 108,134 T216,136 L216,150 Z" fill="#041a44"/>
  <g fill="#0a2f66" opacity=".9">
    <path d="M150,150 C150,128 140,120 146,110 C152,120 156,116 156,108 C162,120 160,132 166,150 Z"/>
    <path d="M40,150 C40,132 34,126 40,116 C46,126 48,122 50,116 C54,128 54,138 58,150 Z"/>
  </g>
  {bubbles}
  <ellipse cx="108" cy="86" rx="92" ry="46" fill="url(#stage{uid})"/>"""

def scene_grass(uid):
    shafts = ""
    for x, w in [(40,20),(96,26),(160,18)]:
        shafts += f'<polygon points="{x},0 {x+w},0 {x+w+26},150 {x+14},150" fill="#eaffb0" opacity=".10"/>'
    pollen = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#f6ffcf" opacity="{op}"/>' for x,y,r,op in
                     [(34,52,1.6,.7),(72,34,1.2,.6),(150,44,1.6,.65),(186,64,1.3,.6),(110,28,1.1,.6),(60,96,1.3,.6)])
    blades = "".join(f'<path d="M{x},150 C{x-3},{y} {x-1},{y-8} {x+2},{y-14}" stroke="#1c5a2a" stroke-width="3" fill="none" stroke-linecap="round"/>'
                     for x,y in [(12,120),(30,112),(190,116),(206,122),(150,126)])
    return f"""
  <defs>
    <linearGradient id="sky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#4fb85e"/><stop offset="50%" stop-color="#2c8a3e"/><stop offset="100%" stop-color="#0c2f16"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  <g fill="#1c5f2b" opacity=".85">
    <rect x="18" y="10" width="20" height="140" rx="10"/><rect x="176" y="4" width="24" height="146" rx="12"/>
  </g>
  <g fill="#134a20" opacity=".7">
    <ellipse cx="30" cy="20" rx="34" ry="20"/><ellipse cx="188" cy="14" rx="40" ry="22"/><ellipse cx="108" cy="6" rx="70" ry="18"/>
  </g>
  {shafts}
  <g fill="#2f9e44" opacity=".8">
    <path d="M46,10 q-10,10 -4,22 q10,-4 8,-20 Z"/><path d="M170,8 q10,10 4,22 q-10,-4 -6,-20 Z"/>
  </g>
  {pollen}
  <path d="M0,150 L0,128 Q54,140 108,130 T216,132 L216,150 Z" fill="#12451f"/>
  {blades}
  <ellipse cx="108" cy="96" rx="92" ry="44" fill="url(#stage{uid})"/>"""

def scene_electric(uid):
    bolts = ""
    for pts in ["150,2 138,40 150,40 132,86", "44,0 34,30 44,30 30,64"]:
        bolts += f'<polyline points="{pts}" fill="none" stroke="#fff29a" stroke-width="2" opacity=".35"/>'
    rain = "".join(f'<line x1="{x}" y1="{y}" x2="{x-4}" y2="{y+16}" stroke="#cfe0ff" stroke-width="1" opacity=".2"/>'
                   for x,y in [(30,20),(70,50),(110,10),(150,60),(190,30),(90,90),(200,90)])
    sparks = "".join(star(x,y,r,"#fff6b0",op) for x,y,r,op in [(60,40,2.4,.8),(170,52,2,.7),(120,30,2.2,.75),(48,96,1.8,.7),(196,100,2,.7)])
    return f"""
  <defs>
    <linearGradient id="sky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#2b2f45"/><stop offset="55%" stop-color="#3a3320"/><stop offset="100%" stop-color="#14140c"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  <g fill="#20233a" opacity=".9">
    <ellipse cx="50" cy="26" rx="52" ry="22"/><ellipse cx="150" cy="18" rx="60" ry="24"/><ellipse cx="200" cy="40" rx="40" ry="20"/>
  </g>
  {bolts}
  {rain}
  {sparks}
  <path d="M0,150 L0,126 Q54,138 108,128 T216,130 L216,150 Z" fill="#181812"/>
  <ellipse cx="108" cy="92" rx="92" ry="44" fill="url(#stage{uid})"/>"""

def scene_shadow(uid):
    stars = "".join(star(x,y,r,"#ffffff",op) for x,y,r,op in
                    [(26,26,2,.9),(64,14,1.4,.7),(96,34,1.7,.8),(140,18,1.3,.7),(178,30,2,.85),(200,60,1.5,.7),
                     (40,70,1.3,.6),(120,96,1.4,.6),(190,104,1.6,.7),(54,112,1.2,.6),(150,58,1.2,.6),(84,72,1.1,.6)])
    dust = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#cdb3ff" opacity="{op}"/>' for x,y,r,op in
                   [(48,44,1,.5),(150,40,1.2,.5),(180,80,1,.45),(70,100,1,.45)])
    return f"""
  <defs>
    <radialGradient id="sky{uid}" cx="52%" cy="40%" r="80%">
      <stop offset="0%" stop-color="#33195e"/><stop offset="55%" stop-color="#1a0d38"/><stop offset="100%" stop-color="#070316"/>
    </radialGradient>
    <radialGradient id="neb{uid}" cx="50%" cy="46%" r="42%">
      <stop offset="0%" stop-color="#8a5cf0" stop-opacity=".55"/><stop offset="100%" stop-color="#8a5cf0" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  <ellipse cx="108" cy="70" rx="96" ry="66" fill="url(#neb{uid})"/>
  {stars}
  {dust}
  <path d="M0,150 L0,132 Q54,142 108,133 T216,135 L216,150 Z" fill="#0b0620"/>
  <ellipse cx="108" cy="92" rx="92" ry="44" fill="url(#stage{uid})"/>"""

SCENES = {1: scene_fire, 2: scene_water, 3: scene_grass, 4: scene_electric, 5: scene_shadow}

# ------------------------------------------------------- structural role mapping
# (copied from tools/generate_cards.py so name -> slot/stage is exact, not guessed)
SETS = [
  {"element":"fire",
   "lines3":[["Emberpup","Cinderhound","Pyrewolf"],["Pebblit","Boulderkin","Magmalith"],
             ["Wickling","Candloth","Infernaya"],["Emberchick","Blazecrow","Cindraven"],
             ["Flintling","Scorchmaw","Vulcanine"],["Emberling","Scaldrake","Pyrothraxx"]],
   "lines2":[["Ashling","Cendrake"],["Flicktail","Emberdon"],["Sootcub","Charbruin"],
             ["Smoldfin","Searpike"],["Kindlebug","Flarebeetle"],["Emberkit","Flarelynx"],["Torchbud","Bloomfire"]],
   "singles_common":["Sootmoth","Coalcrab","Wispfox","Flarebud","Torchfin","Ashhare",
                     "Cindermite","Smokewisp","Charsnail","Emberfly","Warmtoad","Glowmoth"],
   "singles_uncommon":["Magmaw","Blazehorn"],"singles_rare":["Obsidra"],
   "singles_ultra":["Ignarok","Solmyr","Emberyx"],
   "rock_names":{"Pebblit","Boulderkin","Magmalith","Coalcrab","Charsnail","Obsidra"}},
  {"element":"water",
   "lines3":[["Dripling","Splashound","Tidalwolf"],["Frostnib","Glacikin","Glacialith"],
             ["Bubblet","Coralad","Reeflord"],["Mistchick","Fogcrane","Vaporegal"],
             ["Snowpup","Frostmaw","Blizzardine"],["Rilling","Streamsnout","Torrentyx"]],
   "lines2":[["Puddlit","Marshark"],["Icktail","Frostdon"],["Sleetcub","Chillbruin"],
             ["Minnowisp","Anglerfright"],["Krillbug","Nautibeetle"],["Frostkit","Rimelynx"],["Kelpbud","Bloomtide"]],
   "singles_common":["Dewmoth","Icecrab","Mistfox","Foambud","Coldfin","Snowhare",
                     "Frostmite","Vaporwisp","Shellsnail","Brinefly","Chilltoad","Glowjelly"],
   "singles_uncommon":["Maelmaw","Frosthorn"],"singles_rare":["Nacreon"],
   "singles_ultra":["Abyssos","Glaciera","Maelstros"],"rock_names":set()},
  {"element":"grass",
   "lines3":[["Seedling","Sprouthound","Thornwolf"],["Budnib","Bloomkin","Bloomalith"],
             ["Vinelet","Bramblad","Canopylord"],["Sporechick","Mosscrane","Verduregal"],
             ["Leafpup","Thornmaw","Sylvandine"],["Rootling","Barksnout","Titanyx"]],
   "lines2":[["Spriglit","Bramblark"],["Ivytail","Petaldon"],["Ferncub","Timberbruin"],
             ["Tadseed","Lilypike"],["Aphidbug","Beetlebloom"],["Sporekit","Mosslynx"],["Seedbud","Bloomthicket"]],
   "singles_common":["Pollmoth","Barkcrab","Fernfox","Petalbud","Reedfin","Cloverhare",
                     "Sporemite","Pollenwisp","Vinesnail","Dewfly","Mosstoad","Glowspore"],
   "singles_uncommon":["Bramblehorn","Saproot"],"singles_rare":["Verdanox"],
   "singles_ultra":["Sylvareth","Floreon","Eldwyrm"],"rock_names":set()},
  {"element":"electric",
   "lines3":[["Sparkpup","Volthound","Thunderwolf"],["Zapnib","Boltkin","Fulgralith"],
             ["Statlet","Arclad","Stormlord"],["Fizzchick","Wattcrane","Voltregal"],
             ["Joltpup","Surgemaw","Galvandine"],["Currentling","Coilsnout","Teslyx"]],
   "lines2":[["Buzzlit","Sparkshark"],["Ziptail","Voltdon"],["Staticub","Thunderbruin"],
             ["Sparkfin","Zappike"],["Mothbolt","Beetlesurge"],["Joltkit","Arclynx"],["Sparkbud","Boltthicket"]],
   "singles_common":["Zapmoth","Voltcrab","Sparkfox","Fizzbud","Wattfin","Bolthare",
                     "Staticmite","Ozonewisp","Coilsnail","Amperefly","Buzztoad","Glowvolt"],
   "singles_uncommon":["Surgehorn","Dynamaw"],"singles_rare":["Voltanox"],
   "singles_ultra":["Fulguros","Tempesta","Voltaeon"],"rock_names":set()},
  {"element":"shadow",
   "lines3":[["Duskpup","Shadowhound","Nightwolf"],["Voidnib","Umbrakin","Voidalith"],
             ["Gloamlet","Shadelad","Eclipselord"],["Wispchick","Nebulacrane","Astregal"],
             ["Shadepup","Diremaw","Umbrandine"],["Riftling","Starsnout","Cosmyx"]],
   "lines2":[["Murklit","Voidshark"],["Shadetail","Umbradon"],["Gloomcub","Nightbruin"],
             ["Inkfin","Voidpike"],["Mothshade","Beetlevoid"],["Duskkit","Shadelynx"],["Starbud","Voidthicket"]],
   "singles_common":["Duskmoth","Voidcrab","Shadefox","Gloombud","Darkfin","Umbrahare",
                     "Shademite","Netherwisp","Voidsnail","Cometfly","Murktoad","Glowshade"],
   "singles_uncommon":["Nebulahorn","Riftmaw"],"singles_rare":["Umbranox"],
   "singles_ultra":["Nyxaros","Astralon","Eclipsar"],"rock_names":set()},
]

LINE3_SLOTS = ["canine","golem","lord","bird","saber","dragon"]
LINE2_SLOTS = ["shark","don","bear","fish","beetle","lynx","plant"]
SINGLE_COMMON_SLOTS = ["moth","crab","fox","sprout","fish","hare","mite","wisp","snail","fly","toad","glow"]
SINGLE_UNCOMMON_SLOTS = ["maw","horn"]

def build_roles():
    """name -> dict(slot, stage, stage_count, legendary)"""
    roles = {}
    for s in SETS:
        for li, line in enumerate(s["lines3"]):
            for st, nm in enumerate(line):
                roles[nm] = dict(slot=LINE3_SLOTS[li], stage=st+1, sc=3, leg=None)
        for li, line in enumerate(s["lines2"]):
            for st, nm in enumerate(line):
                roles[nm] = dict(slot=LINE2_SLOTS[li], stage=st+1, sc=2, leg=None)
        for i, nm in enumerate(s["singles_common"]):
            roles[nm] = dict(slot=SINGLE_COMMON_SLOTS[i], stage=1, sc=1, leg=None)
        for i, nm in enumerate(s["singles_uncommon"]):
            roles[nm] = dict(slot=SINGLE_UNCOMMON_SLOTS[i], stage=1, sc=1, leg=None)
        for nm in s["singles_rare"]:
            roles[nm] = dict(slot="majestic", stage=1, sc=1, leg=None)
        for nm in s["singles_ultra"]:
            roles[nm] = dict(slot="legendary", stage=1, sc=1, leg=nm)
    return roles

ROLES = build_roles()

# ============================================================ archetype builders
# All creatures are drawn in the 216x150 window, standing on the ground band.
# Base pose faces left. Returns an SVG fragment (defs are added by card()).

def _spikes(uid, e, pts):
    st = e["pal"][3]
    out = f'<g fill="url(#body2{uid})" stroke="{st}" stroke-width="1.6" stroke-linejoin="round">'
    for (x, y, w, h) in pts:
        out += f'<path d="M{x-w},{y} L{x},{y-h} L{x+w},{y} Z"/>'
    return out + "</g>"

def quad(uid, e, var, cx, cy, bw, bh, headr, ear="elem", tail="elem",
         mane=0, mouth="smile", look=-0.7, angry=False, earsize=None, snout=1):
    """Shared side-profile quadruped. Mammal archetypes are configs of this."""
    pal, glow, el, st = e["pal"], e["glow"], e["acc"], e["pal"][3]
    earsize = earsize or headr*0.7
    hx, hy = cx - bw*0.66, cy - bh*0.52
    legh = bh*0.9
    lw = bw*0.30
    g = f'<ellipse cx="{cx}" cy="{cy+bh+legh*0.9:.1f}" rx="{bw*1.02:.1f}" ry="{bh*0.26:.1f}" fill="#000" opacity=".22"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round" stroke-linecap="round">'
    # far legs (darker)
    for lx in (cx-bw*0.30, cx+bw*0.34):
        g += f'<rect x="{lx-lw/2:.1f}" y="{cy+bh*0.2:.1f}" width="{lw:.1f}" height="{legh+bh*0.55:.1f}" rx="{lw/2:.1f}" fill="url(#body2{uid})"/>'
    # tail
    if tail == "elem":
        g += tuft(el, cx+bw*0.98, cy-bh*0.28, bh*0.92, e, 35)
    elif tail == "fluff":
        for i, (dx, dy, r) in enumerate([(0.9,-0.1,0.5),(1.15,-0.35,0.42),(1.32,-0.62,0.32)]):
            g += f'<circle cx="{cx+bw*dx:.1f}" cy="{cy+bh*dy:.1f}" r="{bh*r:.1f}" fill="url(#body{uid})"/>'
    elif tail == "plain":
        g += f'<path d="M{cx+bw*0.8:.1f},{cy:.1f} q{bw*0.5},{-bh*0.2} {bw*0.55},{-bh*0.9}" fill="none" stroke="{st}" stroke-width="{bw*0.16:.1f}"/>'
    elif tail == "long":
        g += f'<path d="M{cx+bw*0.85:.1f},{cy-bh*0.1:.1f} q{bw*0.7},{-bh*0.1} {bw*0.7},{-bh*1.1}" fill="none" stroke="url(#body2{uid})" stroke-width="{bw*0.2:.1f}"/>'
        g += tuft(el, cx+bw*1.55, cy-bh*1.2, bh*0.5, e, 20)
    # body
    g += f'<ellipse cx="{cx}" cy="{cy}" rx="{bw}" ry="{bh}" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="{cx-bw*0.05}" cy="{cy+bh*0.34}" rx="{bw*0.55}" ry="{bh*0.52}" fill="url(#belly{uid})" stroke="none"/>'
    if var["spots"]:
        pts = [(cx+bw*0.2, cy-bh*0.1, 2.2), (cx+bw*0.5, cy+bh*0.1, 2.0), (cx-bw*0.1, cy-bh*0.3, 1.8)][:var["spots"]]
        g += spots(el, pts, e)
    if mane:
        g += _spikes(uid, e, [(cx-bw*0.5, cy-bh*0.75, 5, 12), (cx-bw*0.2, cy-bh*0.95, 6, 15),
                              (cx+bw*0.12, cy-bh*0.9, 6, 14), (cx+bw*0.42, cy-bh*0.7, 5, 11)])
    # near legs
    for lx in (cx-bw*0.52, cx+bw*0.56):
        g += f'<rect x="{lx-lw/2:.1f}" y="{cy+bh*0.25:.1f}" width="{lw:.1f}" height="{legh+bh*0.6:.1f}" rx="{lw/2:.1f}" fill="url(#body{uid})"/>'
        g += f'<ellipse cx="{lx}" cy="{cy+bh+legh*0.85:.1f}" rx="{lw*0.62:.1f}" ry="{lw*0.4:.1f}" fill="{pal[2]}"/>'
    # head
    g += f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{headr:.1f}" fill="url(#body{uid})"/>'
    # ears
    e1x, e1y = hx-headr*0.1, hy-headr*0.78
    e2x, e2y = hx+headr*0.55, hy-headr*0.72
    if ear == "elem":
        g += tuft(el, e1x, e1y, earsize, e, -14) + tuft(el, e2x, e2y, earsize, e, 16)
    elif ear == "round":
        g += f'<circle cx="{e1x:.1f}" cy="{e1y+earsize*0.3:.1f}" r="{earsize*0.62:.1f}" fill="url(#body{uid})"/>'
        g += f'<circle cx="{e2x:.1f}" cy="{e2y+earsize*0.3:.1f}" r="{earsize*0.62:.1f}" fill="url(#body{uid})"/>'
    elif ear in ("pointed", "long", "tuft"):
        hlen = {"pointed":1.1, "long":2.1, "tuft":1.3}[ear]
        for (ex, r) in [(e1x,-8),(e2x,10)]:
            g += f'<path d="M{ex-earsize*0.4:.1f},{hy-headr*0.3:.1f} L{ex:.1f},{hy-headr*0.3-earsize*hlen:.1f} L{ex+earsize*0.4:.1f},{hy-headr*0.3:.1f} Z" fill="url(#body{uid})" transform="rotate({r} {ex} {hy})"/>'
        if ear == "tuft":
            g += tuft(el, e1x, e1y-earsize*0.6, earsize*0.5, e, -10) + tuft(el, e2x, e2y-earsize*0.6, earsize*0.5, e, 10)
    # snout
    if snout:
        g += f'<ellipse cx="{hx-headr*0.72:.1f}" cy="{hy+headr*0.34:.1f}" rx="{headr*0.42:.1f}" ry="{headr*0.32:.1f}" fill="url(#body{uid})"/>'
        g += f'<circle cx="{hx-headr*1.02:.1f}" cy="{hy+headr*0.24:.1f}" r="{headr*0.13:.1f}" fill="{st}"/>'
    # eyes
    er = headr*0.24
    g += eye(hx-headr*0.34, hy-headr*0.04, er, glow=glow, look=look*er, angry=angry, glowy=(el in ("shadow","electric")))
    g += eye(hx+headr*0.16, hy-headr*0.02, er*0.92, glow=glow, look=look*er, angry=angry, glowy=(el in ("shadow","electric")))
    # mouth
    if mouth == "smile":
        g += f'<path d="M{hx-headr*0.95:.1f},{hy+headr*0.52:.1f} q{headr*0.35},{headr*0.3} {headr*0.7},0" fill="none" stroke="{st}" stroke-width="1.5"/>'
    elif mouth == "fang":
        g += f'<path d="M{hx-headr*1.0:.1f},{hy+headr*0.45:.1f} q{headr*0.5},{headr*0.5} {headr*0.95},0.05" fill="{st}" stroke="none"/>'
        g += f'<path d="M{hx-headr*0.8:.1f},{hy+headr*0.5:.1f} l2,6 l3,-6 Z" fill="#fff"/>'
    return g + "</g>"

def stage_k(stage, sc):
    if sc == 3: return [0.82, 0.97, 1.14][stage-1]
    if sc == 2: return [0.86, 1.06][stage-1]
    return 0.95

# ----- mammal-family archetypes (configs of quad) -----
def a_canine(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    fierce = stage == sc and sc >= 2
    return quad(uid, e, var, 108, 88, 40*k, 27*k, 20*k, ear="elem",
                tail="elem", mane=1 if fierce else 0, mouth="fang" if fierce else "smile",
                angry=fierce, look=-0.8)

def a_bear(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    return quad(uid, e, var, 108, 86, 44*k, 33*k, 22*k, ear="round",
                tail="fluff", mane=0, mouth="smile", earsize=16*k, look=-0.5)

def a_fox(uid, e, stage, sc, var):
    k = stage_k(stage, sc)*0.96
    return quad(uid, e, var, 108, 90, 36*k, 24*k, 18*k, ear="pointed",
                tail="fluff", mouth="smile", earsize=15*k, look=-0.8)

def a_hare(uid, e, stage, sc, var):
    k = stage_k(stage, sc)*0.92
    return quad(uid, e, var, 108, 92, 32*k, 24*k, 17*k, ear="long",
                tail="fluff", mouth="smile", earsize=12*k, snout=1, look=-0.6)

def a_lynx(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    return quad(uid, e, var, 108, 88, 38*k, 26*k, 19*k, ear="tuft",
                tail="plain", mouth="smile", earsize=13*k, look=-0.7)

def a_saber(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    fierce = stage == sc
    return quad(uid, e, var, 108, 88, 42*k, 28*k, 21*k, ear="pointed",
                tail="long", mane=1 if fierce else 0, mouth="fang" if fierce else "smile",
                angry=fierce, earsize=14*k, look=-0.85)

def a_don(uid, e, stage, sc, var):
    """horned saurian quadruped (tail -> don)."""
    k = stage_k(stage, sc)
    pal, st = e["pal"], e["pal"][3]
    hx, hy = 108 - 40*k*0.66, 88 - 27*k*0.52
    base = quad(uid, e, var, 108, 88, 40*k, 28*k, 20*k, ear="round",
                tail="plain", mouth="smile", earsize=9*k, look=-0.6)
    # horns forward
    horn = f'<g stroke="{st}" stroke-width="1.8" stroke-linejoin="round" fill="{pal[0]}">'
    horn += f'<path d="M{hx-16*k:.1f},{hy-8*k:.1f} q-12,-2 -18,-9 q10,-1 16,4 Z"/>'
    horn += f'<path d="M{hx-6*k:.1f},{hy-16*k:.1f} q-2,-12 -8,-17 q0,10 3,17 Z"/></g>'
    # back plates
    plates = _spikes(uid, e, [(108-16*k, 88-26*k, 5, 10), (108+2*k, 88-30*k, 6, 13), (108+20*k, 88-24*k, 5, 10)])
    return base + horn + plates

def a_maw(uid, e, stage, sc, var):
    """big-mouthed beast (uncommon single)."""
    k = 1.0
    pal, st, glow = e["pal"], e["pal"][3], e["glow"]
    g = quad(uid, e, var, 108, 88, 42, 28, 22, ear="pointed", tail="long",
             mane=1, mouth="fang", angry=1, earsize=13, look=-0.85)
    hx, hy = 108-42*0.66, 88-28*0.52
    jaw = f'<path d="M{hx-20:.1f},{hy+6:.1f} q-6,14 6,18 q14,3 18,-6 q-10,2 -16,-4 q-4,-4 -8,-8 Z" fill="{pal[3]}" stroke="{st}" stroke-width="1.6"/>'
    teeth = f'<g fill="#fff">'
    for i in range(3):
        teeth += f'<path d="M{hx-16+i*8:.1f},{hy+9:.1f} l2,6 l3,-6 Z"/>'
    teeth += "</g>"
    return g + jaw + teeth

def a_horn(uid, e, stage, sc, var):
    """ram-horned beast (uncommon single)."""
    pal, st = e["pal"], e["pal"][3]
    g = quad(uid, e, var, 108, 88, 40, 28, 21, ear="round", tail="fluff",
             mouth="smile", earsize=9, look=-0.6)
    hx, hy = 108-40*0.66, 88-28*0.52
    ram = f'<g fill="url(#body2{uid})" stroke="{st}" stroke-width="1.8" stroke-linejoin="round">'
    ram += f'<path d="M{hx-14:.1f},{hy-12:.1f} q-16,-6 -18,6 q-2,12 10,12 q-6,-8 0,-14 q6,-6 8,-4 Z"/>'
    ram += f'<path d="M{hx+12:.1f},{hy-13:.1f} q16,-6 18,6 q2,12 -10,12 q6,-8 0,-14 q-6,-6 -8,-4 Z"/></g>'
    return g + ram

def a_majestic(uid, e, stage, sc, var):
    """antlered regal beast (rare single)."""
    pal, st, glow = e["pal"], e["pal"][3], e["glow"]
    g = f'<circle cx="108" cy="66" r="46" fill="none" stroke="{glow}" stroke-width="2" opacity=".28"/>'
    body = quad(uid, e, var, 108, 90, 40, 26, 19, ear="pointed", tail="long",
                mouth="smile", earsize=10, look=-0.7)
    hx, hy = 108-40*0.66, 90-26*0.52
    ant = f'<g fill="none" stroke="url(#body2{uid})" stroke-width="3" stroke-linecap="round">'
    for sgn in (-1, 1):
        bx = hx + sgn*6
        ant += f'<path d="M{bx:.1f},{hy-16:.1f} q{sgn*4},-14 {sgn*2},-24"/>'
        ant += f'<path d="M{bx+sgn*2:.1f},{hy-26:.1f} q{sgn*10},-3 {sgn*14},-10"/>'
        ant += f'<path d="M{bx+sgn*1:.1f},{hy-32:.1f} q{sgn*8},-4 {sgn*10},-12"/>'
    ant += "</g>"
    return g + body + ant

def a_golem(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy, bw, bh = 108, 84, 40*k, 32*k
    g = f'<ellipse cx="{cx}" cy="{cy+bh+bh*0.7:.1f}" rx="{bw*1.05:.1f}" ry="{bh*0.24:.1f}" fill="#000" opacity=".22"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    for lx in (cx-bw*0.5, cx+bw*0.5):
        g += f'<rect x="{lx-bw*0.22:.1f}" y="{cy+bh*0.55:.1f}" width="{bw*0.44:.1f}" height="{bh*0.75:.1f}" rx="7" fill="url(#body2{uid})"/>'
    for ax in (cx-bw-bw*0.16, cx+bw-bw*0.18):
        g += f'<rect x="{ax:.1f}" y="{cy-bh*0.2:.1f}" width="{bw*0.34:.1f}" height="{bh*0.95:.1f}" rx="8" fill="url(#body2{uid})"/>'
    g += f'<rect x="{cx-bw:.1f}" y="{cy-bh:.1f}" width="{bw*2:.1f}" height="{bh*1.9:.1f}" rx="{bw*0.45:.1f}" fill="url(#body{uid})"/>'
    # cracks
    g += f'<g stroke="{pal[3]}" stroke-width="1.4" fill="none" opacity=".5"><path d="M{cx-bw*0.4:.1f},{cy-bh*0.7:.1f} l8,10 l-5,8"/><path d="M{cx+bw*0.5:.1f},{cy+bh*0.2:.1f} l-7,8"/></g>'
    if var["spots"]:
        g += spots(el, [(cx-bw*0.5, cy-bh*0.2, 2.4), (cx+bw*0.45, cy-bh*0.55, 2.2)][:max(1, var["spots"]-1) or 1], e)
    # face panel
    g += f'<rect x="{cx-bw*0.62:.1f}" y="{cy-bh*0.55:.1f}" width="{bw*1.24:.1f}" height="{bh*0.9:.1f}" rx="{bw*0.2:.1f}" fill="{pal[3]}" opacity=".55" stroke="none"/>'
    er = bw*0.16
    g += eye(cx-bw*0.28, cy-bh*0.1, er, glow=glow, look=0, glowy=True) + eye(cx+bw*0.28, cy-bh*0.1, er, glow=glow, look=0, glowy=True)
    g += f'<path d="M{cx-bw*0.3:.1f},{cy+bh*0.35:.1f} q{bw*0.3:.1f},{bh*0.18:.1f} {bw*0.6:.1f},0" fill="none" stroke="{glow}" stroke-width="1.6" opacity=".8"/>'
    g += "</g>"
    # crown tufts
    g += tuft(el, cx-bw*0.4, cy-bh-6, 10*k, e, -12) + tuft(el, cx, cy-bh-10, 13*k, e, 0) + tuft(el, cx+bw*0.4, cy-bh-6, 10*k, e, 12)
    return g

def a_lord(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx = 108
    top = 60 - (stage-1)*4
    baseW = 30*k
    g = f'<ellipse cx="{cx}" cy="132" rx="{baseW*1.2:.1f}" ry="7" fill="#000" opacity=".22"/>'
    g += f'<circle cx="{cx}" cy="{top+6:.1f}" r="{34*k:.1f}" fill="none" stroke="{glow}" stroke-width="2" opacity=".3"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    # robe (tapered)
    g += f'<path d="M{cx-14*k:.1f},{top+16:.1f} L{cx+14*k:.1f},{top+16:.1f} L{cx+baseW:.1f},132 Q{cx},142 {cx-baseW:.1f},132 Z" fill="url(#body{uid})"/>'
    # sleeves
    g += f'<path d="M{cx-12*k:.1f},{top+22:.1f} Q{cx-baseW-6:.1f},{top+40:.1f} {cx-baseW*0.7:.1f},{top+62:.1f} L{cx-baseW*0.4:.1f},{top+56:.1f} Q{cx-16*k:.1f},{top+38:.1f} {cx-10*k:.1f},{top+34:.1f} Z" fill="url(#body2{uid})"/>'
    g += f'<path d="M{cx+12*k:.1f},{top+22:.1f} Q{cx+baseW+6:.1f},{top+40:.1f} {cx+baseW*0.7:.1f},{top+62:.1f} L{cx+baseW*0.4:.1f},{top+56:.1f} Q{cx+16*k:.1f},{top+38:.1f} {cx+10*k:.1f},{top+34:.1f} Z" fill="url(#body2{uid})"/>'
    # belly glow rune
    g += f'<circle cx="{cx}" cy="{top+52:.1f}" r="{6*k:.1f}" fill="url(#orb{uid})"/>'
    # hood/head
    g += f'<path d="M{cx-15*k:.1f},{top+10:.1f} Q{cx}, {top-18*k:.1f} {cx+15*k:.1f},{top+10:.1f} Q{cx},{top+22:.1f} {cx-15*k:.1f},{top+10:.1f} Z" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="{cx}" cy="{top+8:.1f}" rx="{10*k:.1f}" ry="{9*k:.1f}" fill="{pal[3]}" stroke="none"/>'
    g += eye(cx-4*k, top+7, 2.6*k, glow=glow, look=0, glowy=True) + eye(cx+4*k, top+7, 2.6*k, glow=glow, look=0, glowy=True)
    g += "</g>"
    # crown
    g += tuft(el, cx-9*k, top-10*k, 8*k, e, -20) + tuft(el, cx, top-15*k, 11*k, e, 0) + tuft(el, cx+9*k, top-10*k, 8*k, e, 20)
    return g

def a_bird(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 92
    bw, bh = 15*k, 24*k
    span = 34*k + (stage-1)*8
    g = f'<ellipse cx="{cx}" cy="132" rx="{22*k:.1f}" ry="6" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round">'
    # legs
    for lx in (cx-5*k, cx+5*k):
        g += f'<line x1="{lx:.1f}" y1="{cy+bh*0.7:.1f}" x2="{lx:.1f}" y2="128" stroke="{pal[2]}" stroke-width="{2.2*k:.1f}"/>'
        g += f'<path d="M{lx-4:.1f},128 h8 M{lx:.1f},128 v3" stroke="{pal[2]}" stroke-width="1.6"/>'
    # wings (spread), feather tips element-tinted
    for sgn in (-1, 1):
        g += f'<path d="M{cx+sgn*bw*0.6:.1f},{cy-bh*0.3:.1f} Q{cx+sgn*span:.1f},{cy-bh*0.6:.1f} {cx+sgn*(span+6):.1f},{cy+bh*0.2:.1f} Q{cx+sgn*span*0.6:.1f},{cy+bh*0.5:.1f} {cx+sgn*bw*0.6:.1f},{cy+bh*0.4:.1f} Z" fill="url(#body{uid})"/>'
        for i in range(3):
            fx = cx + sgn*(span*0.5 + i*span*0.16)
            g += tuft(el, fx, cy+bh*0.3, 6*k, e, sgn*40)
    # body
    g += f'<ellipse cx="{cx}" cy="{cy}" rx="{bw}" ry="{bh}" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="{cx}" cy="{cy+bh*0.2}" rx="{bw*0.6}" ry="{bh*0.6}" fill="url(#belly{uid})" stroke="none"/>'
    # head
    hy = cy - bh - 6*k
    g += f'<circle cx="{cx}" cy="{hy:.1f}" r="{11*k:.1f}" fill="url(#body{uid})"/>'
    g += f'<path d="M{cx-11*k:.1f},{hy:.1f} l-8,-2 l6,6 Z" fill="{glow}"/>'  # beak
    g += eye(cx-3*k, hy-1, 2.6*k, glow=glow, look=-1, glowy=(el in ("shadow","electric")))
    g += eye(cx+5*k, hy-1, 2.3*k, glow=glow, look=-1, glowy=(el in ("shadow","electric")))
    # crest
    g += tuft(el, cx, hy-10*k, 8*k, e, 0)
    if stage == sc and sc == 3:
        g += tuft(el, cx-5*k, hy-8*k, 6*k, e, -22) + tuft(el, cx+5*k, hy-8*k, 6*k, e, 22)
        # tail plumes
        g += tuft(el, cx, cy+bh+4, 10*k, e, 180)
    return g + "</g>"

def a_dragon(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    g = f'<ellipse cx="112" cy="130" rx="{42*k:.1f}" ry="6" fill="#000" opacity=".2"/>'
    if stage == sc and sc == 3:
        g += f'<circle cx="108" cy="72" r="46" fill="none" stroke="{glow}" stroke-width="2" opacity=".26"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    # coiled serpent body
    b = (f'M150,128 C120,136 96,126 98,108 C100,94 118,92 120,104 C132,106 136,92 124,86 '
         f'C104,76 78,88 76,110 C74,92 86,68 116,60 C100,58 86,70 84,82 C76,70 88,50 112,46 '
         f'C118,56 116,64 108,70 Z')
    g += f'<path d="{b}" fill="url(#body{uid})" transform="translate(108 90) scale({k:.2f}) translate(-108 -90)"/>'
    # element mane spikes along back
    for i, (mx, my) in enumerate([(104,64),(112,74),(118,88),(120,102)]):
        px = 108 + (mx-108)*k
        py = 90 + (my-90)*k
        g += tuft(el, px, py-6, 7*k, e, (i%2)*10-5)
    # head + horns
    hx, hy = 108 + (96-108)*k, 90 + (48-90)*k
    g += f'<path d="M{hx-10*k:.1f},{hy-6*k:.1f} Q{hx+6*k:.1f},{hy-14*k:.1f} {hx+12*k:.1f},{hy:.1f} Q{hx+6*k:.1f},{hy+10*k:.1f} {hx-8*k:.1f},{hy+8*k:.1f} Q{hx-16*k:.1f},{hy:.1f} {hx-10*k:.1f},{hy-6*k:.1f} Z" fill="url(#body{uid})"/>'
    g += tuft(el, hx-2*k, hy-12*k, 7*k, e, -18) + tuft(el, hx+8*k, hy-11*k, 7*k, e, 14)
    g += eye(hx-4*k, hy-1, 3.0*k, glow=glow, look=-1, angry=(stage==sc), glowy=(el in ("shadow","electric","fire")))
    g += f'<path d="M{hx-14*k:.1f},{hy+4*k:.1f} q6,4 12,2" fill="none" stroke="{st}" stroke-width="1.4"/>'
    if stage == sc and sc == 3:
        for sgn in (1,):
            g += f'<path d="M118,86 Q150,60 168,78 Q150,84 140,100 Z" fill="url(#body2{uid})" transform="translate(108 90) scale({k:.2f}) translate(-108 -90)"/>'
    return g + "</g>"

def _fish(uid, e, var, cx, cy, L, Hh, sharky):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    g = f'<ellipse cx="{cx}" cy="{cy+Hh+8:.1f}" rx="{L*0.7:.1f}" ry="{Hh*0.22:.1f}" fill="#000" opacity=".16"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round">'
    # tail fin (right)
    g += f'<path d="M{cx+L*0.82:.1f},{cy:.1f} l{L*0.3:.1f},{-Hh*0.9:.1f} l0,{Hh*1.8:.1f} Z" fill="url(#body2{uid})"/>'
    # body teardrop (head left)
    g += f'<path d="M{cx-L:.1f},{cy:.1f} C{cx-L:.1f},{cy-Hh*1.3:.1f} {cx+L*0.7:.1f},{cy-Hh:.1f} {cx+L*0.85:.1f},{cy:.1f} C{cx+L*0.7:.1f},{cy+Hh:.1f} {cx-L:.1f},{cy+Hh*1.3:.1f} {cx-L:.1f},{cy:.1f} Z" fill="url(#body{uid})"/>'
    g += f'<path d="M{cx-L*0.9:.1f},{cy:.1f} C{cx-L*0.8:.1f},{cy+Hh*0.6:.1f} {cx+L*0.4:.1f},{cy+Hh*0.7:.1f} {cx+L*0.7:.1f},{cy+Hh*0.2:.1f}" fill="none" stroke="{pal[0]}" stroke-width="{Hh*0.28:.1f}" opacity=".7"/>'
    # dorsal fin = element tuft
    g += tuft(el, cx, cy-Hh*0.95, Hh*0.8, e, 0)
    # pectoral fin
    g += f'<path d="M{cx-L*0.2:.1f},{cy+Hh*0.3:.1f} q{-L*0.3:.1f},{Hh*0.5:.1f} {-L*0.05:.1f},{Hh*0.7:.1f} q{L*0.15:.1f},{-Hh*0.3:.1f} {L*0.1:.1f},{-Hh*0.6:.1f} Z" fill="url(#body2{uid})"/>'
    if var["spots"]:
        g += spots(el, [(cx, cy-Hh*0.2, 2.2), (cx+L*0.3, cy, 2.0)][:var["spots"]], e)
    # eye + mouth
    g += eye(cx-L*0.62, cy-Hh*0.18, Hh*0.22, glow=glow, look=-1, glowy=(el in ("shadow","electric")))
    if sharky:
        g += f'<path d="M{cx-L*0.98:.1f},{cy+Hh*0.28:.1f} q{L*0.3:.1f},{Hh*0.28:.1f} {L*0.55:.1f},{-Hh*0.05:.1f} l-2,6 l-6,-3 l-4,5 l-5,-4 l-5,4 Z" fill="#fff" stroke="{st}" stroke-width="1.2"/>'
    else:
        g += f'<path d="M{cx-L*0.95:.1f},{cy+Hh*0.28:.1f} q{L*0.22:.1f},{Hh*0.2:.1f} {L*0.4:.1f},0" fill="none" stroke="{st}" stroke-width="1.5"/>'
    return g + "</g>"

def a_shark(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    return _fish(uid, e, var, 104, 90, 50*k, 22*k, sharky=True)

def a_fish(uid, e, stage, sc, var):
    k = stage_k(stage, sc) if sc > 1 else 0.9
    sharky = (sc == 2 and stage == 2)  # pike stage = toothy
    return _fish(uid, e, var, 104, 92, 40*k, 22*k, sharky=sharky)

def a_beetle(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy, rw, rh = 108, 90, 34*k, 28*k
    g = f'<ellipse cx="{cx}" cy="{cy+rh+4:.1f}" rx="{rw:.1f}" ry="6" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round">'
    for i, sgn in enumerate((-1, 1)):
        for j in range(3):
            ly = cy - rh*0.2 + j*rh*0.5
            g += f'<path d="M{cx+sgn*rw*0.7:.1f},{ly:.1f} q{sgn*rw*0.4:.1f},{-4:.1f} {sgn*rw*0.5:.1f},{6:.1f}" fill="none" stroke="{pal[2]}" stroke-width="{2.4*k:.1f}"/>'
    # head + horn (element)
    g += f'<circle cx="{cx}" cy="{cy-rh*0.75:.1f}" r="{rh*0.42:.1f}" fill="url(#body2{uid})"/>'
    g += tuft(el, cx, cy-rh*1.25, 12*k, e, 0)
    # carapace dome
    g += f'<path d="M{cx-rw:.1f},{cy+rh*0.2:.1f} a{rw:.1f},{rh:.1f} 0 0 1 {rw*2:.1f},0 Z" fill="url(#body{uid})"/>'
    g += f'<line x1="{cx}" y1="{cy-rh*0.78:.1f}" x2="{cx}" y2="{cy+rh*0.2:.1f}" stroke="{pal[3]}" stroke-width="1.6"/>'
    if var["spots"]:
        g += spots(el, [(cx-rw*0.4, cy-rh*0.1, 2.6), (cx+rw*0.4, cy-rh*0.1, 2.6), (cx-rw*0.2, cy-rh*0.4, 2.0)][:var["spots"]], e)
    g += eye(cx-rh*0.18, cy-rh*0.78, 2.4*k, glow=glow, look=0, glowy=(el in ("shadow","electric"))) + eye(cx+rh*0.18, cy-rh*0.78, 2.4*k, glow=glow, look=0, glowy=(el in ("shadow","electric")))
    return g + "</g>"

def a_plant(uid, e, stage, sc, var):
    k = stage_k(stage, sc)
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 96
    bw, bh = 20*k, 22*k
    petals = 6 if stage == sc else 5
    pr = 16*k + (stage-1)*4
    g = f'<ellipse cx="{cx}" cy="{cy+bh+2:.1f}" rx="{bw*1.3:.1f}" ry="6" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round">'
    # leaf arms
    g += tuft("grass", cx-bw*1.2, cy-bh*0.2, 12*k, ELE["grass"], -60) + tuft("grass", cx+bw*1.2, cy-bh*0.2, 12*k, ELE["grass"], 60)
    # bulb body
    g += f'<ellipse cx="{cx}" cy="{cy}" rx="{bw}" ry="{bh}" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="{cx}" cy="{cy+bh*0.2}" rx="{bw*0.6}" ry="{bh*0.6}" fill="url(#belly{uid})" stroke="none"/>'
    # flower crown of element petals
    fy = cy - bh - 2
    for i in range(petals):
        a = math.pi * (0.15 + 0.7*i/(petals-1))
        px = cx - math.cos(a)*pr
        py = fy - math.sin(a)*pr*0.7
        g += tuft(el, px, py, 9*k, e, math.degrees(a)-90)
    g += f'<circle cx="{cx}" cy="{fy+4:.1f}" r="{6*k:.1f}" fill="url(#orb{uid})"/>'
    # face
    g += eye(cx-bw*0.35, cy-bh*0.1, 2.8*k, glow=glow, look=0, glowy=(el in ("shadow","electric"))) + eye(cx+bw*0.35, cy-bh*0.1, 2.8*k, glow=glow, look=0, glowy=(el in ("shadow","electric")))
    g += f'<path d="M{cx-bw*0.28:.1f},{cy+bh*0.25:.1f} q{bw*0.28:.1f},{bh*0.2:.1f} {bw*0.56:.1f},0" fill="none" stroke="{st}" stroke-width="1.5"/>'
    return g + "</g>"

def a_sprout(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 100
    g = f'<ellipse cx="{cx}" cy="{cy+16:.1f}" rx="20" ry="5" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round">'
    # seed body
    g += f'<ellipse cx="{cx}" cy="{cy}" rx="16" ry="17" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="{cx}" cy="{cy+3}" rx="9" ry="10" fill="url(#belly{uid})" stroke="none"/>'
    # sprout stem + leaves (element)
    g += f'<line x1="{cx}" y1="{cy-16:.1f}" x2="{cx}" y2="{cy-30:.1f}" stroke="{pal[2]}" stroke-width="3"/>'
    g += tuft(el, cx-6, cy-30, 9, e, -55) + tuft(el, cx+6, cy-30, 9, e, 55) + tuft(el, cx, cy-36, 8, e, 0)
    g += eye(cx-6, cy-1, 3.0, glow=glow, look=0, glowy=(el in ("shadow","electric"))) + eye(cx+6, cy-1, 3.0, glow=glow, look=0, glowy=(el in ("shadow","electric")))
    g += f'<path d="M{cx-4:.1f},{cy+8:.1f} q4,4 8,0" fill="none" stroke="{st}" stroke-width="1.4"/>'
    return g + "</g>"

def a_moth(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 86
    g = f'<ellipse cx="{cx}" cy="128" rx="30" ry="6" fill="#000" opacity=".16"/>'
    g += f'<g stroke="{st}" stroke-width="2.1" stroke-linejoin="round">'
    for sgn in (-1, 1):
        g += f'<path d="M{cx:.1f},{cy-8:.1f} Q{cx+sgn*46:.1f},{cy-30:.1f} {cx+sgn*44:.1f},{cy-2:.1f} Q{cx+sgn*30:.1f},{cy+4:.1f} {cx:.1f},{cy:.1f} Z" fill="url(#body{uid})"/>'
        g += f'<path d="M{cx:.1f},{cy+2:.1f} Q{cx+sgn*34:.1f},{cy+10:.1f} {cx+sgn*30:.1f},{cy+26:.1f} Q{cx+sgn*16:.1f},{cy+22:.1f} {cx:.1f},{cy+8:.1f} Z" fill="url(#body2{uid})"/>'
        g += spots(el, [(cx+sgn*26, cy-12, 3.2), (cx+sgn*22, cy+14, 2.6)], e)
    # fuzzy body
    g += f'<ellipse cx="{cx}" cy="{cy+4}" rx="7" ry="16" fill="url(#belly{uid})"/>'
    g += f'<circle cx="{cx}" cy="{cy-14:.1f}" r="7" fill="url(#body{uid})"/>'
    # antennae
    g += f'<path d="M{cx-3:.1f},{cy-20:.1f} q-8,-10 -14,-8 M{cx+3:.1f},{cy-20:.1f} q8,-10 14,-8" fill="none" stroke="{st}" stroke-width="1.5"/>'
    g += eye(cx-3, cy-14, 2.4, glow=glow, look=0, glowy=True) + eye(cx+3, cy-14, 2.4, glow=glow, look=0, glowy=True)
    return g + "</g>"

def a_crab(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 96
    g = f'<ellipse cx="{cx}" cy="{cy+18:.1f}" rx="34" ry="6" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round" stroke-linecap="round">'
    for sgn in (-1, 1):
        for j in range(3):
            g += f'<path d="M{cx+sgn*24:.1f},{cy+4+j*4:.1f} q{sgn*14:.1f},4 {sgn*16:.1f},14" fill="none" stroke="{pal[2]}" stroke-width="2.4"/>'
        # claw arms
        g += f'<path d="M{cx+sgn*22:.1f},{cy-2:.1f} q{sgn*20:.1f},-6 {sgn*26:.1f},-16" fill="none" stroke="url(#body2{uid})" stroke-width="5"/>'
        g += f'<path d="M{cx+sgn*46:.1f},{cy-22:.1f} q{sgn*10:.1f},-6 {sgn*2:.1f},-12 q{-sgn*6:.1f},2 {-sgn*2:.1f},8 q{-sgn*8:.1f},-2 {-sgn*8:.1f},6 Z" fill="url(#body{uid})"/>'
    # shell
    g += f'<path d="M{cx-30:.1f},{cy+2:.1f} a30,22 0 0 1 60,0 Z" fill="url(#body{uid})"/>'
    g += spots(el, [(cx-12, cy-6, 2.6), (cx+12, cy-6, 2.6), (cx, cy-2, 2.4)][:2+var["spots"]//2], e)
    # eyestalks
    for sgn in (-1, 1):
        g += f'<line x1="{cx+sgn*8:.1f}" y1="{cy-14:.1f}" x2="{cx+sgn*8:.1f}" y2="{cy-24:.1f}" stroke="{pal[2]}" stroke-width="2.4"/>'
        g += eye(cx+sgn*8, cy-26, 3.0, glow=glow, look=0, glowy=(el in ("shadow","electric")))
    g += f'<path d="M{cx-8:.1f},{cy+6:.1f} q8,5 16,0" fill="none" stroke="{st}" stroke-width="1.4"/>'
    return g + "</g>"

def a_mite(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 96
    g = f'<ellipse cx="{cx}" cy="{cy+16:.1f}" rx="22" ry="5" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.0" stroke-linejoin="round" stroke-linecap="round">'
    for sgn in (-1, 1):
        for j in range(3):
            g += f'<path d="M{cx+sgn*14:.1f},{cy+j*5:.1f} l{sgn*10:.1f},6" fill="none" stroke="{pal[2]}" stroke-width="2.2"/>'
    g += f'<ellipse cx="{cx}" cy="{cy}" rx="18" ry="15" fill="url(#body{uid})"/>'
    g += tuft(el, cx, cy-18, 9, e, 0)
    g += spots(el, [(cx-6, cy-2, 2.2), (cx+6, cy-4, 2.0)][:max(1, var["spots"])], e)
    g += eye(cx-6, cy-1, 3.6, glow=glow, look=0, glowy=True) + eye(cx+6, cy-1, 3.6, glow=glow, look=0, glowy=True)
    return g + "</g>"

def a_wisp(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 84
    g = f'<ellipse cx="{cx}" cy="124" rx="16" ry="5" fill="#000" opacity=".14"/>'
    g += f'<g stroke="{st}" stroke-width="2.1" stroke-linejoin="round">'
    # wispy tail
    g += f'<path d="M{cx-10:.1f},{cy+6:.1f} Q{cx-14:.1f},{cy+30:.1f} {cx:.1f},{cy+40:.1f} Q{cx+14:.1f},{cy+30:.1f} {cx+10:.1f},{cy+6:.1f} Z" fill="url(#body{uid})"/>'
    # orb core
    g += f'<circle cx="{cx}" cy="{cy}" r="18" fill="url(#orb{uid})"/>'
    g += tuft(el, cx, cy-22, 11, e, 0)
    g += eye(cx-6, cy, 3.0, glow="#1a1020", look=0) + eye(cx+6, cy, 3.0, glow="#1a1020", look=0)
    g += f'<path d="M{cx-4:.1f},{cy+8:.1f} q4,4 8,0" fill="none" stroke="{st}" stroke-width="1.4"/>'
    return g + "</g>"

def a_snail(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 112, 96
    g = f'<ellipse cx="{cx-6:.1f}" cy="{cy+14:.1f}" rx="30" ry="5" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round">'
    # foot/body
    g += f'<path d="M{cx-34:.1f},{cy+10:.1f} q-2,-14 14,-14 l18,0 q6,10 -4,14 Z" fill="url(#belly{uid})"/>'
    # head
    g += f'<circle cx="{cx-32:.1f}" cy="{cy-2:.1f}" r="9" fill="url(#body2{uid})"/>'
    for sgn in (-1, 1):
        g += f'<line x1="{cx-34:.1f}" y1="{cy-8:.1f}" x2="{cx-38:.1f}" y2="{cy-8+sgn*8:.1f}" stroke="{pal[2]}" stroke-width="2"/>'
    g += eye(cx-34, cy-3, 2.6, glow=glow, look=-1, glowy=(el in ("shadow","electric")))
    # spiral shell
    g += f'<circle cx="{cx+4:.1f}" cy="{cy-6:.1f}" r="20" fill="url(#body{uid})"/>'
    g += f'<path d="M{cx+4:.1f},{cy-6:.1f} m0,0 a4,4 0 1 1 6,-2 a9,9 0 1 1 -13,3 a15,15 0 1 1 22,-4" fill="none" stroke="{pal[3]}" stroke-width="1.8"/>'
    g += tuft(el, cx+4, cy-28, 7, e, 0)
    return g + "</g>"

def a_fly(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 88
    g = f'<ellipse cx="{cx}" cy="126" rx="18" ry="5" fill="#000" opacity=".14"/>'
    g += f'<g stroke="{st}" stroke-width="1.9" stroke-linejoin="round">'
    for sgn in (-1, 1):
        g += f'<ellipse cx="{cx+sgn*20:.1f}" cy="{cy-8:.1f}" rx="18" ry="8" fill="url(#body{uid})" opacity=".92" transform="rotate({sgn*-18} {cx+sgn*20:.1f} {cy-8:.1f})"/>'
        g += f'<ellipse cx="{cx+sgn*18:.1f}" cy="{cy+6:.1f}" rx="13" ry="6" fill="url(#body2{uid})" opacity=".9" transform="rotate({sgn*16} {cx+sgn*18:.1f} {cy+6:.1f})"/>'
    # segmented body (glowing tail for firefly vibe)
    g += f'<ellipse cx="{cx}" cy="{cy+2}" rx="6" ry="18" fill="url(#body2{uid})"/>'
    g += f'<circle cx="{cx}" cy="{cy+16:.1f}" r="5" fill="url(#orb{uid})"/>'
    g += f'<circle cx="{cx}" cy="{cy-16:.1f}" r="7" fill="url(#body{uid})"/>'
    g += f'<path d="M{cx-2:.1f},{cy-22:.1f} q-6,-8 -12,-7 M{cx+2:.1f},{cy-22:.1f} q6,-8 12,-7" fill="none" stroke="{st}" stroke-width="1.4"/>'
    g += eye(cx-3, cy-16, 2.4, glow=glow, look=0, glowy=True) + eye(cx+3, cy-16, 2.4, glow=glow, look=0, glowy=True)
    return g + "</g>"

def a_toad(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 96
    g = f'<ellipse cx="{cx}" cy="{cy+18:.1f}" rx="36" ry="6" fill="#000" opacity=".2"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    for sgn in (-1, 1):
        g += f'<path d="M{cx+sgn*26:.1f},{cy+4:.1f} q{sgn*12:.1f},6 {sgn*10:.1f},16 q{-sgn*8:.1f},2 {-sgn*12:.1f},-4 Z" fill="url(#body2{uid})"/>'
    g += f'<ellipse cx="{cx}" cy="{cy}" rx="34" ry="24" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="{cx}" cy="{cy+8}" rx="20" ry="14" fill="url(#belly{uid})" stroke="none"/>'
    g += spots(el, [(cx-16, cy-8, 2.6), (cx+16, cy-8, 2.6), (cx-6, cy-12, 2.0), (cx+8, cy-2, 2.2)][:1+var["spots"]], e)
    # wide mouth
    g += f'<path d="M{cx-24:.1f},{cy+4:.1f} q{24:.1f},{16:.1f} {48:.1f},0" fill="none" stroke="{st}" stroke-width="1.8"/>'
    # eyes on top
    for sgn in (-1, 1):
        g += f'<circle cx="{cx+sgn*14:.1f}" cy="{cy-20:.1f}" r="9" fill="url(#body{uid})"/>'
        g += eye(cx+sgn*14, cy-21, 3.4, glow=glow, look=0, glowy=(el in ("shadow","electric")))
    return g + "</g>"

def a_glow(uid, e, stage, sc, var):
    pal, st, glow, el = e["pal"], e["pal"][3], e["glow"], e["acc"]
    cx, cy = 108, 78
    g = f'<circle cx="{cx}" cy="{cy+6:.1f}" r="42" fill="url(#stage{uid})"/>'
    g += f'<g stroke="{st}" stroke-width="2.1" stroke-linejoin="round">'
    # tentacles
    for i in range(6):
        tx = cx - 24 + i*10
        g += f'<path d="M{tx:.1f},{cy+16:.1f} q{-4 if i%2 else 4},20 {2 if i%2 else -2},40" fill="none" stroke="{pal[1]}" stroke-width="2.4" opacity=".9"/>'
    # bell
    g += f'<path d="M{cx-30:.1f},{cy+16:.1f} a30,26 0 0 1 60,0 Q{cx},{cy+26:.1f} {cx-30:.1f},{cy+16:.1f} Z" fill="url(#orb{uid})"/>'
    g += spots(el, [(cx-12, cy, 2.4), (cx+12, cy, 2.4), (cx, cy-6, 2.2)][:1+var["spots"]], e)
    g += eye(cx-9, cy+2, 3.2, glow="#1a1020", look=0) + eye(cx+9, cy+2, 3.2, glow="#1a1020", look=0)
    g += f'<path d="M{cx-6:.1f},{cy+9:.1f} q6,4 12,0" fill="none" stroke="{st}" stroke-width="1.4"/>'
    return g + "</g>"

# ==================================================================== legendaries
def l_emberyx(uid, e, var):
    pal = e["pal"]; g = '<g>'
    g += f'<circle cx="108" cy="70" r="50" fill="none" stroke="{e["glow"]}" stroke-width="2.5" opacity=".4"/>'
    for k in range(16):
        a = k*math.pi/8; x1 = 108+math.cos(a)*40; y1 = 70+math.sin(a)*40; x2 = 108+math.cos(a)*62; y2 = 70+math.sin(a)*62
        g += f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{e["glow"]}" stroke-width="1.4" opacity=".22"/>'
    g += f'<g stroke="{pal[3]}" stroke-width="2.2" stroke-linejoin="round">'
    for sgn, base in [(-1,104),(1,112)]:
        g += (f'<path d="M{base},72 C{base+sgn*36},40 {base+sgn*74},40 {base+sgn*96},52 '
              f'C{base+sgn*72},52 {base+sgn*60},58 {base+sgn*66},66 '
              f'C{base+sgn*84},60 {base+sgn*92},70 {base+sgn*88},80 '
              f'C{base+sgn*66},70 {base+sgn*40},80 {base},92 Z" fill="url(#body{uid})"/>')
    g += f'<path d="M108,116 C96,132 92,142 84,148 C104,140 108,132 108,124 C108,132 112,140 132,148 C124,142 120,132 108,116 Z" fill="{pal[1]}"/>'
    g += f'<path d="M108,66 C122,66 128,84 122,104 C118,118 98,118 94,104 C88,84 94,66 108,66 Z" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="108" cy="96" rx="9" ry="14" fill="url(#belly{uid})" stroke="none"/>'
    g += f'<circle cx="108" cy="54" r="16" fill="url(#body{uid})"/>'
    g += f'<path d="M100,42 C96,30 100,22 104,16 C108,26 108,32 106,40 Z M108,40 C108,28 112,20 118,14 C120,26 118,34 114,42 Z" fill="{e["glow"]}" stroke="none"/>'
    g += f'<path d="M94,54 l-12,-3 l12,-3 Z" fill="{e["glow"]}"/>'
    g += eye(102,52,3.6,glow=e["glow"],look=-0.6,glowy=True)+eye(114,52,3.6,glow=e["glow"],look=-0.6,glowy=True)
    g += f'<circle cx="108" cy="86" r="5" fill="{e["glow"]}" stroke="#fff" stroke-width="1"/>'
    return g+'</g></g>'

def l_glaciera(uid, e, var):
    pal = e["pal"]; g = '<g>'
    g += f'<circle cx="108" cy="72" r="50" fill="none" stroke="#dff6ff" stroke-width="2" opacity=".35"/>'
    for k in range(12):
        a = k*math.pi/6; x1 = 108+math.cos(a)*40; y1 = 72+math.sin(a)*40; x2 = 108+math.cos(a)*60; y2 = 72+math.sin(a)*60
        g += f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#dff6ff" stroke-width="1" opacity=".2"/>'
    g += f'<g stroke="{pal[3]}" stroke-width="2.2" stroke-linejoin="round">'
    g += (f'<path d="M108,120 C82,122 72,104 88,94 C102,86 118,94 114,108 '
          f'C134,110 142,130 118,138 C92,146 66,134 66,110 C66,86 88,74 112,78 Z" fill="url(#body{uid})"/>')
    g += f'<path d="M84,92 L88,74 L96,90 Z M100,86 L106,66 L114,86 Z M118,90 L126,74 L128,96 Z" fill="#dff6ff" stroke="{pal[3]}" stroke-width="1.6"/>'
    g += f'<path d="M100,86 C96,66 100,50 108,44 C118,50 120,68 116,88 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M108,34 C122,34 130,46 128,58 C126,70 116,74 108,74 C100,74 90,70 88,58 C86,46 94,34 108,34 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M96,40 L88,22 L102,36 Z M120,40 L128,22 L114,36 Z" fill="#dff6ff" stroke="{pal[3]}" stroke-width="1.6"/>'
    g += eye(101,56,3.6,glow="#dff6ff",glowy=True,look=0.5)+eye(115,56,3.6,glow="#dff6ff",glowy=True,look=0.5)
    g += f'<path d="M104,66 q4,3 8,0" fill="none" stroke="{pal[3]}" stroke-width="1.5" stroke-linecap="round"/>'
    g += f'<path d="M108,98 l6,6 -6,6 -6,-6 Z" fill="#eafaff" stroke="#fff" stroke-width="1"/>'
    return g+'</g></g>'

def l_eldwyrm(uid, e, var):
    pal = e["pal"]; g = '<g>'
    g += f'<circle cx="108" cy="72" r="50" fill="none" stroke="{e["glow"]}" stroke-width="2" opacity=".3"/>'
    g += f'<g stroke="{pal[3]}" stroke-width="2.2" stroke-linejoin="round">'
    g += (f'<path d="M150,132 C120,140 96,130 98,112 C100,98 118,96 120,108 '
          f'C132,110 136,96 124,90 C104,80 76,90 74,112 C72,96 84,72 112,64 '
          f'C96,62 84,72 82,84 C74,72 84,52 108,48 C112,58 110,66 104,72 Z" fill="url(#body{uid})"/>')
    g += f'<path d="M104,72 C112,80 118,90 120,104 M112,64 C118,74 120,84 118,96" fill="none" stroke="#2f9e44" stroke-width="2.5" opacity=".7"/>'
    for x, y in [(110,80),(116,92),(120,104)]:
        g += f'<ellipse cx="{x}" cy="{y}" rx="5" ry="7" fill="#5fd35f" stroke="{pal[3]}" stroke-width="1.2" transform="rotate(30 {x} {y})"/>'
    g += f'<path d="M92,42 C104,34 120,36 124,48 C126,58 118,66 106,66 C96,66 86,60 86,52 C86,48 88,44 92,42 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M96,40 C90,26 86,20 88,12 C94,20 98,28 100,38 M96,30 l-8,-2 M100,34 l8,-4" fill="none" stroke="#7a5a2a" stroke-width="2.5" stroke-linecap="round"/>'
    g += f'<path d="M118,40 C124,26 128,20 126,12 C120,20 116,28 114,38 M118,30 l8,-2 M114,34 l-8,-4" fill="none" stroke="#7a5a2a" stroke-width="2.5" stroke-linecap="round"/>'
    g += f'<path d="M90,58 C78,60 70,58 62,52 M124,54 C136,56 144,54 152,48" fill="none" stroke="#5fd35f" stroke-width="2" stroke-linecap="round"/>'
    g += eye(100,50,3.4,glow=e["glow"],glowy=True,look=-0.6)+eye(114,50,3.4,glow=e["glow"],glowy=True,look=-0.6)
    g += f'<path d="M100,60 q6,3 12,0" fill="none" stroke="{pal[3]}" stroke-width="1.5" stroke-linecap="round"/>'
    return g+'</g></g>'

def l_voltaeon(uid, e, var):
    pal = e["pal"]; glow = e["glow"]; g = '<g>'
    g += f'<circle cx="108" cy="70" r="50" fill="none" stroke="{glow}" stroke-width="2" opacity=".38"/>'
    for k in range(12):
        a = k*math.pi/6; x2 = 108+math.cos(a)*60; y2 = 70+math.sin(a)*60; x1 = 108+math.cos(a)*42; y1 = 70+math.sin(a)*42
        g += f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{glow}" stroke-width="1.3" opacity=".2"/>'
    g += f'<g stroke="{pal[3]}" stroke-width="2.3" stroke-linejoin="round">'
    g += f'<ellipse cx="108" cy="140" rx="38" ry="6" fill="#000" opacity=".28" stroke="none"/>'
    g += f'<polyline points="120,112 140,104 130,118 152,110 138,128 158,122" fill="none" stroke="{glow}" stroke-width="3.5" stroke-linejoin="round"/>'
    g += f'<path d="M98,112 C92,124 92,134 96,142 L107,142 C107,132 106,120 108,114 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M118,112 C124,124 124,134 120,142 L109,142 C109,132 110,120 108,114 Z" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="97" cy="143" rx="8" ry="4" fill="url(#body{uid})"/><ellipse cx="119" cy="143" rx="8" ry="4" fill="url(#body{uid})"/>'
    g += f'<path d="M108,74 C121,74 126,92 121,114 C117,124 99,124 95,114 C90,92 95,74 108,74 Z" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="108" cy="102" rx="9" ry="15" fill="url(#belly{uid})" stroke="none"/>'
    g += f'<path d="M97,84 C84,80 76,70 74,58 C80,64 86,66 92,70 C90,76 92,80 97,82 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M119,84 C132,80 140,70 142,58 C136,64 130,66 124,70 C126,76 124,80 119,82 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M74,58 l-3,-5 M74,58 l-5,-1 M74,58 l1,-6 M142,58 l3,-5 M142,58 l5,-1 M142,58 l-1,-6" fill="none" stroke="{pal[3]}" stroke-width="1.6" stroke-linecap="round"/>'
    g += f'<circle cx="108" cy="62" r="15" fill="url(#body{uid})"/>'
    g += f'<path d="M99,52 L94,34 L107,50 Z M117,52 L122,34 L109,50 Z" fill="{glow}" stroke="{pal[3]}" stroke-width="1.4"/>'
    for i, (mx, my) in enumerate([(101,76),(108,74),(115,76)]):
        g += f'<polyline points="{mx-4},{my+6} {mx},{my-8} {mx+3},{my-1} {mx+7},{my-7} {mx+8},{my+5}" fill="{glow if i%2 else pal[0]}" stroke="{pal[3]}" stroke-width="1.2"/>'
    g += eye(102,60,3.6,glow=glow,glowy=True,look=0.5)+eye(114,60,3.6,glow=glow,glowy=True,look=0.5)
    g += f'<path d="M104,69 q4,3 8,0" fill="none" stroke="{pal[3]}" stroke-width="1.5" stroke-linecap="round"/>'
    return g+'</g></g>'

def l_nyxaros(uid, e, var):
    pal = e["pal"]; g = '<g>'
    g += f'<circle cx="108" cy="74" r="52" fill="none" stroke="{e["glow"]}" stroke-width="2" opacity=".35"/>'
    g += f'<ellipse cx="108" cy="74" rx="70" ry="46" fill="#7a3fd0" opacity=".12"/>'
    g += f'<g stroke="{pal[3]}" stroke-width="2.4" stroke-linejoin="round">'
    g += f'<ellipse cx="108" cy="136" rx="50" ry="7" fill="#000" opacity=".3" stroke="none"/>'
    g += f'<path d="M58,116 C56,96 76,84 104,84 C134,84 154,94 150,114 C146,128 120,130 108,126 C96,130 70,130 58,116 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M150,108 C172,104 182,84 176,64 C190,84 188,116 156,120 Z" fill="url(#body{uid})"/>'
    g += star(180,58,4,"#fff",0.95)
    for lx in (78,132):
        g += f'<rect x="{lx-6}" y="116" width="13" height="26" rx="6.5" fill="url(#body{uid})"/>'
    g += f'<rect x="98" y="118" width="12" height="24" rx="6" fill="{pal[2]}"/>'
    g += f'<path d="M58,92 C46,84 42,70 48,60 C56,52 72,54 78,64 C84,74 78,88 68,92 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M52,58 L46,42 L62,54 Z M70,56 L78,42 L82,58 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M46,66 q7,-5 15,-1 q-6,6 -15,3 Z" fill="{e["glow"]}" stroke="none"/><circle cx="53" cy="66" r="2.4" fill="#1a1020" stroke="none"/>'
    g += f'<ellipse cx="40" cy="72" rx="3.4" ry="2.6" fill="#20141f" stroke="none"/>'
    g += f'<path d="M45,70 q6,4 12,2" fill="none" stroke="{pal[3]}" stroke-width="1.5" stroke-linecap="round"/>'
    for x, y, r in [(92,100,1.6),(112,96,1.5),(128,104,1.5),(104,112,1.3),(74,104,1.3),(140,100,1.3)]:
        g += star(x, y, r, "#fff", 0.85)
    return g+'</g></g>'

def l_ignarok(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<circle cx="108" cy="66" r="52" fill="none" stroke="{glow}" stroke-width="2" opacity=".3"/>'
    g += f'<g stroke="{st}" stroke-width="2.4" stroke-linejoin="round">'
    g += f'<ellipse cx="108" cy="140" rx="46" ry="7" fill="#000" opacity=".3" stroke="none"/>'
    for lx in (94,122):
        g += f'<rect x="{lx-9}" y="106" width="18" height="36" rx="7" fill="url(#body2{uid})"/>'
    g += f'<path d="M76,74 C60,80 54,98 58,114 L69,111 C66,98 72,88 84,84 Z" fill="url(#body2{uid})"/>'
    g += f'<path d="M140,74 C156,80 162,98 158,114 L147,111 C150,98 144,88 132,84 Z" fill="url(#body2{uid})"/>'
    g += f'<path d="M108,54 C132,54 142,80 136,110 C130,124 86,124 80,110 C74,80 84,54 108,54 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M108,72 l9,16 -7,4 9,14 M108,72 l-9,16 7,4 -9,14" fill="none" stroke="{glow}" stroke-width="2.4"/>'
    g += f'<circle cx="108" cy="48" r="16" fill="url(#body{uid})"/>'
    g += f'<path d="M96,42 C82,30 76,18 80,8 C92,18 98,30 100,40 Z M120,42 C134,30 140,18 136,8 C124,18 118,30 116,40 Z" fill="url(#body2{uid})" stroke="{st}" stroke-width="1.8"/>'
    for i, mx in enumerate((98,108,118)):
        g += tuft("fire", mx, 32, 11, e, (i-1)*16)
    g += eye(101,48,3.4,glow=glow,glowy=True,look=0,angry=True)+eye(115,48,3.4,glow=glow,glowy=True,look=0,angry=True)
    g += f'<path d="M99,56 q9,7 18,0 l-3,7 -6,-4 -6,4 Z" fill="#fff" stroke="{st}" stroke-width="1"/>'
    return g+'</g></g>'

def l_solmyr(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<circle cx="108" cy="70" r="42" fill="url(#orb{uid})" opacity=".45"/>'
    for k in range(20):
        a = k*math.pi/10; ext = 60+(6 if k % 2 else 0)
        x1 = 108+math.cos(a)*44; y1 = 70+math.sin(a)*44; x2 = 108+math.cos(a)*ext; y2 = 70+math.sin(a)*ext
        g += f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{glow}" stroke-width="2" opacity=".4"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    g += f'<path d="M108,116 C82,116 70,98 86,88 C100,80 118,88 112,102 C132,104 140,124 116,132 C90,140 64,128 66,104 C68,82 90,72 114,76 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M92,86 L96,68 L104,84 Z M106,80 L112,60 L120,80 Z" fill="{glow}" stroke="{st}" stroke-width="1.4"/>'
    g += f'<path d="M96,58 C88,50 90,38 100,34 C112,34 118,44 116,56 C114,66 104,68 96,58 Z" fill="url(#body{uid})"/>'
    g += eye(100,50,3.2,glow=glow,glowy=True,look=0.4)+eye(112,50,3.2,glow=glow,glowy=True,look=0.4)
    g += f'<circle cx="108" cy="98" r="6" fill="url(#orb{uid})"/>'
    return g+'</g></g>'

def l_abyssos(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<ellipse cx="108" cy="84" rx="82" ry="54" fill="#04122e" opacity=".5"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    g += f'<ellipse cx="108" cy="132" rx="40" ry="6" fill="#000" opacity=".3" stroke="none"/>'
    g += f'<path d="M150,86 l26,-16 l-6,20 l14,10 l-30,4 Z" fill="url(#body2{uid})"/>'
    g += f'<ellipse cx="104" cy="90" rx="48" ry="40" fill="url(#body{uid})"/>'
    g += f'<path d="M60,92 Q104,84 148,96 Q120,124 90,120 Q68,112 60,92 Z" fill="{pal[3]}"/>'
    g += '<g fill="#eaf6ff">'
    for i in range(7):
        g += f'<path d="M{66+i*11},{93} l3,9 l4,-9 Z"/>'
    for i in range(6):
        g += f'<path d="M{74+i*11},{114} l3,-8 l4,8 Z"/>'
    g += '</g>'
    g += f'<path d="M96,54 q-6,-18 12,-26" fill="none" stroke="{pal[2]}" stroke-width="2.4"/>'
    g += f'<circle cx="110" cy="26" r="11" fill="{glow}" opacity=".25"/><circle cx="110" cy="26" r="6" fill="url(#orb{uid})"/>'
    g += eye(86,80,4,glow=glow,glowy=True,look=-0.6)
    return g+'</g></g>'

def l_maelstros(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += '<g fill="none" stroke="'+pal[1]+'" stroke-width="3" opacity=".5">'
    for r in (40, 30, 20):
        g += f'<path d="M{108-r},124 a{r},{r*0.4:.1f} 0 1 0 {2*r},0"/>'
    g += '</g>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    g += (f'<path d="M92,124 C80,104 96,92 110,96 C100,84 104,66 118,60 C112,74 118,84 128,88 '
          f'C140,94 138,112 122,116 C132,118 134,128 124,132 C108,136 96,132 92,124 Z" fill="url(#body{uid})"/>')
    g += f'<path d="M114,60 q-6,-14 6,-20 q0,10 6,14 q6,-8 12,-6 q-4,8 2,14" fill="none" stroke="#eaf6ff" stroke-width="2.4"/>'
    g += f'<path d="M110,58 C104,50 108,38 118,36 C128,38 132,48 128,58 C124,66 116,66 110,58 Z" fill="url(#body{uid})"/>'
    g += eye(114,48,3.2,glow=glow,glowy=True,look=0.4)+eye(124,48,3.0,glow=glow,glowy=True,look=0.4)
    g += f'<path d="M108,90 l6,6 -6,6 -6,-6 Z" fill="#eaf6ff"/>'
    return g+'</g></g>'

def l_sylvareth(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<circle cx="80" cy="52" r="46" fill="none" stroke="{glow}" stroke-width="2" opacity=".28"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    g += f'<ellipse cx="108" cy="140" rx="42" ry="6" fill="#000" opacity=".26" stroke="none"/>'
    for lx in (88, 100, 118, 130):
        g += f'<line x1="{lx}" y1="106" x2="{lx}" y2="138" stroke="url(#body2{uid})" stroke-width="6" stroke-linecap="round"/>'
    g += f'<ellipse cx="110" cy="98" rx="36" ry="18" fill="url(#body{uid})"/>'
    g += f'<path d="M84,98 C72,82 72,64 84,56 L96,64 C90,74 92,88 100,98 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M70,58 C60,52 60,40 72,36 C84,34 92,44 88,56 C85,64 78,64 70,58 Z" fill="url(#body{uid})"/>'
    g += '<g fill="none" stroke="url(#body2'+uid+')" stroke-width="3" stroke-linecap="round">'
    for sgn in (-1, 1):
        g += f'<path d="M74,40 q{sgn*4},-16 {sgn*2},-28 M{74+sgn*2},20 q{sgn*12},-2 {sgn*18},-10 M{74+sgn*1},12 q{sgn*10},-4 {sgn*12},-14"/>'
    g += '</g>'
    for x, y in [(60,12),(50,6),(92,10),(98,2)]:
        g += tuft("grass", x, y, 7, ELE["grass"], 8)
    g += eye(72,48,3.2,glow=glow,glowy=True,look=-0.6)
    g += f'<circle cx="114" cy="96" r="7" fill="url(#orb{uid})"/>'
    return g+'</g></g>'

def l_floreon(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<circle cx="108" cy="66" r="48" fill="none" stroke="{glow}" stroke-width="2" opacity=".28"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    g += f'<ellipse cx="108" cy="138" rx="44" ry="7" fill="#000" opacity=".26" stroke="none"/>'
    for k in range(10):
        a = k*math.pi/5; px = 108+math.cos(a)*30; py = 64+math.sin(a)*30
        g += tuft(e["acc"], px, py, 12, e, math.degrees(a)+90)
    g += f'<path d="M74,120 C70,98 88,88 108,88 C128,88 146,98 142,120 C136,132 80,132 74,120 Z" fill="url(#body{uid})"/>'
    for lx in (86, 130):
        g += f'<rect x="{lx-7}" y="116" width="15" height="24" rx="7" fill="url(#body{uid})"/>'
    g += f'<circle cx="108" cy="64" r="20" fill="url(#body{uid})"/>'
    g += eye(100,64,3.4,glow=glow,glowy=True,look=0)+eye(116,64,3.4,glow=glow,glowy=True,look=0)
    g += f'<path d="M102,72 q6,5 12,0" fill="none" stroke="{st}" stroke-width="1.5"/>'
    g += f'<circle cx="108" cy="66" r="3" fill="{st}"/>'
    return g+'</g></g>'

def l_fulguros(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<circle cx="108" cy="70" r="50" fill="none" stroke="{glow}" stroke-width="2" opacity=".35"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    for sgn in (-1, 1):
        g += f'<path d="M108,74 L{108+sgn*30},60 L{108+sgn*20},66 L{108+sgn*54},52 L{108+sgn*40},64 L{108+sgn*72},60 L{108+sgn*44},80 L108,86 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M108,68 C120,68 124,86 118,104 C114,114 102,114 98,104 C92,86 96,68 108,68 Z" fill="url(#body{uid})"/>'
    g += f'<ellipse cx="108" cy="96" rx="8" ry="12" fill="url(#belly{uid})" stroke="none"/>'
    g += f'<polyline points="102,112 96,128 104,124 100,140" fill="none" stroke="{glow}" stroke-width="3"/>'
    g += f'<polyline points="114,112 120,128 112,124 116,140" fill="none" stroke="{glow}" stroke-width="3"/>'
    g += f'<circle cx="108" cy="56" r="13" fill="url(#body{uid})"/>'
    g += f'<polygon points="104,44 116,44 108,30 112,42 100,42 108,52" fill="{glow}" stroke="{st}" stroke-width="1.2"/>'
    g += f'<path d="M95,56 l-9,-2 l9,-4 Z" fill="{glow}"/>'
    g += eye(103,54,3,glow=glow,glowy=True,look=-0.6)+eye(114,54,3,glow=glow,glowy=True,look=-0.6)
    return g+'</g></g>'

def l_tempesta(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    g += f'<path d="M96,138 L84,96 Q108,104 132,96 L120,138 Z" fill="url(#body2{uid})" opacity=".85"/>'
    g += f'<path d="M64,86 a20,20 0 0 1 6,-30 a26,26 0 0 1 44,-6 a22,22 0 0 1 34,14 a18,18 0 0 1 -8,34 Q108,96 64,86 Z" fill="url(#body{uid})"/>'
    g += f'<polyline points="90,92 84,110 92,106 86,124" fill="none" stroke="{glow}" stroke-width="3"/>'
    g += f'<polyline points="122,92 128,110 120,106 126,124" fill="none" stroke="{glow}" stroke-width="3"/>'
    g += f'<polyline points="108,96 104,116 112,112 106,132" fill="none" stroke="{glow}" stroke-width="3.4"/>'
    g += eye(98,66,4,glow=glow,glowy=True,look=0,angry=True)+eye(120,66,4,glow=glow,glowy=True,look=0,angry=True)
    g += f'<path d="M100,78 q9,6 18,0" fill="none" stroke="{st}" stroke-width="1.8"/>'
    return g+'</g></g>'

def l_astralon(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<g stroke="{st}" stroke-width="2.2" stroke-linejoin="round">'
    body = ('M150,128 C120,136 96,126 98,108 C100,94 118,92 120,104 C132,106 136,92 124,86 '
            'C104,76 78,88 76,110 C74,92 86,68 112,60 C96,58 84,70 82,82 C74,70 86,50 110,46 Z')
    g += f'<path d="{body}" fill="url(#body{uid})" opacity=".85"/>'
    g += f'<path d="M96,54 C90,46 94,34 104,32 C114,32 120,42 118,52 C116,62 106,64 96,54 Z" fill="url(#body{uid})"/>'
    g += '</g>'
    nodes = [(150,128),(112,112),(120,104),(100,96),(112,78),(96,70),(110,52)]
    g += '<g stroke="'+glow+'" stroke-width="1.2" opacity=".85">'
    for i in range(len(nodes)-1):
        g += f'<line x1="{nodes[i][0]}" y1="{nodes[i][1]}" x2="{nodes[i+1][0]}" y2="{nodes[i+1][1]}"/>'
    g += '</g>'
    for (x, y) in nodes:
        g += star(x, y, 3, glow, 1)
    g += star(108, 24, 4, glow, 1)
    g += eye(100,48,3,glow=glow,glowy=True,look=0.4)+eye(112,48,3,glow=glow,glowy=True,look=0.4)
    return g+'</g>'

def l_eclipsar(uid, e, var):
    pal, glow, st = e["pal"], e["glow"], e["pal"][3]; g = '<g>'
    g += f'<circle cx="108" cy="64" r="26" fill="{glow}" opacity=".3"/>'
    for k in range(16):
        a = k*math.pi/8; x1 = 108+math.cos(a)*24; y1 = 64+math.sin(a)*24; x2 = 108+math.cos(a)*38; y2 = 64+math.sin(a)*38
        g += f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="{glow}" stroke-width="1.4" opacity=".5"/>'
    g += f'<g stroke="{st}" stroke-width="2.3" stroke-linejoin="round">'
    for sgn in (-1, 1):
        g += f'<path d="M108,92 C{108+sgn*30},72 {108+sgn*66},72 {108+sgn*88},84 C{108+sgn*64},84 {108+sgn*54},90 {108+sgn*60},98 C{108+sgn*40},90 {108+sgn*24},98 108,108 Z" fill="url(#body{uid})"/>'
        g += star(108+sgn*50,86,2.4,glow,1)+star(108+sgn*32,94,2,glow,.9)
    g += f'<path d="M108,96 C118,96 122,110 117,126 C113,134 103,134 99,126 C94,110 98,96 108,96 Z" fill="url(#body{uid})"/>'
    g += f'<path d="M108,128 l-8,16 8,-6 8,6 Z" fill="url(#body2{uid})"/>'
    g += f'<circle cx="108" cy="64" r="20" fill="#0b0620"/><circle cx="108" cy="64" r="21" fill="none" stroke="{glow}" stroke-width="2"/>'
    g += eye(103,62,3,glow=glow,glowy=True,look=0)+eye(114,62,3,glow=glow,glowy=True,look=0)
    return g+'</g></g>'

# ------------------------------------------------------------------- registries
ARCH = {
    "canine": a_canine, "golem": a_golem, "lord": a_lord, "bird": a_bird,
    "saber": a_saber, "dragon": a_dragon, "shark": a_shark, "don": a_don,
    "bear": a_bear, "fish": a_fish, "beetle": a_beetle, "lynx": a_lynx,
    "plant": a_plant, "moth": a_moth, "crab": a_crab, "fox": a_fox,
    "sprout": a_sprout, "hare": a_hare, "mite": a_mite, "wisp": a_wisp,
    "snail": a_snail, "fly": a_fly, "toad": a_toad, "glow": a_glow,
    "maw": a_maw, "horn": a_horn, "majestic": a_majestic,
}
LEG = {
    "Emberyx": l_emberyx, "Ignarok": l_ignarok, "Solmyr": l_solmyr,
    "Glaciera": l_glaciera, "Abyssos": l_abyssos, "Maelstros": l_maelstros,
    "Eldwyrm": l_eldwyrm, "Sylvareth": l_sylvareth, "Floreon": l_floreon,
    "Voltaeon": l_voltaeon, "Fulguros": l_fulguros, "Tempesta": l_tempesta,
    "Nyxaros": l_nyxaros, "Astralon": l_astralon, "Eclipsar": l_eclipsar,
}

# ------------------------------------------------------------------- composition
with open(os.path.join(ROOT, "data", "cards.json")) as f:
    CARDS = json.load(f)

def art_inner(card):
    el = card["element"]; e = ELE[el]; uid = card["id"].replace("-", "_")
    role = ROLES[card["name"]]; var = vary(card["name"])
    s = defs(uid, e) + SCENES[card["set"]](uid)
    if role["leg"]:
        s += LEG[role["leg"]](uid, e, var)
    else:
        s += ARCH[role["slot"]](uid, e, role["stage"], role["sc"], var)
    return s

def art_svg(card):
    return f'<svg viewBox="0 0 {VB_W} {VB_H}" xmlns="http://www.w3.org/2000/svg">{art_inner(card)}</svg>'

def _xml(s):
    return s.replace("&", "&amp;").replace("<", "&lt;")

def qa_sheet(setno, out_dir="/tmp"):
    """Contact sheet of all 50 cards in a set (Chrome-free, via rsvg)."""
    import subprocess
    cards = sorted([c for c in CARDS if c["set"] == setno], key=lambda c: c["number"])
    cols, cw, pad, gap, ch = 5, 216, 16, 12, 186
    rows = (len(cards) + cols - 1) // cols
    sw = pad + cols * (cw + gap)
    sh = pad + rows * (ch + gap)
    body = f'<rect width="{sw}" height="{sh}" fill="#0e1118"/>'
    for i, c in enumerate(cards):
        cx = pad + (i % cols) * (cw + gap)
        cy = pad + (i // cols) * (ch + gap)
        role = ROLES[c["name"]]; tag = role["leg"] or f'{role["slot"]}{role["stage"]}'
        body += f'<g transform="translate({cx},{cy})">'
        body += f'<rect x="-5" y="-5" width="{cw+10}" height="{ch+6}" rx="9" fill="#171a22"/>'
        body += f'<svg x="0" y="0" width="{cw}" height="150" viewBox="0 0 {VB_W} {VB_H}">{art_inner(c)}</svg>'
        body += (f'<text x="2" y="169" font-family="Helvetica,Arial,sans-serif" font-size="12" '
                 f'font-weight="600" fill="#e8ecf4">{c["number"]:03d} {_xml(c["name"])}</text>')
        body += (f'<text x="2" y="181" font-family="Helvetica,Arial,sans-serif" font-size="10" '
                 f'fill="#8b93a6">{c["element"]} \u00b7 {tag}</text>')
        body += '</g>'
    svg = f'<svg xmlns="http://www.w3.org/2000/svg" width="{sw}" height="{sh}" viewBox="0 0 {sw} {sh}">{body}</svg>'
    sp = os.path.join(out_dir, f"qa_set{setno}.svg")
    open(sp, "w").write(svg)
    out = os.path.join(out_dir, f"qa_set{setno}.png")
    subprocess.run(["rsvg-convert", sp, "-o", out], check=True)
    print("wrote", out)

CARDART = os.path.join(ROOT, "TradingUp", "Assets.xcassets", "CardArt")
MOCKART = os.path.join(ROOT, "design", "mockups", "art")

def _contents_json(fid):
    return json.dumps({
        "images": [{"filename": f"{fid}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2)

def build_assets():
    import subprocess, concurrent.futures
    for d in (CARDART, MOCKART):
        os.makedirs(d, exist_ok=True)
    jobs = []
    for c in CARDS:
        fid = c["id"]
        svg = art_svg(c)
        svg_path = os.path.join(MOCKART, f"{fid}.svg")
        open(svg_path, "w").write(svg)
        iset = os.path.join(CARDART, f"{fid}.imageset")
        os.makedirs(iset, exist_ok=True)
        open(os.path.join(iset, "Contents.json"), "w").write(_contents_json(fid))
        jobs.append((svg_path, os.path.join(iset, f"{fid}.png")))

    def render_one(job):
        svg_path, png = job
        subprocess.run(["rsvg-convert", "-w", "864", "-h", "600", svg_path, "-o", png],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return png

    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        for _ in ex.map(render_one, jobs):
            done += 1
    missing = [j[1] for j in jobs if not os.path.exists(j[1]) or os.path.getsize(j[1]) < 200]
    print(f"done: {done} rendered, {len(missing)} missing/empty")
    if missing:
        print("MISSING:", missing[:10])

if __name__ == "__main__":
    import sys
    cmd = sys.argv[1] if len(sys.argv) >= 2 else ""
    if cmd == "qa":
        which = [int(sys.argv[2])] if len(sys.argv) >= 3 else [1, 2, 3, 4, 5]
        for n in which:
            qa_sheet(n)
    elif cmd == "assets":
        build_assets()
    else:
        print("usage: generate_art.py [assets | qa [setno]]")
