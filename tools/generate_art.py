#!/usr/bin/env python3
"""Spryte card art — 250 individually designed creature illustrations.

Every card is its own creature. Nothing is a recolour of anything else:

  * Each **set has its own design language** (see SETSTYLE below) that changes the
    actual geometry — torso silhouette, limbs, head, eyes, mouth, crest, tail and
    surface treatment — not just the palette.
  * Each **slot** (canine, golem, dragon, moth, ...) gets a *different concept per
    set*: SLOT_BASE holds the family default, SET_OVR replaces body plan, build,
    head, crest, tail and flourishes per (set, slot), and resolve() merges them.
    Emberfall's hound and Umbral Reach's hound share a name suffix and nothing else.
  * Each **evolution stage** adds real structure (horns, manes, wings, extra
    limbs, orbiting shards), so a stage 3 is never a scaled-up stage 1.
  * The 15 ultra legendaries stay fully bespoke.

`dupes` proves it: it hashes each creature's geometry with palette and elemental
accents stripped out, and fails if two cards resolve to the same character design.

Commands (needs `rsvg-convert` from librsvg: `brew install librsvg`):
  python3 tools/generate_art.py assets    # (re)render the 250 card assets + mockup SVGs
  python3 tools/generate_art.py qa [n]    # QA contact sheet(s) to /tmp for review
  python3 tools/generate_art.py dupes     # assert all 250 designs are distinct

Outputs:
  - asset PNGs  TradingUp/Assets.xcassets/CardArt/<id>.imageset/<id>.png  (864x600)
  - mockup SVGs docs/mockups/art/<id>.svg
  - QA sheets   /tmp/qa_set{n}.png  (all 50 of a set in a grid)
The app (CardView) shows these via UIImage(named: card.id); SigilView is the fallback.
"""
import json, os, math, hashlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HERE = os.path.dirname(os.path.abspath(__file__))
VB_W, VB_H = 216, 150

# --------------------------------------------------------------- element palettes
ELE = {
    "fire":     dict(pal=["#ffe08a", "#ff8a2a", "#e01f1f", "#4a0f04"], glow="#ffd15c", acc="fire"),
    "rock":     dict(pal=["#f4cf94", "#c98a3c", "#7a4a24", "#2c1a0c"], glow="#ffcf8a", acc="rock"),
    "water":    dict(pal=["#c2f0ff", "#4bb6ff", "#1e5bd6", "#08245c"], glow="#bff0ff", acc="water"),
    "grass":    dict(pal=["#dcffa8", "#78dd63", "#2f9e44", "#123f1e"], glow="#eaffb4", acc="grass"),
    "electric": dict(pal=["#fff6b0", "#ffd21a", "#f5a300", "#5a3d00"], glow="#fff6b0", acc="electric"),
    "shadow":   dict(pal=["#e2c8ff", "#a06cf6", "#5b2bb3", "#160a2e"], glow="#ecd8ff", acc="shadow"),
}

# ------------------------------------------------------------ per-set design DNA
# Every set draws from a different shape language. These are the knobs the
# morphology primitives read; the primitives themselves branch on set number.
SETSTYLE = {
    1: dict(name="Emberfall",    crust="#2b1109", seam="#ff7a1a", ash="#5a4038", ember="#ffbf5c"),
    2: dict(name="Tidecaller",   ice="#e6fbff",   deep="#062a63", foam="#ffffff", kelp="#0f7d7d"),
    3: dict(name="Verdspire",    bark="#6b4a24",  leaf="#2f9e44", bloom="#ff9ec7", spore="#f4ffce"),
    4: dict(name="Voltcrest",    metal="#98a3bd", arc="#fff6b0",  rubber="#241f14", copper="#e8a83c"),
    5: dict(name="Umbral Reach", void="#0a0518",  star="#ffffff", neb="#8a5cf0",   rift="#ff9bf5"),
}
# Every style carries every key so per-set lookup tables can be written inline.
_STYDEF = dict(crust="#2b1109", seam="#ff7a1a", ash="#5a4038", ember="#ffbf5c",
               ice="#e6fbff", deep="#062a63", foam="#ffffff", kelp="#0f7d7d",
               bark="#6b4a24", leaf="#2f9e44", bloom="#ff9ec7", spore="#f4ffce",
               metal="#98a3bd", arc="#fff6b0", rubber="#241f14", copper="#e8a83c",
               void="#0a0518", star="#ffffff", neb="#8a5cf0", rift="#ff9bf5", coral="#ff9a6b")
SETSTYLE = {k: dict(_STYDEF, **v) for k, v in SETSTYLE.items()}


def H(s):
    return int(hashlib.md5(s.encode()).hexdigest(), 16)


class Rng:
    """Tiny deterministic LCG so art never shifts between runs."""

    def __init__(self, seed):
        self.s = (seed ^ 0x9E3779B9) & 0x7FFFFFFF or 1

    def nxt(self):
        self.s = (1103515245 * self.s + 12345) & 0x7FFFFFFF
        return self.s

    def f(self, a=0.0, b=1.0):
        return a + (b - a) * (self.nxt() / 0x7FFFFFFF)

    def i(self, a, b):
        return a + self.nxt() % (b - a + 1)

    def pick(self, seq):
        return seq[self.nxt() % len(seq)]


def vary(name):
    h = H(name)
    return dict(
        spots=(h & 3),
        marks=1 + ((h >> 2) & 2),
        jitter=((h >> 5) & 7) - 3.5,
        flip=(h >> 8) & 1,
        seed=h & 0x7FFFFFFF,
    )


# ------------------------------------------------------------------ svg plumbing
class Ctx:
    """Per-card drawing context: set DNA, palette, unique ids, extra <defs>."""

    def __init__(self, uid, e, setno, var, name=""):
        self.uid, self.e, self.s, self.var, self.name = uid, e, setno, var, name
        self.sty = SETSTYLE[setno]
        self.pal = e["pal"]
        self.glow = e["glow"]
        self.ink = "#cbb6ff" if setno == 5 else e["pal"][3]
        self.el = e["acc"]
        self.n = 0
        self.defs = []

    def nid(self, tag):
        self.n += 1
        return f"{tag}{self.uid}_{self.n}"

    def rng(self, salt=0):
        return Rng(self.var["seed"] + salt * 7919)


def fmt(*vals):
    return " ".join(f"{v:.1f}" for v in vals)


# ------------------------------------------------------------- shape vocabulary
def smooth_poly(pts):
    """Closed curve through the midpoints of a point ring (organic silhouette)."""
    n = len(pts)
    mids = [((pts[i][0] + pts[(i + 1) % n][0]) / 2, (pts[i][1] + pts[(i + 1) % n][1]) / 2) for i in range(n)]
    d = f"M{mids[-1][0]:.1f},{mids[-1][1]:.1f}"
    for i in range(n):
        d += f" Q{pts[i][0]:.1f},{pts[i][1]:.1f} {mids[i][0]:.1f},{mids[i][1]:.1f}"
    return d + " Z"


def sharp_poly(pts):
    return "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts) + " Z"


def ring(cx, cy, rx, ry, n, seed, amp=0.14, phase=0.0):
    r = Rng(seed)
    return [(cx + math.cos(2 * math.pi * i / n + phase) * rx * (1 - amp + 2 * amp * r.f()),
             cy + math.sin(2 * math.pi * i / n + phase) * ry * (1 - amp + 2 * amp * r.f()))
            for i in range(n)]


def crag(cx, cy, rx, ry, seed, n=11, amp=0.16):
    """Fractured volcanic mass: hard corners, uneven crust."""
    return sharp_poly(ring(cx, cy, rx, ry, n, seed, amp))


def teardrop(cx, cy, rx, ry, tilt=0.0):
    """Streamlined hydrodynamic mass, blunt at the left, tapered right."""
    return (f"M{cx - rx:.1f},{cy + tilt:.1f} "
            f"C{cx - rx:.1f},{cy - ry * 1.28:.1f} {cx + rx * 0.34:.1f},{cy - ry * 1.05:.1f} {cx + rx:.1f},{cy - ry * 0.22:.1f} "
            f"C{cx + rx * 1.05:.1f},{cy + ry * 0.1:.1f} {cx + rx * 0.4:.1f},{cy + ry * 1.16:.1f} {cx - rx:.1f},{cy + tilt:.1f} Z")


def lobed(cx, cy, rx, ry, seed, lobes=3):
    """Mossy overgrown mass: rounded, asymmetric, budding upward."""
    r = Rng(seed)
    pts = []
    n = 9
    for i in range(n):
        a = 2 * math.pi * i / n
        k = 1.0 + (0.2 * math.sin(lobes * a + r.f(0, 2)) if math.sin(a) < 0 else 0.02)
        pts.append((cx + math.cos(a) * rx * k, cy + math.sin(a) * ry * k))
    return smooth_poly(pts)


def chamfer(cx, cy, rx, ry, cut=0.34):
    """Machined hard-edged chassis: an octagon with bevelled corners."""
    cx_, cy_ = cx, cy
    kx, ky = rx * cut, ry * cut
    return sharp_poly([
        (cx_ - rx, cy_ - ry + ky), (cx_ - rx + kx, cy_ - ry), (cx_ + rx - kx, cy_ - ry),
        (cx_ + rx, cy_ - ry + ky), (cx_ + rx, cy_ + ry - ky), (cx_ + rx - kx, cy_ + ry),
        (cx_ - rx + kx, cy_ + ry), (cx_ - rx, cy_ + ry - ky),
    ])


def riftshape(cx, cy, rx, ry, seed, bite=0.5):
    """Void mass with a crescent torn out of it — nothing here is fully solid."""
    r = Rng(seed)
    pts = ring(cx, cy, rx, ry, 10, seed, 0.1)
    d = smooth_poly(pts)
    ang = r.f(-0.5, 0.5) + 0.6
    bx, by = cx + math.cos(ang) * rx * 0.72, cy + math.sin(ang) * ry * 0.5
    br = min(rx, ry) * bite
    d += (f" M{bx - br:.1f},{by:.1f} a{br:.1f},{br * 0.86:.1f} 0 1 0 {br * 2:.1f},0 "
          f"a{br * 0.72:.1f},{br * 0.62:.1f} 0 1 1 {-br * 2:.1f},0 Z")
    return d


def starfield(x, y, w, h, seed, count=22, tint="#ffffff"):
    r = Rng(seed)
    out = ""
    for _ in range(count):
        px, py = x + r.f(0, w), y + r.f(0, h)
        rad = r.f(0.35, 1.5)
        out += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{rad:.2f}" fill="{tint}" opacity="{r.f(0.35, 1):.2f}"/>'
    for _ in range(3):
        px, py = x + r.f(0, w), y + r.f(0, h)
        out += star(px, py, r.f(1.6, 2.8), tint, 0.9)
    return out


def eye(cx, cy, r, glow="#fff", look=0.6, angry=False, glowy=False):
    base = glow if glowy else "#ffffff"
    pupil = "#1a1020"
    s = f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{r:.1f}" ry="{r * 1.14:.1f}" fill="{base}"/>'
    s += f'<circle cx="{cx + look:.1f}" cy="{cy + r * 0.12:.1f}" r="{r * 0.6:.1f}" fill="{pupil}"/>'
    s += f'<circle cx="{cx - r * 0.24 + look:.1f}" cy="{cy - r * 0.36:.1f}" r="{r * 0.24:.1f}" fill="#fff"/>'
    if angry:
        s += (f'<path d="M{cx - r * 1.3:.1f},{cy - r * 1.5:.1f} L{cx + r * 1.1:.1f},{cy - r * 0.5:.1f}" '
              f'stroke="{pupil}" stroke-width="{r * 0.5:.1f}" stroke-linecap="round"/>')
    return s


def star(x, y, r, c="#fff", op=0.9):
    return (f'<path d="M{x:.1f},{y - r:.1f} L{x + r * 0.28:.1f},{y - r * 0.28:.1f} L{x + r:.1f},{y:.1f} '
            f'L{x + r * 0.28:.1f},{y + r * 0.28:.1f} L{x:.1f},{y + r:.1f} L{x - r * 0.28:.1f},{y + r * 0.28:.1f} '
            f'L{x - r:.1f},{y:.1f} L{x - r * 0.28:.1f},{y - r * 0.28:.1f} Z" fill="{c}" opacity="{op}"/>')


def tuft(el, cx, cy, s, e, rot=0):
    """Small elemental motif — a flame, droplet, leaf, bolt, shard or star."""
    pal, glow, stroke = e["pal"], e["glow"], e["pal"][3]
    g = f'<g transform="rotate({rot:.0f} {cx:.1f} {cy:.1f})" stroke="{stroke}" stroke-width="1.1" stroke-linejoin="round">'
    if el == "fire":
        g += (f'<path d="M{cx:.1f},{cy + s:.1f} C{cx - 0.8 * s:.1f},{cy + 0.2 * s:.1f} {cx - 0.5 * s:.1f},{cy - 0.4 * s:.1f} {cx:.1f},{cy - s:.1f} '
              f'C{cx + 0.5 * s:.1f},{cy - 0.4 * s:.1f} {cx + 0.8 * s:.1f},{cy + 0.2 * s:.1f} {cx:.1f},{cy + s:.1f} Z" fill="{glow}"/>')
        g += (f'<path d="M{cx:.1f},{cy + 0.5 * s:.1f} C{cx - 0.4 * s:.1f},{cy + 0.1 * s:.1f} {cx - 0.25 * s:.1f},{cy - 0.25 * s:.1f} {cx:.1f},{cy - 0.6 * s:.1f} '
              f'C{cx + 0.25 * s:.1f},{cy - 0.25 * s:.1f} {cx + 0.4 * s:.1f},{cy + 0.1 * s:.1f} {cx:.1f},{cy + 0.5 * s:.1f} Z" fill="{pal[1]}" stroke="none"/>')
    elif el == "water":
        g += f'<path d="M{cx:.1f},{cy - s:.1f} L{cx + 0.72 * s:.1f},{cy + s:.1f} Q{cx:.1f},{cy + 0.45 * s:.1f} {cx - 0.72 * s:.1f},{cy + s:.1f} Z" fill="{pal[0]}"/>'
        g += f'<line x1="{cx:.1f}" y1="{cy - 0.5 * s:.1f}" x2="{cx:.1f}" y2="{cy + 0.7 * s:.1f}" stroke="{pal[2]}" stroke-width="0.9"/>'
    elif el == "grass":
        g += f'<path d="M{cx:.1f},{cy - s:.1f} Q{cx + 0.7 * s:.1f},{cy:.1f} {cx:.1f},{cy + s:.1f} Q{cx - 0.7 * s:.1f},{cy:.1f} {cx:.1f},{cy - s:.1f} Z" fill="{pal[0]}"/>'
        g += f'<line x1="{cx:.1f}" y1="{cy - 0.7 * s:.1f}" x2="{cx:.1f}" y2="{cy + 0.7 * s:.1f}" stroke="{pal[2]}" stroke-width="0.9"/>'
    elif el == "electric":
        g += (f'<polygon points="{cx - 0.2 * s:.1f},{cy - s:.1f} {cx + 0.5 * s:.1f},{cy - s:.1f} {cx + 0.05 * s:.1f},{cy - 0.05 * s:.1f} '
              f'{cx + 0.45 * s:.1f},{cy - 0.05 * s:.1f} {cx - 0.35 * s:.1f},{cy + s:.1f} {cx - 0.02 * s:.1f},{cy + 0.05 * s:.1f} '
              f'{cx - 0.5 * s:.1f},{cy + 0.05 * s:.1f} {cx:.1f},{cy - 0.2 * s:.1f}" fill="{glow}"/>')
    elif el == "rock":
        g += f'<path d="M{cx:.1f},{cy - s:.1f} L{cx + 0.55 * s:.1f},{cy - 0.1 * s:.1f} L{cx:.1f},{cy + s:.1f} L{cx - 0.55 * s:.1f},{cy - 0.1 * s:.1f} Z" fill="{pal[0]}"/>'
        g += f'<line x1="{cx:.1f}" y1="{cy - s:.1f}" x2="{cx:.1f}" y2="{cy + s:.1f}" stroke="{pal[2]}" stroke-width="0.8"/>'
    else:  # shadow
        g += star(cx, cy, s, glow, 1)
        g = g.replace("<path", '<path stroke="' + stroke + '" stroke-width="1"', 1)
    return g + "</g>"


def spots(el, pts, e):
    pal, glow = e["pal"], e["glow"]
    out = ""
    for (x, y, r) in pts:
        if el == "shadow":
            out += star(x, y, r * 1.2, glow, .9)
        elif el == "electric":
            out += star(x, y, r * 1.1, glow, .85)
        elif el == "grass":
            out += f'<path d="M{x:.1f},{y - r:.1f} Q{x + r:.1f},{y:.1f} {x:.1f},{y + r:.1f} Q{x - r:.1f},{y:.1f} {x:.1f},{y - r:.1f} Z" fill="{pal[3]}" opacity=".5"/>'
        elif el == "water":
            out += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{pal[0]}" opacity=".6"/>'
        elif el == "rock":
            out += f'<path d="M{x:.1f},{y - r:.1f} L{x + r * .6:.1f},{y:.1f} L{x:.1f},{y + r:.1f} L{x - r * .6:.1f},{y:.1f} Z" fill="{pal[3]}" opacity=".45"/>'
        else:
            out += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.1f}" fill="{glow}" opacity=".7"/>'
    return out


def defs(ctx):
    uid, e = ctx.uid, ctx.e
    pal, glow, sty = e["pal"], e["glow"], ctx.sty
    extra = "".join(ctx.defs)
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
    <linearGradient id="void{uid}" x1="0" y1="0" x2="0.3" y2="1">
      <stop offset="0%" stop-color="#4c2a86"/><stop offset="55%" stop-color="#2a1352"/>
      <stop offset="100%" stop-color="#100628"/>
    </linearGradient>
    <linearGradient id="metal{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#c9d2e6"/><stop offset="45%" stop-color="#7d879f"/>
      <stop offset="100%" stop-color="#333a4d"/>
    </linearGradient>
    <linearGradient id="wood{uid}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#9a6d3a"/><stop offset="100%" stop-color="#4a3016"/>
    </linearGradient>
    <radialGradient id="stage{uid}" cx="50%" cy="62%" r="55%">
      <stop offset="0%" stop-color="{glow}" stop-opacity=".55"/><stop offset="70%" stop-color="{glow}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="orb{uid}" cx="42%" cy="38%" r="65%">
      <stop offset="0%" stop-color="#ffffff" stop-opacity=".95"/>
      <stop offset="45%" stop-color="{pal[0]}"/><stop offset="100%" stop-color="{pal[2]}"/>
    </radialGradient>
    <radialGradient id="halo{uid}" cx="50%" cy="50%" r="50%">
      <stop offset="60%" stop-color="{glow}" stop-opacity="0"/><stop offset="100%" stop-color="{glow}" stop-opacity=".5"/>
    </radialGradient>
    <linearGradient id="rim{uid}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="{sty.get('rift', glow)}"/><stop offset="100%" stop-color="{glow}" stop-opacity=".2"/>
    </linearGradient>{extra}
  </defs>"""


# --------------------------------------------------------------------------- scenes
def scene_fire(uid):
    """Emberfall: a caldera at dusk — lava terraces, obsidian spires, falling ash."""
    ash = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#ffcf6a" opacity="{op}"/>'
                  for x, y, r, op in [(30, 52, 1.8, .9), (70, 34, 1.3, .8), (120, 60, 1.6, .85), (160, 30, 1.2, .7),
                                      (188, 66, 1.7, .8), (50, 84, 1.2, .7), (96, 26, 1.1, .7), (142, 44, 1.0, .6)])
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
  {ash}
  <ellipse cx="108" cy="118" rx="86" ry="30" fill="url(#stage{uid})"/>"""


def scene_water(uid):
    """Tidecaller: a sunlit trench — god rays, kelp, drifting bubbles."""
    rays = ""
    for x, w in [(24, 16), (70, 22), (120, 14), (168, 26)]:
        rays += f'<polygon points="{x},0 {x + w},0 {x + w + 34},150 {x + 18},150" fill="#bfeaff" opacity=".08"/>'
    bubbles = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#dff6ff" opacity="{op}"/>' for x, y, r, op in
                      [(34, 44, 2.4, .5), (58, 80, 1.6, .4), (180, 40, 2.8, .5), (150, 96, 1.8, .4),
                       (196, 110, 2.2, .45), (90, 30, 1.4, .4), (120, 120, 1.6, .4)])
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
    """Verdspire: the canopy floor — trunks, light shafts, drifting pollen."""
    shafts = ""
    for x, w in [(40, 20), (96, 26), (160, 18)]:
        shafts += f'<polygon points="{x},0 {x + w},0 {x + w + 26},150 {x + 14},150" fill="#eaffb0" opacity=".10"/>'
    pollen = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#f6ffcf" opacity="{op}"/>' for x, y, r, op in
                     [(34, 52, 1.6, .7), (72, 34, 1.2, .6), (150, 44, 1.6, .65), (186, 64, 1.3, .6),
                      (110, 28, 1.1, .6), (60, 96, 1.3, .6)])
    blades = "".join(f'<path d="M{x},150 C{x - 3},{y} {x - 1},{y - 8} {x + 2},{y - 14}" stroke="#1c5a2a" stroke-width="3" fill="none" stroke-linecap="round"/>'
                     for x, y in [(12, 120), (30, 112), (190, 116), (206, 122), (150, 126)])
    return f"""
  <defs>
    <linearGradient id="sky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#2a7d3d"/><stop offset="50%" stop-color="#15522480"/><stop offset="100%" stop-color="#06180c"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  <g fill="#123f1e" opacity=".9">
    <rect x="18" y="10" width="20" height="140" rx="10"/><rect x="176" y="4" width="24" height="146" rx="12"/>
  </g>
  <g fill="#0d3517" opacity=".8">
    <ellipse cx="30" cy="20" rx="34" ry="20"/><ellipse cx="188" cy="14" rx="40" ry="22"/><ellipse cx="108" cy="6" rx="70" ry="18"/>
  </g>
  {shafts}
  <g fill="#1f7a33" opacity=".85">
    <path d="M46,10 q-10,10 -4,22 q10,-4 8,-20 Z"/><path d="M170,8 q10,10 4,22 q-10,-4 -6,-20 Z"/>
  </g>
  {pollen}
  <path d="M0,150 L0,128 Q54,140 108,130 T216,132 L216,150 Z" fill="#0a2f14"/>
  {blades}
  <ellipse cx="108" cy="96" rx="92" ry="44" fill="url(#stage{uid})"/>"""


def scene_electric(uid):
    """Voltcrest: a storm ridge — thunderheads, pylon silhouettes, live sparks."""
    bolts = ""
    for pts in ["150,2 138,40 150,40 132,86", "44,0 34,30 44,30 30,64"]:
        bolts += f'<polyline points="{pts}" fill="none" stroke="#fff29a" stroke-width="2" opacity=".35"/>'
    rain = "".join(f'<line x1="{x}" y1="{y}" x2="{x - 4}" y2="{y + 16}" stroke="#cfe0ff" stroke-width="1" opacity=".2"/>'
                   for x, y in [(30, 20), (70, 50), (110, 10), (150, 60), (190, 30), (90, 90), (200, 90)])
    sparks = "".join(star(x, y, r, "#fff6b0", op) for x, y, r, op in
                     [(60, 40, 2.4, .8), (170, 52, 2, .7), (120, 30, 2.2, .75), (48, 96, 1.8, .7), (196, 100, 2, .7)])
    pylons = ""
    for px, ph in [(22, 44), (196, 52)]:
        pylons += (f'<g stroke="#101218" stroke-width="2" fill="none" opacity=".75">'
                   f'<path d="M{px - 8},130 L{px},{130 - ph} L{px + 8},130 M{px - 5},{130 - ph * 0.4:.0f} L{px + 5},{130 - ph * 0.4:.0f} '
                   f'M{px - 3},{130 - ph * 0.72:.0f} L{px + 3},{130 - ph * 0.72:.0f}"/></g>')
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
  {pylons}
  <path d="M0,150 L0,126 Q54,138 108,128 T216,130 L216,150 Z" fill="#181812"/>
  <ellipse cx="108" cy="92" rx="92" ry="44" fill="url(#stage{uid})"/>"""


def scene_shadow(uid):
    """Umbral Reach: deep space — a ringed dead world, nebula veils, a torn horizon."""
    stars = "".join(star(x, y, r, "#ffffff", op) for x, y, r, op in
                    [(26, 26, 2, .9), (64, 14, 1.4, .7), (96, 34, 1.7, .8), (140, 18, 1.3, .7), (178, 30, 2, .85),
                     (200, 60, 1.5, .7), (40, 70, 1.3, .6), (120, 96, 1.4, .6), (190, 104, 1.6, .7), (54, 112, 1.2, .6),
                     (150, 58, 1.2, .6), (84, 72, 1.1, .6), (12, 46, 1.1, .55), (168, 82, 1.0, .5)])
    dust = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="#cdb3ff" opacity="{op}"/>' for x, y, r, op in
                   [(48, 44, 1, .5), (150, 40, 1.2, .5), (180, 80, 1, .45), (70, 100, 1, .45)])
    return f"""
  <defs>
    <radialGradient id="sky{uid}" cx="52%" cy="40%" r="80%">
      <stop offset="0%" stop-color="#271248"/><stop offset="55%" stop-color="#140925"/><stop offset="100%" stop-color="#05020f"/>
    </radialGradient>
    <radialGradient id="neb{uid}" cx="50%" cy="46%" r="42%">
      <stop offset="0%" stop-color="#7a4fdd" stop-opacity=".3"/><stop offset="100%" stop-color="#7a4fdd" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="neb2{uid}" cx="26%" cy="70%" r="46%">
      <stop offset="0%" stop-color="#ff6fd8" stop-opacity=".16"/><stop offset="100%" stop-color="#ff6fd8" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="orb2{uid}" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#4a2b7a"/><stop offset="100%" stop-color="#150a2c"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="{VB_W}" height="{VB_H}" fill="url(#sky{uid})"/>
  <ellipse cx="108" cy="70" rx="96" ry="66" fill="url(#neb{uid})"/>
  <ellipse cx="60" cy="104" rx="86" ry="52" fill="url(#neb2{uid})"/>
  {stars}
  <g opacity=".85">
    <circle cx="176" cy="34" r="19" fill="url(#orb2{uid})"/>
    <circle cx="176" cy="34" r="19" fill="none" stroke="#9c7bdc" stroke-width="0.8" opacity=".7"/>
    <ellipse cx="176" cy="34" rx="30" ry="8" fill="none" stroke="#d9c6ff" stroke-width="1.6" opacity=".55" transform="rotate(-18 176 34)"/>
    <ellipse cx="176" cy="34" rx="36" ry="10" fill="none" stroke="#b79bff" stroke-width="0.9" opacity=".4" transform="rotate(-18 176 34)"/>
  </g>
  {dust}
  <path d="M0,150 L0,132 Q54,142 108,133 T216,135 L216,150 Z" fill="#0b0620"/>
  <path d="M0,134 Q54,144 108,135 T216,137" fill="none" stroke="#a06cf6" stroke-width="1" opacity=".5"/>
  <ellipse cx="108" cy="96" rx="78" ry="34" fill="url(#stage{uid})" opacity=".45"/>"""


SCENES = {1: scene_fire, 2: scene_water, 3: scene_grass, 4: scene_electric, 5: scene_shadow}


# ==================================================================================
# EXTENDED ART — full-card illustrations (Gauntlet win reward)
# ----------------------------------------------------------------------------------
# The extended-art variant fills the *whole* card (portrait 216x302, the card's own
# aspect) instead of the 216x150 art window. It reuses the card's exact spryte — so
# grading/foil overlays still read as the same creature — but rebuilds a taller,
# richer environment around it. Unlike the base scenes (one fixed backdrop per set),
# every extended scene is driven by the card's vary() seed, so the scenery is unique
# on every card. See CardView(extendedArt:) and docs/DESIGN.md §14.6.
# ==================================================================================
EXT_W, EXT_H = 216, 302
EXT_GROUND = 250  # the y where the spryte's feet rest / the stage glow sits


def ext_scene_fire(ctx):
    """Emberfall — a vertical caldera: distant cones, an ember-filled sky, a lava lake."""
    uid = ctx.uid
    rp = ctx.rng(11)
    peaks, x = "", -12.0
    while x < 228:
        w, h = rp.f(34, 64), rp.f(46, 104)
        peaks += (f'<path d="M{x:.0f},178 L{x + w / 2:.0f},{178 - h:.0f} L{x + w:.0f},178 Z" '
                  f'fill="#2a0a06" opacity="0.85"/>')
        x += w * 0.62
    re = ctx.rng(12)
    embers = "".join(
        f'<circle cx="{re.f(6, 210):.1f}" cy="{re.f(8, 236):.1f}" r="{re.f(0.8, 2.6):.2f}" '
        f'fill="#ffcf6a" opacity="{re.f(0.4, 0.95):.2f}"/>' for _ in range(28))
    sparks = "".join(star(re.f(20, 196), re.f(24, 150), re.f(1.6, 3.0), "#ffe8b0", re.f(.5, .9))
                     for _ in range(5))
    return f"""
  <defs>
    <linearGradient id="esky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#370c05"/><stop offset="42%" stop-color="#7a1c06"/>
      <stop offset="70%" stop-color="#c2440e"/><stop offset="100%" stop-color="#1e060a"/>
    </linearGradient>
    <radialGradient id="elava{uid}" cx="50%" cy="100%" r="72%">
      <stop offset="0%" stop-color="#ffe08a"/><stop offset="34%" stop-color="#ff6a1a"/>
      <stop offset="100%" stop-color="#7a1c06" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="{EXT_W}" height="{EXT_H}" fill="url(#esky{uid})"/>
  <ellipse cx="108" cy="150" rx="120" ry="70" fill="#ff7a1a" opacity="0.10"/>
  {peaks}
  {sparks}
  {embers}
  <rect x="0" y="206" width="{EXT_W}" height="96" fill="url(#elava{uid})"/>
  <path d="M0,302 L0,248 L38,260 L76,244 L112,258 L150,242 L188,258 L216,246 L216,302 Z" fill="#280a06"/>
  <path d="M0,302 L0,272 Q54,262 108,272 T216,270 L216,302 Z" fill="#ff8a2a" opacity="0.85"/>
  <path d="M0,302 L0,286 Q54,278 108,286 T216,284 L216,302 Z" fill="#ffe08a" opacity="0.7"/>
  <ellipse cx="108" cy="{EXT_GROUND}" rx="98" ry="30" fill="url(#stage{uid})"/>"""


def ext_scene_water(ctx):
    """Tidecaller — a deep trench: god rays, drifting bubbles, kelp, a bright surface."""
    uid = ctx.uid
    rr = ctx.rng(21)
    rays = "".join(
        f'<polygon points="{rr.f(0, 200):.0f},0 {rr.f(0, 200) + 14:.0f},0 '
        f'{rr.f(0, 200) + 48:.0f},302 {rr.f(0, 200) + 18:.0f},302" fill="#bfeaff" opacity="0.06"/>'
        for _ in range(5))
    rb = ctx.rng(22)
    bubbles = "".join(
        f'<circle cx="{rb.f(8, 208):.1f}" cy="{rb.f(20, 250):.1f}" r="{rb.f(1.2, 3.4):.2f}" '
        f'fill="#dff6ff" opacity="{rb.f(0.3, 0.6):.2f}"/>' for _ in range(20))
    rk = ctx.rng(23)
    kelp = ""
    for _ in range(5):
        bx = rk.f(10, 206)
        sway = rk.f(-16, 16)
        kelp += (f'<path d="M{bx:.0f},302 C{bx + sway:.0f},260 {bx - sway:.0f},226 {bx + sway * 0.6:.0f},196" '
                 f'stroke="#0f7d7d" stroke-width="{rk.f(3, 6):.1f}" fill="none" '
                 f'stroke-linecap="round" opacity="0.75"/>')
    return f"""
  <defs>
    <linearGradient id="esky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#1a72c4"/><stop offset="40%" stop-color="#0b3f86"/>
      <stop offset="100%" stop-color="#03102e"/>
    </linearGradient>
  </defs>
  <rect width="{EXT_W}" height="{EXT_H}" fill="url(#esky{uid})"/>
  <ellipse cx="108" cy="0" rx="150" ry="70" fill="#bff0ff" opacity="0.16"/>
  {rays}
  {bubbles}
  {kelp}
  <path d="M0,302 L0,254 Q40,266 78,254 Q120,242 150,256 Q186,268 216,254 L216,302 Z" fill="#06255a"/>
  <path d="M0,302 L0,276 Q54,286 108,276 T216,278 L216,302 Z" fill="#041a44"/>
  <ellipse cx="108" cy="{EXT_GROUND}" rx="98" ry="30" fill="url(#stage{uid})"/>"""


def ext_scene_grass(ctx):
    """Verdspire — the canopy floor: trunks, arching foliage, light shafts, drifting pollen."""
    uid = ctx.uid
    rt = ctx.rng(31)
    trunks = ""
    for _ in range(3):
        tx, tw = rt.f(4, 190), rt.f(16, 28)
        trunks += f'<rect x="{tx:.0f}" y="-6" width="{tw:.0f}" height="308" rx="{tw / 2:.0f}" fill="#123f1e" opacity="0.9"/>'
    rc = ctx.rng(32)
    canopy = "".join(
        f'<ellipse cx="{rc.f(0, 216):.0f}" cy="{rc.f(-6, 26):.0f}" rx="{rc.f(30, 58):.0f}" '
        f'ry="{rc.f(16, 28):.0f}" fill="#0d3517" opacity="0.85"/>' for _ in range(4))
    shafts = "".join(
        f'<polygon points="{rc.f(20, 180):.0f},0 {rc.f(20, 180) + 22:.0f},0 '
        f'{rc.f(20, 180) + 40:.0f},302 {rc.f(20, 180) + 12:.0f},302" fill="#eaffb0" opacity="0.08"/>'
        for _ in range(3))
    rpo = ctx.rng(33)
    pollen = "".join(
        f'<circle cx="{rpo.f(8, 208):.1f}" cy="{rpo.f(16, 240):.1f}" r="{rpo.f(1.0, 2.2):.2f}" '
        f'fill="#f6ffcf" opacity="{rpo.f(0.4, 0.75):.2f}"/>' for _ in range(14))
    rbl = ctx.rng(34)
    ferns = "".join(
        f'<path d="M{fx:.0f},302 C{fx - 8:.0f},272 {fx - 4:.0f},244 {fx + 4:.0f},220" '
        f'stroke="#1c5a2a" stroke-width="4" fill="none" stroke-linecap="round"/>'
        for fx in [rbl.f(4, 212) for _ in range(4)])
    return f"""
  <defs>
    <linearGradient id="esky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#2f8a45"/><stop offset="45%" stop-color="#155224"/>
      <stop offset="100%" stop-color="#06180c"/>
    </linearGradient>
  </defs>
  <rect width="{EXT_W}" height="{EXT_H}" fill="url(#esky{uid})"/>
  {trunks}
  {canopy}
  {shafts}
  {pollen}
  <path d="M0,302 L0,262 Q54,274 108,264 T216,266 L216,302 Z" fill="#0a2f14"/>
  {ferns}
  <ellipse cx="108" cy="{EXT_GROUND}" rx="98" ry="30" fill="url(#stage{uid})"/>"""


def ext_scene_electric(ctx):
    """Voltcrest — a storm ridge: thunderheads, forked bolts, pylons, sparks, rain."""
    uid = ctx.uid
    rc = ctx.rng(41)
    clouds = "".join(
        f'<ellipse cx="{rc.f(0, 216):.0f}" cy="{rc.f(6, 40):.0f}" rx="{rc.f(40, 66):.0f}" '
        f'ry="{rc.f(18, 26):.0f}" fill="#20233a" opacity="0.9"/>' for _ in range(4))
    rb = ctx.rng(42)
    bolts = ""
    for _ in range(2):
        bx, by = rb.f(30, 186), rb.f(30, 46)
        bolts += (f'<polyline points="{bx:.0f},{by:.0f} {bx - 12:.0f},{by + 38:.0f} '
                  f'{bx:.0f},{by + 38:.0f} {bx - 18:.0f},{by + 92:.0f}" fill="none" '
                  f'stroke="#fff29a" stroke-width="2.2" opacity="0.4"/>')
    rp = ctx.rng(43)
    pylons = ""
    for _ in range(2):
        px, ph = rp.f(16, 200), rp.f(46, 74)
        base = 214.0
        pylons += (f'<g stroke="#101218" stroke-width="2" fill="none" opacity="0.7">'
                   f'<path d="M{px - 9:.0f},{base:.0f} L{px:.0f},{base - ph:.0f} L{px + 9:.0f},{base:.0f} '
                   f'M{px - 5:.0f},{base - ph * 0.42:.0f} L{px + 5:.0f},{base - ph * 0.42:.0f} '
                   f'M{px - 3:.0f},{base - ph * 0.72:.0f} L{px + 3:.0f},{base - ph * 0.72:.0f}"/></g>')
    rs = ctx.rng(44)
    sparks = "".join(star(rs.f(16, 200), rs.f(40, 200), rs.f(1.6, 3.0), "#fff6b0", rs.f(.6, .85))
                     for _ in range(6))
    rain = "".join(
        f'<line x1="{rs.f(0, 216):.0f}" y1="{rs.f(0, 200):.0f}" x2="{rs.f(0, 216) - 4:.0f}" '
        f'y2="{rs.f(0, 200) + 18:.0f}" stroke="#cfe0ff" stroke-width="1" opacity="0.18"/>' for _ in range(9))
    return f"""
  <defs>
    <linearGradient id="esky{uid}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#2b2f45"/><stop offset="52%" stop-color="#3a3320"/>
      <stop offset="100%" stop-color="#12120a"/>
    </linearGradient>
  </defs>
  <rect width="{EXT_W}" height="{EXT_H}" fill="url(#esky{uid})"/>
  {clouds}
  {bolts}
  {rain}
  {sparks}
  {pylons}
  <path d="M0,302 L0,258 Q54,270 108,260 T216,262 L216,302 Z" fill="#181812"/>
  <ellipse cx="108" cy="{EXT_GROUND}" rx="98" ry="30" fill="url(#stage{uid})"/>"""


def ext_scene_shadow(ctx):
    """Umbral Reach — deep space: nebula veils, a dense starfield, a ringed dead world, shards."""
    uid = ctx.uid
    field = starfield(0, 0, EXT_W, 240, ctx.var["seed"] + 51 * 7919, count=40, tint="#ffffff")
    rp = ctx.rng(52)
    planet_x, planet_y, pr = rp.f(40, 176), rp.f(30, 66), rp.f(15, 24)
    tilt = rp.f(-26, -8)
    rs = ctx.rng(53)
    shards = "".join(
        f'<path d="M{rs.f(10, 206):.0f},{rs.f(60, 210):.0f} l{rs.f(4, 9):.0f},{rs.f(-8, -4):.0f} '
        f'l{rs.f(3, 6):.0f},{rs.f(6, 12):.0f} l{rs.f(-6, -3):.0f},{rs.f(4, 8):.0f} Z" '
        f'fill="#4a2b7a" stroke="#9c7bdc" stroke-width="0.7" opacity="0.7"/>' for _ in range(5))
    return f"""
  <defs>
    <radialGradient id="esky{uid}" cx="52%" cy="34%" r="82%">
      <stop offset="0%" stop-color="#2a1450"/><stop offset="52%" stop-color="#140925"/>
      <stop offset="100%" stop-color="#05020f"/>
    </radialGradient>
    <radialGradient id="eneb{uid}" cx="50%" cy="42%" r="46%">
      <stop offset="0%" stop-color="#7a4fdd" stop-opacity="0.32"/><stop offset="100%" stop-color="#7a4fdd" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="eneb2{uid}" cx="28%" cy="66%" r="48%">
      <stop offset="0%" stop-color="#ff6fd8" stop-opacity="0.16"/><stop offset="100%" stop-color="#ff6fd8" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="eorb{uid}" cx="40%" cy="36%" r="66%">
      <stop offset="0%" stop-color="#5a3a92"/><stop offset="100%" stop-color="#150a2c"/>
    </radialGradient>
  </defs>
  <rect width="{EXT_W}" height="{EXT_H}" fill="url(#esky{uid})"/>
  <ellipse cx="108" cy="120" rx="132" ry="120" fill="url(#eneb{uid})"/>
  <ellipse cx="64" cy="180" rx="120" ry="96" fill="url(#eneb2{uid})"/>
  {field}
  <g opacity="0.9">
    <circle cx="{planet_x:.0f}" cy="{planet_y:.0f}" r="{pr:.0f}" fill="url(#eorb{uid})"/>
    <circle cx="{planet_x:.0f}" cy="{planet_y:.0f}" r="{pr:.0f}" fill="none" stroke="#9c7bdc" stroke-width="0.8" opacity="0.7"/>
    <ellipse cx="{planet_x:.0f}" cy="{planet_y:.0f}" rx="{pr * 1.7:.0f}" ry="{pr * 0.42:.0f}" fill="none"
             stroke="#d9c6ff" stroke-width="1.6" opacity="0.5" transform="rotate({tilt:.0f} {planet_x:.0f} {planet_y:.0f})"/>
  </g>
  {shards}
  <path d="M0,302 L0,262 Q54,272 108,263 T216,265 L216,302 Z" fill="#0b0620"/>
  <path d="M0,264 Q54,274 108,265 T216,267" fill="none" stroke="#a06cf6" stroke-width="1" opacity="0.5"/>
  <ellipse cx="108" cy="{EXT_GROUND}" rx="92" ry="30" fill="url(#stage{uid})" opacity="0.55"/>"""


EXT_SCENES = {1: ext_scene_fire, 2: ext_scene_water, 3: ext_scene_grass,
              4: ext_scene_electric, 5: ext_scene_shadow}


def ext_art_inner(card):
    e = ELE[card["element"]]
    uid = card["id"].replace("-", "_")
    role = ROLES[card["name"]]
    ctx = Ctx(uid, e, card["set"], vary(card["name"]), card["name"])
    body = creature(ctx, role)                      # same spryte as the base card
    scene = EXT_SCENES[card["set"]](ctx)            # unique full-card environment
    # The spryte is authored in 216x150 space; enlarge it about its footing (108,150)
    # and drop it onto the extended stage so it reads as the hero of the scene.
    hero = (f'<g transform="translate(108 {EXT_GROUND}) scale(1.28) translate(-108 -150)">'
            f'{body}</g>')
    return defs(ctx) + scene + hero


def ext_art_svg(card):
    return f'<svg viewBox="0 0 {EXT_W} {EXT_H}" xmlns="http://www.w3.org/2000/svg">{ext_art_inner(card)}</svg>'


# ==================================================================================
# SET MORPHOLOGY
# ----------------------------------------------------------------------------------
# The same call produces genuinely different geometry in every set. Emberfall is
# fractured crust; Tidecaller is streamlined and buoyant; Verdspire is lobed and
# overgrown; Voltcrest is machined and chamfered; Umbral Reach is torn open, half
# missing, and full of stars.
# ==================================================================================
def P(ctx, d, fill, sw=2.2, extra=""):
    return (f'<path d="{d}" fill="{fill}" stroke="{ctx.ink}" stroke-width="{sw}" '
            f'stroke-linejoin="round"{extra}/>')


def sh_shape(ctx, cx, cy, rx, ry, seed=0):
    """The set's silhouette language, as a bare path."""
    s, sd = ctx.s, seed or ctx.var["seed"]
    if s == 1:
        return crag(cx, cy, rx, ry, sd, n=9, amp=0.11)
    if s == 2:
        return teardrop(cx, cy, rx, ry)
    if s == 3:
        return lobed(cx, cy, rx, ry, sd)
    if s == 4:
        return chamfer(cx, cy, rx, ry)
    return riftshape(cx, cy, rx, ry, sd)


def sh_torso(ctx, cx, cy, rx, ry, fill=None, seed=0, belly=True, sw=2.2):
    """Body mass + the set's surface treatment."""
    s, uid, pal, sty = ctx.s, ctx.uid, ctx.pal, ctx.sty
    d = sh_shape(ctx, cx, cy, rx, ry, seed)
    fill = fill or f"url(#body{uid})"
    g = ""
    if s == 5:
        cid = ctx.nid("cl")
        ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        g += P(ctx, d, f"url(#void{uid})", sw)
        g += f'<g clip-path="url(#{cid})">'
        g += f'<path d="{d}" fill="{fill}" opacity=".34"/>'
        g += starfield(cx - rx, cy - ry, rx * 2, ry * 2, (seed or ctx.var["seed"]) + 11,
                       count=int(6 + rx * ry / 42), tint=sty["star"])
        g += f'<ellipse cx="{cx - rx * 0.45:.1f}" cy="{cy - ry * 0.5:.1f}" rx="{rx * 0.7:.1f}" ry="{ry * 0.55:.1f}" fill="{sty["neb"]}" opacity=".3"/>'
        g += "</g>"
        g += f'<path d="{d}" fill="none" stroke="url(#rim{uid})" stroke-width="1.6" opacity=".9"/>'
        return g
    g += P(ctx, d, fill, sw)
    if belly:
        by = cy + ry * 0.34
        if s == 1:
            g += (f'<path d="{crag(cx - rx * 0.05, by, rx * 0.58, ry * 0.52, (seed or ctx.var["seed"]) + 5, 7, 0.1)}" '
                  f'fill="url(#belly{uid})" opacity=".88"/>')
        elif s == 2:
            g += (f'<path d="M{cx - rx * 0.82:.1f},{cy + ry * 0.1:.1f} Q{cx - rx * 0.1:.1f},{cy + ry * 1.12:.1f} '
                  f'{cx + rx * 0.72:.1f},{cy + ry * 0.16:.1f} Q{cx - rx * 0.05:.1f},{cy + ry * 0.62:.1f} '
                  f'{cx - rx * 0.82:.1f},{cy + ry * 0.1:.1f} Z" fill="url(#belly{uid})" opacity=".95"/>')
        elif s == 3:
            g += f'<ellipse cx="{cx:.1f}" cy="{by:.1f}" rx="{rx * 0.54:.1f}" ry="{ry * 0.5:.1f}" fill="url(#belly{uid})" opacity=".9"/>'
        else:
            g += (f'<rect x="{cx - rx * 0.52:.1f}" y="{by - ry * 0.34:.1f}" width="{rx * 1.04:.1f}" height="{ry * 0.66:.1f}" '
                  f'rx="{ry * 0.22:.1f}" fill="url(#belly{uid})" opacity=".92"/>')
    g += sh_marks(ctx, cx, cy, rx, ry, seed)
    return g


def sh_marks(ctx, cx, cy, rx, ry, seed=0):
    """Surface treatment: fissures / facets+gills / bark rings+buds / plating+coils."""
    s, sty, pal, r = ctx.s, ctx.sty, ctx.pal, ctx.rng(3 + (seed & 7))
    g = ""
    if s == 1:
        for _ in range(3):
            x, y = cx + r.f(-.55, .55) * rx, cy + r.f(-.6, .2) * ry
            d = f"M{x:.1f},{y:.1f}"
            for _ in range(3):
                x += r.f(-.2, .2) * rx
                y += r.f(.12, .3) * ry
                d += f" L{x:.1f},{y:.1f}"
            g += f'<path d="{d}" fill="none" stroke="{sty["seam"]}" stroke-width="1.5" stroke-linecap="round" opacity=".9"/>'
        g += (f'<path d="{crag(cx - rx * 0.3, cy - ry * 0.45, rx * 0.42, ry * 0.34, (seed or 1) + 3, 6, .2)}" '
              f'fill="{sty["crust"]}" opacity=".45"/>')
    elif s == 2:
        for i in range(3):
            fx = cx - rx * 0.4 + i * rx * 0.3
            g += (f'<path d="M{fx:.1f},{cy - ry * 0.62:.1f} L{fx + rx * 0.16:.1f},{cy - ry * 0.1:.1f} '
                  f'L{fx - rx * 0.1:.1f},{cy - ry * 0.05:.1f} Z" fill="{sty["ice"]}" opacity=".3"/>')
        for i in range(3):
            gx = cx - rx * 0.5 + i * rx * 0.17
            g += (f'<path d="M{gx:.1f},{cy - ry * 0.16:.1f} q{rx * 0.06:.1f},{ry * 0.32:.1f} 0,{ry * 0.56:.1f}" '
                  f'fill="none" stroke="{pal[2]}" stroke-width="1.3" opacity=".75"/>')
    elif s == 3:
        for i in (0, 1):
            ry2 = ry * (0.55 + i * 0.3)
            g += (f'<path d="M{cx - rx * 0.72:.1f},{cy - ry * 0.1 + i * ry * 0.34:.1f} q{rx * 0.7:.1f},{ry2 * 0.42:.1f} {rx * 1.44:.1f},0" '
                  f'fill="none" stroke="{sty["bark"]}" stroke-width="1.4" opacity=".55"/>')
        for i in range(2 + (ctx.var["spots"] & 1)):
            bx, by = cx + r.f(-.55, .6) * rx, cy + r.f(-.55, .1) * ry
            g += f'<circle cx="{bx:.1f}" cy="{by:.1f}" r="{r.f(1.8, 3.0):.1f}" fill="{sty["bloom"]}" stroke="{ctx.ink}" stroke-width="0.8"/>'
    elif s == 4:
        uid = ctx.uid
        cid = ctx.nid("cl")
        ctx.defs.append(f'<clipPath id="{cid}"><path d="{chamfer(cx, cy, rx, ry)}"/></clipPath>')
        g += f'<g clip-path="url(#{cid})">'
        plate = chamfer(cx, cy - ry * 0.62, rx * 1.04, ry * 0.72)
        g += f'<path d="{plate}" fill="url(#metal{uid})" opacity=".95"/>'
        g += (f'<line x1="{cx - rx:.1f}" y1="{cy - ry * 0.1:.1f}" x2="{cx + rx:.1f}" y2="{cy - ry * 0.1:.1f}" '
              f'stroke="{ctx.ink}" stroke-width="1.6" opacity=".8"/>')
        for i in range(5):
            bx = cx - rx * 0.7 + i * rx * 0.35
            g += (f'<circle cx="{bx:.1f}" cy="{cy - ry * 0.28:.1f}" r="1.7" fill="{sty["metal"]}" '
                  f'stroke="{ctx.ink}" stroke-width="0.8"/>')
        for i in range(3):
            vx = cx + rx * (0.18 + i * 0.24)
            g += (f'<rect x="{vx:.1f}" y="{cy + ry * 0.14:.1f}" width="{rx * 0.1:.1f}" height="{ry * 0.42:.1f}" '
                  f'rx="{rx * 0.05:.1f}" fill="{ctx.ink}" opacity=".55"/>')
        for i in range(3):
            wx = cx - rx * 0.62 + i * rx * 0.24
            g += (f'<path d="M{wx:.1f},{cy + ry * 0.02:.1f} q{rx * 0.12:.1f},{ry * 0.3:.1f} 0,{ry * 0.6:.1f}" '
                  f'fill="none" stroke="{sty["copper"]}" stroke-width="2" opacity=".9"/>')
        g += "</g>"
        g += (f'<circle cx="{cx - rx * 0.36:.1f}" cy="{cy - ry * 0.55:.1f}" r="{ry * 0.2:.1f}" fill="{sty["arc"]}" '
              f'stroke="{ctx.ink}" stroke-width="1.2"/>')
        g += (f'<circle cx="{cx - rx * 0.36:.1f}" cy="{cy - ry * 0.55:.1f}" r="{ry * 0.09:.1f}" fill="{ctx.ink}"/>')
    return g


def sh_ground(ctx, cx, cy, rx):
    """Contact with the world: scorched, buoyant, rooted, charged or absent."""
    s, sty = ctx.s, ctx.sty
    if s == 1:
        return (f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{rx * 0.2:.1f}" fill="#000" opacity=".26"/>'
                f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx * 0.72:.1f}" ry="{rx * 0.13:.1f}" fill="{sty["seam"]}" opacity=".4"/>')
    if s == 2:
        g = f'<ellipse cx="{cx:.1f}" cy="{cy + 6:.1f}" rx="{rx * 0.8:.1f}" ry="{rx * 0.14:.1f}" fill="#000" opacity=".16"/>'
        for i in (0, 1):
            g += (f'<ellipse cx="{cx:.1f}" cy="{cy + 6:.1f}" rx="{rx * (0.5 + i * 0.42):.1f}" ry="{rx * (0.1 + i * 0.07):.1f}" '
                  f'fill="none" stroke="{sty["ice"]}" stroke-width="1" opacity="{0.4 - i * 0.16:.2f}"/>')
        return g
    if s == 3:
        g = f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{rx * 0.19:.1f}" fill="#000" opacity=".24"/>'
        for i, dx in enumerate((-0.9, -0.5, 0.6, 1.0)):
            g += (f'<path d="M{cx + rx * dx:.1f},{cy + 3:.1f} q{-2 if i % 2 else 2},-6 {1 if i % 2 else -1},-11" '
                  f'fill="none" stroke="{sty["leaf"]}" stroke-width="2.2" stroke-linecap="round"/>')
        return g
    if s == 4:
        g = f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{rx * 0.18:.1f}" fill="#000" opacity=".26"/>'
        g += (f'<polyline points="{cx - rx * 0.9:.1f},{cy + 3:.1f} {cx - rx * 0.4:.1f},{cy - 1:.1f} {cx - rx * 0.55:.1f},{cy + 4:.1f} '
              f'{cx + rx * 0.1:.1f},{cy:.1f}" fill="none" stroke="{sty["arc"]}" stroke-width="1.3" opacity=".8"/>')
        return g
    # Umbral Reach: they do not touch the ground — a well of dark and a faint ring
    g = f'<ellipse cx="{cx:.1f}" cy="{cy + 4:.1f}" rx="{rx * 0.86:.1f}" ry="{rx * 0.17:.1f}" fill="#05020f" opacity=".65"/>'
    g += (f'<ellipse cx="{cx:.1f}" cy="{cy + 4:.1f}" rx="{rx * 1.02:.1f}" ry="{rx * 0.22:.1f}" fill="none" '
          f'stroke="{ctx.glow}" stroke-width="1" opacity=".38"/>')
    return g


def sh_leg(ctx, x, top, w, h, back=False):
    """One leg, in the set's idiom."""
    s, uid, pal, sty = ctx.s, ctx.uid, ctx.pal, ctx.sty
    fill = f"url(#body2{uid})" if back else f"url(#body{uid})"
    op = ' opacity=".85"' if back else ""
    if s == 1:
        d = (f"M{x - w / 2:.1f},{top:.1f} L{x + w / 2:.1f},{top:.1f} L{x + w * 0.62:.1f},{top + h * 0.7:.1f} "
             f"L{x + w * 0.78:.1f},{top + h:.1f} L{x - w * 0.78:.1f},{top + h:.1f} L{x - w * 0.62:.1f},{top + h * 0.7:.1f} Z")
        g = P(ctx, d, fill, 2.1, op)
        g += f'<line x1="{x:.1f}" y1="{top + h * 0.25:.1f}" x2="{x:.1f}" y2="{top + h * 0.8:.1f}" stroke="{sty["seam"]}" stroke-width="1.2" opacity=".8"/>'
        g += (f'<ellipse cx="{x:.1f}" cy="{top + h:.1f}" rx="{w * 0.86:.1f}" ry="{w * 0.34:.1f}" '
              f'fill="{sty["crust"]}" stroke="{ctx.ink}" stroke-width="1.4"{op}/>')
        return g
    if s == 2:
        d = (f"M{x - w * 0.5:.1f},{top:.1f} Q{x - w * 0.72:.1f},{top + h * 0.7:.1f} {x - w * 0.95:.1f},{top + h:.1f} "
             f"Q{x:.1f},{top + h * 1.12:.1f} {x + w * 0.95:.1f},{top + h:.1f} "
             f"Q{x + w * 0.72:.1f},{top + h * 0.7:.1f} {x + w * 0.5:.1f},{top:.1f} Z")
        g = P(ctx, d, fill, 2.0, op)
        for i in (-1, 0, 1):
            g += (f'<line x1="{x + i * w * 0.3:.1f}" y1="{top + h * 0.35:.1f}" x2="{x + i * w * 0.62:.1f}" y2="{top + h * 0.92:.1f}" '
                  f'stroke="{pal[2]}" stroke-width="1" opacity=".7"/>')
        g += (f'<ellipse cx="{x:.1f}" cy="{top + h:.1f}" rx="{w * 1.02:.1f}" ry="{w * 0.3:.1f}" '
              f'fill="{sty["ice"]}" stroke="{ctx.ink}" stroke-width="1.3"{op}/>')
        return g
    if s == 3:
        g = (f'<path d="M{x:.1f},{top:.1f} q{-w * 0.5:.1f},{h * 0.45:.1f} {-w * 0.16:.1f},{h:.1f}" fill="none" '
             f'stroke="url(#wood{uid})" stroke-width="{w * 0.86:.1f}" stroke-linecap="round"/>')
        g += (f'<path d="M{x:.1f},{top:.1f} q{-w * 0.5:.1f},{h * 0.45:.1f} {-w * 0.16:.1f},{h:.1f}" fill="none" '
              f'stroke="{ctx.ink}" stroke-width="1" opacity=".5"/>')
        for i in (-1, 1):
            g += (f'<path d="M{x - w * 0.16:.1f},{top + h:.1f} q{i * w * 0.5:.1f},{2:.1f} {i * w * 0.78:.1f},{5:.1f}" '
                  f'fill="none" stroke="{sty["bark"]}" stroke-width="2.6" stroke-linecap="round"/>')
        g += (f'<ellipse cx="{x - w * 0.16:.1f}" cy="{top + h:.1f}" rx="{w * 0.5:.1f}" ry="{w * 0.2:.1f}" '
              f'fill="{sty["bark"]}" stroke="{ctx.ink}" stroke-width="1.2"/>')
        return g
    if s == 4:
        g = (f'<polyline points="{x:.1f},{top:.1f} {x + w * 0.7:.1f},{top + h * 0.42:.1f} {x - w * 0.4:.1f},{top + h * 0.6:.1f} '
             f'{x + w * 0.2:.1f},{top + h:.1f}" fill="none" stroke="url(#metal{uid})" stroke-width="{w * 0.72:.1f}" '
             f'stroke-linejoin="round" stroke-linecap="round"/>')
        g += (f'<rect x="{x - w * 0.5:.1f}" y="{top + h * 0.86:.1f}" width="{w:.1f}" height="{h * 0.2:.1f}" rx="2" '
              f'fill="{sty["rubber"]}" stroke="{ctx.ink}" stroke-width="1.2"/>')
        return g
    # Umbral Reach: limbs float free of the body and fade into nothing
    d = (f"M{x - w * 0.5:.1f},{top + h * 0.18:.1f} L{x + w * 0.5:.1f},{top + h * 0.18:.1f} "
         f"L{x + w * 0.16:.1f},{top + h:.1f} L{x - w * 0.16:.1f},{top + h:.1f} Z")
    g = P(ctx, d, f"url(#void{uid})", 1.8, ' opacity=".95"')
    g += f'<path d="{d}" fill="none" stroke="url(#rim{uid})" stroke-width="1.2" opacity=".8"/>'
    g += star(x, top + h + 2, 2.2, ctx.glow, .9)
    return g


def sh_arm(ctx, sx, sy, ex, ey, w):
    """Upper limb / claw arm."""
    s, uid, sty = ctx.s, ctx.uid, ctx.sty
    if s == 1:
        return (f'<path d="M{sx:.1f},{sy:.1f} L{ex:.1f},{ey:.1f}" stroke="url(#body2{uid})" stroke-width="{w:.1f}" '
                f'stroke-linecap="round"/><path d="M{sx:.1f},{sy:.1f} L{ex:.1f},{ey:.1f}" stroke="{sty["seam"]}" '
                f'stroke-width="1.1" opacity=".7"/>')
    if s == 2:
        mx, my = (sx + ex) / 2 - 6, (sy + ey) / 2
        return (f'<path d="M{sx:.1f},{sy:.1f} Q{mx:.1f},{my:.1f} {ex:.1f},{ey:.1f}" fill="none" '
                f'stroke="url(#body{uid})" stroke-width="{w:.1f}" stroke-linecap="round"/>')
    if s == 3:
        mx, my = (sx + ex) / 2 + 5, (sy + ey) / 2 - 4
        return (f'<path d="M{sx:.1f},{sy:.1f} Q{mx:.1f},{my:.1f} {ex:.1f},{ey:.1f}" fill="none" '
                f'stroke="url(#wood{uid})" stroke-width="{w:.1f}" stroke-linecap="round"/>')
    if s == 4:
        mx, my = (sx + ex) / 2 + 7, (sy + ey) / 2 - 7
        return (f'<polyline points="{sx:.1f},{sy:.1f} {mx:.1f},{my:.1f} {ex:.1f},{ey:.1f}" fill="none" '
                f'stroke="url(#metal{uid})" stroke-width="{w:.1f}" stroke-linejoin="round" stroke-linecap="round"/>')
    return (f'<path d="M{sx:.1f},{sy:.1f} L{ex:.1f},{ey:.1f}" stroke="#3d1d70" stroke-width="{w:.1f}" '
            f'stroke-linecap="round"/><path d="M{sx:.1f},{sy:.1f} L{ex:.1f},{ey:.1f}" stroke="url(#rim{uid})" '
            f'stroke-width="1.1" opacity=".8"/>')


def sh_head(ctx, hx, hy, r, kind="muzzle", look=-1.0, mood="calm"):
    """Cranium in the set's idiom + a slot-specific face (muzzle/beak/jaw/...)."""
    s, uid, pal, sty, ink = ctx.s, ctx.uid, ctx.pal, ctx.sty, ctx.ink
    g = ""
    d = sh_shape(ctx, hx, hy, r, r * 0.96, ctx.var["seed"] + 31)
    if s == 1:
        g += P(ctx, d, f"url(#body{uid})", 2.1)
        g += (f'<path d="M{hx - r * 0.95:.1f},{hy - r * 0.32:.1f} L{hx + r * 0.5:.1f},{hy - r * 0.86:.1f} '
              f'L{hx + r * 0.98:.1f},{hy - r * 0.26:.1f} Z" fill="{sty["crust"]}" opacity=".55"/>')
    elif s == 2:
        g += (f'<path d="M{hx + r * 0.5:.1f},{hy - r * 0.9:.1f} q{r * 1.1:.1f},{r * 0.3:.1f} {r * 0.4:.1f},{r * 1.5:.1f} '
              f'q{-r * 0.5:.1f},{-r * 0.3:.1f} {-r * 0.7:.1f},{-r * 0.5:.1f} Z" fill="url(#body2{uid})" '
              f'stroke="{ink}" stroke-width="1.6" stroke-linejoin="round"/>')
        g += f'<circle cx="{hx:.1f}" cy="{hy:.1f}" r="{r:.1f}" fill="url(#body{uid})" stroke="{ink}" stroke-width="2.1"/>'
        g += f'<path d="M{hx - r * 0.8:.1f},{hy - r * 0.5:.1f} q{r * 0.6:.1f},{-r * 0.25:.1f} {r * 1.2:.1f},{r * 0.1:.1f}" fill="none" stroke="{sty["ice"]}" stroke-width="1.4" opacity=".6"/>'
    elif s == 3:
        g += P(ctx, d, f"url(#body{uid})", 2.1)
        g += (f'<path d="M{hx - r * 0.98:.1f},{hy - r * 0.42:.1f} a{r:.1f},{r * 0.7:.1f} 0 0 1 {r * 1.96:.1f},0 '
              f'q{-r:.1f},{r * 0.28:.1f} {-r * 1.96:.1f},0 Z" fill="{sty["leaf"]}" stroke="{ink}" stroke-width="1.5"/>')
    elif s == 4:
        g += P(ctx, d, f"url(#body{uid})", 2.1)
        g += (f'<rect x="{hx - r * 0.98:.1f}" y="{hy - r * 0.34:.1f}" width="{r * 1.96:.1f}" height="{r * 0.5:.1f}" '
              f'rx="{r * 0.16:.1f}" fill="{sty["rubber"]}" opacity=".75"/>')
    else:
        cid = ctx.nid("cl")
        ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        g += P(ctx, d, f"url(#void{uid})", 2.0)
        g += (f'<g clip-path="url(#{cid})"><path d="{d}" fill="url(#body{uid})" opacity=".3"/>'
              + starfield(hx - r, hy - r, r * 2, r * 2, ctx.var["seed"] + 71, count=8, tint=sty["star"]) + "</g>")
        g += f'<path d="{d}" fill="none" stroke="url(#rim{uid})" stroke-width="1.5" opacity=".9"/>'
        g += (f'<path d="M{hx - r * 0.9:.1f},{hy - r * 0.15:.1f} a{r * 0.92:.1f},{r * 0.8:.1f} 0 0 1 {r * 1.8:.1f},0 Z" '
              f'fill="{sty["neb"]}" opacity=".28"/>')
    # slot-specific face front (creatures face left)
    if kind == "muzzle":
        g += (f'<ellipse cx="{hx - r * 0.78:.1f}" cy="{hy + r * 0.36:.1f}" rx="{r * 0.46:.1f}" ry="{r * 0.32:.1f}" '
              f'fill="url(#body{uid})" stroke="{ink}" stroke-width="1.6"/>')
        g += f'<circle cx="{hx - r * 1.1:.1f}" cy="{hy + r * 0.24:.1f}" r="{r * 0.14:.1f}" fill="{ink}"/>'
    elif kind == "feline":
        g += (f'<path d="M{hx - r * 0.98:.1f},{hy + r * 0.18:.1f} q{r * 0.34:.1f},{r * 0.5:.1f} {r * 0.72:.1f},{r * 0.12:.1f}" '
              f'fill="url(#body{uid})" stroke="{ink}" stroke-width="1.4"/>')
        g += f'<path d="M{hx - r * 0.74:.1f},{hy + r * 0.12:.1f} l{-r * 0.16:.1f},{-r * 0.16:.1f} l{r * 0.32:.1f},0 Z" fill="{ink}"/>'
    elif kind == "beak":
        g += (f'<path d="M{hx - r * 0.7:.1f},{hy + r * 0.05:.1f} L{hx - r * 1.75:.1f},{hy + r * 0.2:.1f} '
              f'L{hx - r * 0.66:.1f},{hy + r * 0.56:.1f} Z" fill="{ctx.glow}" stroke="{ink}" stroke-width="1.4" stroke-linejoin="round"/>')
    elif kind == "jaw":
        g += (f'<path d="M{hx - r * 0.2:.1f},{hy - r * 0.1:.1f} L{hx - r * 1.85:.1f},{hy + r * 0.1:.1f} '
              f'L{hx - r * 1.7:.1f},{hy + r * 0.62:.1f} L{hx - r * 0.2:.1f},{hy + r * 0.7:.1f} Z" '
              f'fill="url(#body2{uid})" stroke="{ink}" stroke-width="1.6" stroke-linejoin="round"/>')
        g += (f'<path d="M{hx - r * 1.6:.1f},{hy + r * 0.18:.1f} l{r * 0.1:.1f},{r * 0.3:.1f} l{r * 0.16:.1f},{-r * 0.28:.1f} '
              f'l{r * 0.14:.1f},{r * 0.3:.1f} l{r * 0.16:.1f},{-r * 0.3:.1f}" fill="#fff" stroke="none"/>')
    elif kind == "toad":
        g += (f'<path d="M{hx - r * 1.25:.1f},{hy + r * 0.18:.1f} q{r * 1.25:.1f},{r * 0.95:.1f} {r * 2.4:.1f},{-r * 0.05:.1f} '
              f'q{-r * 1.2:.1f},{r * 0.28:.1f} {-r * 2.4:.1f},{r * 0.05:.1f} Z" fill="url(#body2{uid})" '
              f'stroke="{ink}" stroke-width="1.7" stroke-linejoin="round"/>')
        for sgn, bx in ((-1, hx - r * 0.52), (1, hx + r * 0.5)):
            g += (f'<circle cx="{bx:.1f}" cy="{hy - r * 0.62:.1f}" r="{r * 0.44:.1f}" fill="url(#body{uid})" '
                  f'stroke="{ink}" stroke-width="1.6"/>')
        g += f'<circle cx="{hx - r * 1.02:.1f}" cy="{hy - r * 0.05:.1f}" r="{r * 0.1:.1f}" fill="{ink}"/>'
    elif kind == "trunk":
        g += (f'<path d="M{hx - r * 0.6:.1f},{hy + r * 0.2:.1f} q{-r * 0.9:.1f},{r * 0.3:.1f} {-r * 0.75:.1f},{r * 1.1:.1f}" '
              f'fill="none" stroke="url(#body{uid})" stroke-width="{r * 0.38:.1f}" stroke-linecap="round"/>')
    return g


def sh_eyes(ctx, x, y, r, look=-1.0, mood="calm", pair=True, gap=None):
    """Eyes carry a lot of a set's personality."""
    s, sty = ctx.s, ctx.sty
    gap = gap if gap is not None else r * 2.4
    xs = [x, x + gap] if pair else [x]
    angry = mood == "fierce"
    g = ""
    for i, ex in enumerate(xs):
        rr = r if i == 0 else r * 0.92
        if s == 1:
            g += eye(ex, y, rr, glow=ctx.glow, look=look * rr, angry=angry, glowy=True)
            g += f'<path d="M{ex - rr * 1.2:.1f},{y - rr * 1.5:.1f} l{rr * 2.2:.1f},{-rr * 0.3:.1f}" stroke="{sty["crust"]}" stroke-width="{rr * 0.5:.1f}" stroke-linecap="round"/>'
        elif s == 2:
            g += eye(ex, y, rr * 1.12, glow="#ffffff", look=look * rr, angry=angry)
            g += f'<circle cx="{ex + rr * 0.5:.1f}" cy="{y - rr * 0.7:.1f}" r="{rr * 0.26:.1f}" fill="#fff" opacity=".9"/>'
        elif s == 3:
            g += eye(ex, y, rr, glow="#ffffff", look=look * rr, angry=angry)
            g += (f'<path d="M{ex - rr * 1.2:.1f},{y - rr * 1.05:.1f} q{rr * 1.2:.1f},{-rr * 0.9:.1f} {rr * 2.4:.1f},{-rr * 0.1:.1f}" '
                  f'fill="none" stroke="{sty["leaf"]}" stroke-width="1.5" stroke-linecap="round"/>')
        elif s == 4:
            g += (f'<rect x="{ex - rr * 1.15:.1f}" y="{y - rr * 0.85:.1f}" width="{rr * 2.3:.1f}" height="{rr * 1.7:.1f}" '
                  f'rx="{rr * 0.45:.1f}" fill="{sty["arc"]}" stroke="{ctx.ink}" stroke-width="1.2"/>')
            g += (f'<rect x="{ex - rr * 0.28 + look * rr * 0.4:.1f}" y="{y - rr * 0.6:.1f}" width="{rr * 0.6:.1f}" '
                  f'height="{rr * 1.2:.1f}" rx="{rr * 0.25:.1f}" fill="#1a1020"/>')
        else:
            g += f'<circle cx="{ex:.1f}" cy="{y:.1f}" r="{rr * 1.7:.1f}" fill="{ctx.glow}" opacity=".16"/>'
            g += (f'<ellipse cx="{ex:.1f}" cy="{y:.1f}" rx="{rr * 1.02:.1f}" ry="{rr * 1.16:.1f}" fill="#0b0620" '
                  f'stroke="{sty["rift"]}" stroke-width="1.1"/>')
            g += f'<circle cx="{ex + look * rr * 0.2:.1f}" cy="{y:.1f}" r="{rr * 0.6:.1f}" fill="{sty["star"]}"/>'
            g += star(ex + look * rr * 0.2, y, rr * 0.92, "#ffffff", .95)
            if angry:
                g += (f'<path d="M{ex - rr * 1.25:.1f},{y - rr * 2.05:.1f} L{ex + rr * 1.15:.1f},{y - rr * 1.45:.1f}" '
                      f'stroke="{sty["rift"]}" stroke-width="{rr * 0.42:.1f}" stroke-linecap="round"/>')
    return g


def sh_mouth(ctx, x, y, w, kind="smile"):
    s, ink = ctx.s, ctx.ink
    if kind == "none":
        return ""
    if kind == "fang":
        g = f'<path d="M{x:.1f},{y:.1f} q{w * 0.5:.1f},{w * 0.52:.1f} {w:.1f},0 Z" fill="{ink}"/>'
        g += f'<path d="M{x + w * 0.18:.1f},{y + w * 0.06:.1f} l{w * 0.08:.1f},{w * 0.26:.1f} l{w * 0.12:.1f},{-w * 0.26:.1f} Z" fill="#fff"/>'
        g += f'<path d="M{x + w * 0.62:.1f},{y + w * 0.06:.1f} l{w * 0.08:.1f},{w * 0.24:.1f} l{w * 0.12:.1f},{-w * 0.24:.1f} Z" fill="#fff"/>'
        return g
    if kind == "grin":
        return (f'<path d="M{x:.1f},{y:.1f} q{w * 0.5:.1f},{w * 0.44:.1f} {w:.1f},0" fill="none" stroke="{ink}" '
                f'stroke-width="1.6" stroke-linecap="round"/>'
                f'<path d="M{x + w * 0.2:.1f},{y + w * 0.12:.1f} l0,{w * 0.16:.1f} M{x + w * 0.5:.1f},{y + w * 0.2:.1f} l0,{w * 0.16:.1f} '
                f'M{x + w * 0.78:.1f},{y + w * 0.14:.1f} l0,{w * 0.14:.1f}" stroke="{ink}" stroke-width="1.1"/>')
    if kind == "slit":
        return f'<line x1="{x:.1f}" y1="{y:.1f}" x2="{x + w:.1f}" y2="{y + w * 0.12:.1f}" stroke="{ink}" stroke-width="1.6" stroke-linecap="round"/>'
    if kind == "void":
        return (f'<ellipse cx="{x + w * 0.5:.1f}" cy="{y + w * 0.1:.1f}" rx="{w * 0.34:.1f}" ry="{w * 0.2:.1f}" '
                f'fill="#05020f" stroke="{ctx.glow}" stroke-width="1" opacity=".95"/>')
    return (f'<path d="M{x:.1f},{y:.1f} q{w * 0.5:.1f},{w * 0.4:.1f} {w:.1f},0" fill="none" stroke="{ink}" '
            f'stroke-width="1.5" stroke-linecap="round"/>')


def sh_ears(ctx, hx, hy, r, kind="point", spread=1.0):
    """Ear pair. Shape comes from the slot, material from the set."""
    s, uid, pal, sty, ink = ctx.s, ctx.uid, ctx.pal, ctx.sty, ctx.ink
    if kind == "none":
        return ""
    g = ""
    for sgn, ex in ((-1, hx - r * 0.42 * spread), (1, hx + r * 0.52 * spread)):
        base = hy - r * 0.5
        h = {"point": 1.25, "round": 0.7, "long": 1.85, "tuft": 1.35, "small": 0.55}[kind] * r
        w = {"point": 0.4, "round": 0.62, "long": 0.34, "tuft": 0.42, "small": 0.4}[kind] * r
        rot = sgn * (10 if kind != "long" else 6)
        if kind == "round":
            g += (f'<circle cx="{ex:.1f}" cy="{base - h * 0.2:.1f}" r="{w:.1f}" fill="url(#body{uid})" '
                  f'stroke="{ink}" stroke-width="1.6"/>')
            if s == 2:
                g += f'<circle cx="{ex:.1f}" cy="{base - h * 0.2:.1f}" r="{w * 0.5:.1f}" fill="{sty["ice"]}" opacity=".5"/>'
            elif s == 4:
                g += f'<circle cx="{ex:.1f}" cy="{base - h * 0.2:.1f}" r="{w * 0.45:.1f}" fill="{sty["copper"]}" opacity=".8"/>'
            elif s == 5:
                g += star(ex, base - h * 0.2, w * 0.55, ctx.glow, .9)
            continue
        if s == 1:
            d = (f"M{ex - w:.1f},{base:.1f} L{ex - w * 0.2:.1f},{base - h * 0.6:.1f} L{ex + w * 0.15:.1f},{base - h:.1f} "
                 f"L{ex + w * 0.55:.1f},{base - h * 0.45:.1f} L{ex + w:.1f},{base:.1f} Z")
        elif s == 2:
            d = (f"M{ex - w:.1f},{base:.1f} Q{ex - w * 0.4:.1f},{base - h:.1f} {ex + w * 0.9:.1f},{base - h * 0.72:.1f} "
                 f"Q{ex + w * 0.5:.1f},{base - h * 0.2:.1f} {ex + w:.1f},{base:.1f} Z")
        elif s == 3:
            d = (f"M{ex:.1f},{base:.1f} Q{ex - w * 1.5:.1f},{base - h * 0.55:.1f} {ex:.1f},{base - h:.1f} "
                 f"Q{ex + w * 1.5:.1f},{base - h * 0.55:.1f} {ex:.1f},{base:.1f} Z")
        elif s == 4:
            d = (f"M{ex - w:.1f},{base:.1f} L{ex - w * 0.45:.1f},{base - h:.1f} L{ex + w * 0.2:.1f},{base - h * 0.55:.1f} "
                 f"L{ex + w * 0.75:.1f},{base - h * 0.9:.1f} L{ex + w:.1f},{base:.1f} Z")
        else:
            d = (f"M{ex - w:.1f},{base:.1f} Q{ex - w * 0.9:.1f},{base - h:.1f} {ex + w * 0.25:.1f},{base - h * 1.05:.1f} "
                 f"Q{ex + w * 0.1:.1f},{base - h * 0.4:.1f} {ex + w:.1f},{base:.1f} Z")
        fill = f"url(#void{uid})" if s == 5 else f"url(#body{uid})"
        g += f'<g transform="rotate({rot} {ex:.1f} {base:.1f})">' + P(ctx, d, fill, 1.7)
        if s == 3:
            g += f'<line x1="{ex:.1f}" y1="{base:.1f}" x2="{ex:.1f}" y2="{base - h * 0.85:.1f}" stroke="{ink}" stroke-width="1" opacity=".55"/>'
        if s == 5:
            g += f'<path d="{d}" fill="none" stroke="url(#rim{uid})" stroke-width="1.1" opacity=".85"/>'
        if kind == "tuft":
            g += tuft(ctx.el, ex, base - h * 1.1, r * 0.34, ctx.e, rot)
        g += "</g>"
    return g


def sh_crest(ctx, hx, hy, r, kind="none", stage=1):
    """Head furniture: horns, antlers, frills, crowns, caps, haloes."""
    s, uid, pal, sty, ink, el, e = ctx.s, ctx.uid, ctx.pal, ctx.sty, ctx.ink, ctx.el, ctx.e
    if kind == "none":
        return ""
    g = ""
    top = hy - r * 0.86
    if kind == "horn":
        L = r * (1.05 + 0.34 * stage)
        for sgn in (-1, 1):
            bx = hx + sgn * r * 0.42
            if s == 1:
                d = (f"M{bx - r * 0.26:.1f},{top:.1f} L{bx + sgn * r * 0.34:.1f},{top - L * 0.62:.1f} "
                     f"L{bx + sgn * r * 0.16:.1f},{top - L:.1f} L{bx + r * 0.28:.1f},{top - L * 0.16:.1f} Z")
                g += P(ctx, d, sty["ember"], 1.6)
            elif s == 2:
                tipx = bx + sgn * r * 0.5
                d = (f"M{bx - r * 0.26:.1f},{top:.1f} L{bx - sgn * r * 0.04:.1f},{top - L * 0.72:.1f} "
                     f"L{tipx:.1f},{top - L * 1.1:.1f} L{bx + sgn * r * 0.2:.1f},{top - L * 0.42:.1f} "
                     f"L{bx + r * 0.26:.1f},{top:.1f} Z")
                g += P(ctx, d, pal[1], 1.4, ' opacity=".95"')
                g += (f'<path d="M{bx:.1f},{top:.1f} L{tipx:.1f},{top - L * 1.1:.1f}" stroke="{sty["ice"]}" '
                      f'stroke-width="1.2" opacity=".85"/>')
            elif s == 3:
                g += (f'<path d="M{bx:.1f},{top:.1f} q{sgn * r * 0.3:.1f},{-L * 0.6:.1f} {sgn * r * 0.05:.1f},{-L:.1f}" '
                      f'fill="none" stroke="url(#wood{uid})" stroke-width="{r * 0.24:.1f}" stroke-linecap="round"/>')
                g += tuft("grass", bx + sgn * r * 0.08, top - L, r * 0.3, ELE["grass"], sgn * 26)
            elif s == 4:
                g += (f'<rect x="{bx - r * 0.11:.1f}" y="{top - L:.1f}" width="{r * 0.22:.1f}" height="{L:.1f}" rx="{r * 0.08:.1f}" '
                      f'fill="url(#metal{uid})" stroke="{ink}" stroke-width="1.3"/>')
                g += f'<circle cx="{bx:.1f}" cy="{top - L:.1f}" r="{r * 0.16:.1f}" fill="{sty["arc"]}" stroke="{ink}" stroke-width="1"/>'
            else:
                g += (f'<path d="M{bx - r * 0.2:.1f},{top:.1f} Q{bx + sgn * r * 0.55:.1f},{top - L * 0.65:.1f} '
                      f'{bx + sgn * r * 0.16:.1f},{top - L:.1f} Q{bx + sgn * r * 0.02:.1f},{top - L * 0.5:.1f} '
                      f'{bx + r * 0.2:.1f},{top:.1f} Z" fill="url(#void{uid})" stroke="url(#rim{uid})" stroke-width="1.4"/>')
                g += star(bx + sgn * r * 0.16, top - L, r * 0.22, sty["star"], .95)
        if s == 4 and stage >= 2:
            g += (f'<path d="M{hx - r * 0.42:.1f},{top - r * 0.9:.1f} q{r * 0.42:.1f},{r * 0.5:.1f} {r * 0.84:.1f},0" '
                  f'fill="none" stroke="{sty["arc"]}" stroke-width="1.6" opacity=".9" stroke-dasharray="3 2"/>')
    elif kind == "antler":
        for sgn in (-1, 1):
            bx = hx + sgn * r * 0.36
            stroke = {1: sty["ember"], 2: sty["ice"], 3: f"url(#wood{uid})", 4: f"url(#metal{uid})", 5: "#4a2585"}[s]
            g += f'<g fill="none" stroke="{stroke}" stroke-width="{r * 0.2:.1f}" stroke-linecap="round">'
            g += f'<path d="M{bx:.1f},{top:.1f} q{sgn * r * 0.2:.1f},{-r * 0.7:.1f} {sgn * r * 0.1:.1f},{-r * 1.3:.1f}"/>'
            g += f'<path d="M{bx + sgn * r * 0.14:.1f},{top - r * 0.72:.1f} q{sgn * r * 0.6:.1f},{-r * 0.16:.1f} {sgn * r * 0.86:.1f},{-r * 0.6:.1f}"/>'
            g += f'<path d="M{bx + sgn * r * 0.1:.1f},{top - r * 1.06:.1f} q{sgn * r * 0.46:.1f},{-r * 0.22:.1f} {sgn * r * 0.6:.1f},{-r * 0.72:.1f}"/>'
            g += "</g>"
            if s == 5:
                g += (f'<g fill="none" stroke="url(#rim{uid})" stroke-width="1" opacity=".9" stroke-linecap="round">'
                      f'<path d="M{bx:.1f},{top:.1f} q{sgn * r * 0.2:.1f},{-r * 0.7:.1f} {sgn * r * 0.1:.1f},{-r * 1.3:.1f}"/>'
                      f'<path d="M{bx + sgn * r * 0.14:.1f},{top - r * 0.72:.1f} q{sgn * r * 0.6:.1f},{-r * 0.16:.1f} {sgn * r * 0.86:.1f},{-r * 0.6:.1f}"/>'
                      f'<path d="M{bx + sgn * r * 0.1:.1f},{top - r * 1.06:.1f} q{sgn * r * 0.46:.1f},{-r * 0.22:.1f} {sgn * r * 0.6:.1f},{-r * 0.72:.1f}"/></g>')
            if s == 3:
                g += tuft("grass", bx + sgn * r * 0.7, top - r * 1.3, r * 0.3, ELE["grass"], sgn * 30)
            elif s == 5:
                g += star(bx + sgn * r * 0.7, top - r * 1.3, r * 0.26, sty["star"], .95)
            elif s == 1:
                g += tuft("fire", bx + sgn * r * 0.1, top - r * 1.5, r * 0.32, e, sgn * 8)
    elif kind == "frill":
        n = 5 + stage
        for i in range(n):
            a = math.pi * (0.12 + 0.76 * i / (n - 1))
            px, py = hx - math.cos(a) * r * 1.05, hy - math.sin(a) * r * 1.05
            qx, qy = hx - math.cos(a) * r * 1.9, hy - math.sin(a) * r * 1.9
            if s == 2:
                g += (f'<path d="M{px:.1f},{py:.1f} L{qx:.1f},{qy:.1f}" stroke="{pal[2]}" stroke-width="1.3" '
                      f'stroke-linecap="round" opacity=".75"/>')
            elif s == 4:
                g += f'<path d="M{px:.1f},{py:.1f} L{qx:.1f},{qy:.1f}" stroke="{sty["copper"]}" stroke-width="{r * 0.2:.1f}" stroke-linecap="round"/>'
            elif s == 5:
                g += star(qx, qy, r * 0.2, sty["star"], .9)
                g += f'<path d="M{px:.1f},{py:.1f} L{qx:.1f},{qy:.1f}" stroke="{ctx.glow}" stroke-width="1" opacity=".5"/>'
            else:
                g += tuft(el, (px + qx) / 2, (py + qy) / 2, r * 0.42, e, math.degrees(a) - 90)
        if s == 2:
            web = (f'M{hx - r * 1.75:.1f},{hy + r * 0.1:.1f} '
                   f'A{r * 1.75:.1f},{r * 1.9:.1f} 0 0 1 {hx + r * 1.75:.1f},{hy + r * 0.1:.1f} '
                   f'Q{hx:.1f},{hy - r * 0.35:.1f} {hx - r * 1.75:.1f},{hy + r * 0.1:.1f} Z')
            g = (f'<path d="{web}" fill="{pal[1]}" opacity=".75" stroke="{ink}" stroke-width="1.5" '
                 f'stroke-linejoin="round"/>') + g
            g += (f'<path d="M{hx - r * 1.75:.1f},{hy + r * 0.1:.1f} '
                  f'A{r * 1.75:.1f},{r * 1.9:.1f} 0 0 1 {hx + r * 1.75:.1f},{hy + r * 0.1:.1f}" '
                  f'fill="none" stroke="{sty["coral"]}" stroke-width="1.6" opacity=".85"/>')
    elif kind == "crown":
        n = 3 + stage
        for i in range(n):
            a = math.pi * (0.2 + 0.6 * i / max(1, n - 1))
            px, py = hx - math.cos(a) * r * 0.92, hy - math.sin(a) * r * 1.0
            if s == 5:
                g += f'<circle cx="{px:.1f}" cy="{py - r * 0.2:.1f}" r="{r * 0.16:.1f}" fill="{sty["star"]}"/>'
                g += f'<circle cx="{px:.1f}" cy="{py - r * 0.2:.1f}" r="{r * 0.3:.1f}" fill="none" stroke="{ctx.glow}" stroke-width="0.9" opacity=".7"/>'
            elif s == 4:
                sh = r * (0.55 + 0.5 * math.sin(math.pi * (i + 0.5) / n))
                g += (f'<line x1="{px:.1f}" y1="{py:.1f}" x2="{px:.1f}" y2="{py - sh:.1f}" '
                      f'stroke="url(#metal{uid})" stroke-width="{r * 0.14:.1f}" stroke-linecap="round"/>')
                g += (f'<circle cx="{px:.1f}" cy="{py - sh:.1f}" r="{r * 0.15:.1f}" fill="{sty["arc"]}" '
                      f'stroke="{ink}" stroke-width="1"/>')
                if i:
                    g += (f'<path d="M{px - r * 0.28:.1f},{py - sh * 0.55:.1f} q{r * 0.14:.1f},{-r * 0.2:.1f} {r * 0.28:.1f},0" '
                          f'fill="none" stroke="{sty["arc"]}" stroke-width="1.1" opacity=".8"/>')
            elif s == 2:
                sh = r * (0.5 + 0.42 * math.sin(math.pi * (i + 0.5) / n))
                g += (f'<path d="M{px - r * 0.2:.1f},{py:.1f} L{px:.1f},{py - sh:.1f} '
                      f'L{px + r * 0.2:.1f},{py:.1f} Z" fill="{pal[1]}" opacity=".9" stroke="{ink}" '
                      f'stroke-width="1.2" stroke-linejoin="round"/>')
                g += (f'<path d="M{px:.1f},{py:.1f} L{px:.1f},{py - sh * 0.8:.1f}" stroke="{sty["ice"]}" '
                      f'stroke-width="1.1" opacity=".8"/>')
            else:
                g += tuft(el, px, py - r * 0.28, r * 0.42, e, math.degrees(a) - 90)
    elif kind == "cap":
        w = r * (1.25 + 0.12 * stage)
        capfill = {1: sty["ember"], 2: sty["ice"], 3: sty["bloom"], 4: f"url(#metal{uid})", 5: f"url(#void{uid})"}[s]
        g += P(ctx, f"M{hx - w:.1f},{hy - r * 0.42:.1f} a{w:.1f},{w * 0.78:.1f} 0 0 1 {w * 2:.1f},0 Z", capfill, 1.8)
        dots = 3 + stage
        rr = ctx.rng(9)
        for i in range(dots):
            dx = hx - w * 0.7 + i * (w * 1.4 / max(1, dots - 1))
            g += (f'<circle cx="{dx:.1f}" cy="{hy - r * 0.42 - rr.f(2, w * 0.5):.1f}" r="{rr.f(1.2, 2.2):.1f}" '
                  f'fill="{sty["star"] if s == 5 else "#ffffff"}" opacity=".8"/>')
    elif kind == "plume":
        if s == 5:
            g += f'<ellipse cx="{hx:.1f}" cy="{top - r * 0.5:.1f}" rx="{r * 1.0:.1f}" ry="{r * 0.28:.1f}" fill="none" stroke="{ctx.glow}" stroke-width="1.6" opacity=".8"/>'
            g += star(hx - r * 0.9, top - r * 0.5, r * 0.22, sty["star"], .95)
        else:
            g += tuft(el, hx, top - r * 0.42, r * (0.5 + 0.12 * stage), e, 0)
            if stage >= 2:
                g += tuft(el, hx - r * 0.42, top - r * 0.2, r * 0.34, e, -22)
                g += tuft(el, hx + r * 0.42, top - r * 0.2, r * 0.34, e, 22)
    elif kind == "halo":
        rr = r * (1.5 + 0.14 * stage)
        if s == 5:
            g += (f'<ellipse cx="{hx:.1f}" cy="{hy - r * 1.15:.1f}" rx="{rr:.1f}" ry="{rr * 0.3:.1f}" fill="none" '
                  f'stroke="{ctx.glow}" stroke-width="2" opacity=".85" transform="rotate(-12 {hx:.1f} {hy - r * 1.15:.1f})"/>')
            g += (f'<ellipse cx="{hx:.1f}" cy="{hy - r * 1.15:.1f}" rx="{rr * 1.28:.1f}" ry="{rr * 0.4:.1f}" fill="none" '
                  f'stroke="{sty["rift"]}" stroke-width="1" opacity=".55" transform="rotate(-12 {hx:.1f} {hy - r * 1.15:.1f})"/>')
        elif s == 4:
            g += (f'<ellipse cx="{hx:.1f}" cy="{hy - r * 1.2:.1f}" rx="{rr:.1f}" ry="{rr * 0.32:.1f}" fill="none" '
                  f'stroke="{sty["arc"]}" stroke-width="1.6" stroke-dasharray="4 3" opacity=".9"/>')
        elif s == 2:
            g += (f'<ellipse cx="{hx:.1f}" cy="{hy - r * 1.2:.1f}" rx="{rr:.1f}" ry="{rr * 0.3:.1f}" fill="none" '
                  f'stroke="{sty["foam"]}" stroke-width="1.4" opacity=".7"/>')
        elif s == 3:
            for i in range(6):
                a = 2 * math.pi * i / 6
                g += tuft("grass", hx + math.cos(a) * rr, hy - r * 1.2 + math.sin(a) * rr * 0.32, r * 0.24, ELE["grass"], math.degrees(a))
        else:
            for i in range(5):
                a = math.pi * (0.1 + 0.8 * i / 4)
                g += f'<circle cx="{hx + math.cos(a) * rr:.1f}" cy="{hy - r * 1.2 - math.sin(a) * rr * 0.4:.1f}" r="{r * 0.13:.1f}" fill="{ctx.glow}" opacity=".85"/>'
    return g


def sh_spine(ctx, cx, cy, rx, ry, kind="spikes", n=4, up=1.0):
    """Along-the-back structure: crest spikes, sails, leaf rows, coils, ring stacks."""
    s, uid, pal, sty, ink, el, e = ctx.s, ctx.uid, ctx.pal, ctx.sty, ctx.ink, ctx.el, ctx.e
    if kind == "none":
        return ""
    g = ""
    for i in range(n):
        t = i / max(1, n - 1)
        px = cx - rx * 0.72 + t * rx * 1.44
        py = cy - ry * (0.86 + 0.2 * math.sin(math.pi * t)) * up
        h = ry * (0.4 + 0.28 * math.sin(math.pi * t))
        if kind == "spikes":
            if s == 1:
                g += P(ctx, f"M{px - h * 0.42:.1f},{py:.1f} L{px:.1f},{py - h:.1f} L{px + h * 0.42:.1f},{py:.1f} Z", sty["crust"], 1.5)
            elif s == 2:
                g += P(ctx, f"M{px - h * 0.46:.1f},{py:.1f} Q{px - h * 0.1:.1f},{py - h * 1.05:.1f} "
                            f"{px + h * 0.46:.1f},{py:.1f} Z", pal[1], 1.3, ' opacity=".9"')
                g += (f'<path d="M{px - h * 0.1:.1f},{py - h * 0.15:.1f} L{px - h * 0.1:.1f},{py - h * 0.8:.1f}" '
                      f'stroke="{sty["ice"]}" stroke-width="1.1" opacity=".75"/>')
            elif s == 3:
                g += tuft("grass", px, py - h * 0.55, h * 0.6, ELE["grass"], (t - 0.5) * 40)
            elif s == 4:
                g += P(ctx, f"M{px - h * 0.3:.1f},{py:.1f} L{px - h * 0.12:.1f},{py - h:.1f} L{px + h * 0.3:.1f},{py - h * 0.68:.1f} Z", f"url(#metal{uid})", 1.3)
            else:
                g += P(ctx, f"M{px - h * 0.34:.1f},{py:.1f} Q{px:.1f},{py - h * 1.2:.1f} {px + h * 0.34:.1f},{py:.1f} Z", f"url(#void{uid})", 1.3)
                g += star(px, py - h * 0.75, h * 0.2, sty["star"], .9)
        elif kind == "sail":
            g += f'<path d="M{px:.1f},{py:.1f} L{px:.1f},{py - h * 1.3:.1f}" stroke="{pal[2]}" stroke-width="1.4"/>'
        elif kind == "coil":
            g += (f'<path d="M{px - h * 0.4:.1f},{py:.1f} q{h * 0.4:.1f},{-h * 0.9:.1f} {h * 0.8:.1f},0" fill="none" '
                  f'stroke="{sty.get("copper", pal[1])}" stroke-width="2" opacity=".9"/>')
        elif kind == "rings":
            g += (f'<ellipse cx="{px:.1f}" cy="{py + h * 0.2:.1f}" rx="{h * 0.62:.1f}" ry="{h * 0.22:.1f}" fill="none" '
                  f'stroke="{ctx.glow}" stroke-width="1.2" opacity=".75" transform="rotate(-16 {px:.1f} {py:.1f})"/>')
    if kind == "sail":
        pts = " ".join(f"{cx - rx * 0.72 + (i / max(1, n - 1)) * rx * 1.44:.1f},{cy - ry * (1.1 + 0.4 * math.sin(math.pi * i / max(1, n - 1))):.1f}" for i in range(n))
        g = (f'<polygon points="{cx - rx * 0.72:.1f},{cy - ry * 0.6:.1f} {pts} {cx + rx * 0.72:.1f},{cy - ry * 0.6:.1f}" '
             f'fill="url(#body2{uid})" stroke="{ink}" stroke-width="1.6" opacity=".92"/>') + g
    return g


def sh_tail(ctx, x, y, size, kind="plume", flip=1):
    """Tails read at a glance, so every set gets its own vocabulary."""
    s, uid, pal, sty, ink, el, e = ctx.s, ctx.uid, ctx.pal, ctx.sty, ctx.ink, ctx.el, ctx.e
    if kind == "none":
        return ""
    g = ""
    if kind == "plume":
        if s == 1:
            for i, (dx, dy, sc) in enumerate([(0.2, -0.2, 1.0), (0.75, -0.75, 0.72), (1.2, -1.35, 0.5)]):
                g += tuft("fire", x + size * dx * flip, y + size * dy, size * 0.55 * sc, e, flip * 24)
        elif s == 2:
            g += (f'<path d="M{x:.1f},{y:.1f} q{size * 0.9 * flip:.1f},{-size * 0.2:.1f} {size * 1.15 * flip:.1f},{-size * 1.05:.1f} '
                  f'q{-size * 0.2 * flip:.1f},{size * 0.86:.1f} {-size * 1.15 * flip:.1f},{size * 0.45:.1f} Z" '
                  f'fill="url(#body{uid})" stroke="{ink}" stroke-width="1.6"/>')
            for i in (0, 1):
                g += f'<circle cx="{x + size * (1.25 + i * 0.4) * flip:.1f}" cy="{y - size * (1.1 + i * 0.5):.1f}" r="{2.4 - i:.1f}" fill="{sty["foam"]}" opacity=".8"/>'
        elif s == 3:
            g += (f'<path d="M{x:.1f},{y:.1f} q{size * 0.8 * flip:.1f},{-size * 0.3:.1f} {size * 1.0 * flip:.1f},{-size * 1.1:.1f}" '
                  f'fill="none" stroke="url(#wood{uid})" stroke-width="{size * 0.22:.1f}" stroke-linecap="round"/>')
            for i in range(3):
                g += tuft("grass", x + size * (0.4 + i * 0.3) * flip, y - size * (0.35 + i * 0.4), size * 0.34, ELE["grass"], flip * (40 - i * 26))
        elif s == 4:
            g += (f'<polyline points="{x:.1f},{y:.1f} {x + size * 0.6 * flip:.1f},{y - size * 0.3:.1f} '
                  f'{x + size * 0.3 * flip:.1f},{y - size * 0.75:.1f} {x + size * 1.05 * flip:.1f},{y - size * 1.2:.1f}" '
                  f'fill="none" stroke="{ctx.glow}" stroke-width="{size * 0.24:.1f}" stroke-linejoin="round" stroke-linecap="round"/>')
            g += f'<circle cx="{x + size * 1.05 * flip:.1f}" cy="{y - size * 1.2:.1f}" r="{size * 0.2:.1f}" fill="{sty["arc"]}" stroke="{ink}" stroke-width="1"/>'
        else:
            g += (f'<path d="M{x:.1f},{y:.1f} Q{x + size * 1.1 * flip:.1f},{y - size * 0.4:.1f} {x + size * 1.7 * flip:.1f},{y - size * 1.3:.1f} '
                  f'Q{x + size * 0.8 * flip:.1f},{y - size * 0.3:.1f} {x:.1f},{y + size * 0.28:.1f} Z" '
                  f'fill="url(#void{uid})" stroke="url(#rim{uid})" stroke-width="1.4" opacity=".95"/>')
            for i in range(3):
                g += star(x + size * (0.6 + i * 0.5) * flip, y - size * (0.3 + i * 0.42), size * (0.22 - i * 0.04), sty["star"], .9)
    elif kind == "brush":
        g += (f'<path d="M{x:.1f},{y + size * 0.3:.1f} Q{x + size * 0.9 * flip:.1f},{y + size * 0.3:.1f} '
              f'{x + size * 1.3 * flip:.1f},{y - size * 0.95:.1f} Q{x + size * 0.5 * flip:.1f},{y - size * 0.2:.1f} '
              f'{x:.1f},{y - size * 0.35:.1f} Z" fill="url(#{"void" if s == 5 else "body2"}{uid})" '
              f'stroke="{ink}" stroke-width="1.7"/>')
        for i, (dx, dy, r) in enumerate([(0.3, 0.0, 0.5), (0.78, -0.42, 0.42), (1.16, -0.95, 0.3)]):
            px, py = x + size * dx * flip, y + size * dy
            d2 = sh_shape(ctx, px, py, size * r, size * r * 0.94, ctx.var["seed"] + 60 + i * 7)
            g += P(ctx, d2, f"url(#void{uid})" if s == 5 else f"url(#body{uid})", 1.5)
            if s == 5:
                g += star(px, py, size * r * 0.5, sty["star"], .85)
            elif s == 2:
                g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{size * r * 0.45:.1f}" fill="{sty["ice"]}" opacity=".45"/>'
            elif s == 1:
                g += tuft("fire", px, py - size * r * 0.6, size * r * 0.55, e, flip * 20)
    elif kind == "fluke":
        g += (f'<path d="M{x:.1f},{y:.1f} q{size * 0.9 * flip:.1f},{-size * 0.1:.1f} {size * 1.1 * flip:.1f},{-size * 0.15:.1f} '
              f'l{size * 0.5 * flip:.1f},{-size * 0.85:.1f} l{size * 0.24 * flip:.1f},{size * 1.6:.1f} '
              f'l{-size * 0.6 * flip:.1f},{-size * 0.42:.1f} Z" fill="url(#body2{uid})" stroke="{ink}" stroke-width="1.6"/>')
    elif kind == "frond":
        g += (f'<path d="M{x:.1f},{y:.1f} q{size * 1.0 * flip:.1f},{-size * 0.5:.1f} {size * 1.15 * flip:.1f},{-size * 1.4:.1f}" '
              f'fill="none" stroke="{sty.get("bark", pal[2])}" stroke-width="{size * 0.18:.1f}" stroke-linecap="round"/>')
        for i in range(4):
            t = 0.25 + i * 0.24
            g += tuft(el, x + size * 1.15 * flip * t, y - size * 1.4 * t * t - size * 0.1, size * 0.3, e, flip * (70 - i * 24))
    elif kind == "prong":
        shaft = {1: sty["crust"], 2: pal[1], 3: f"url(#wood{uid})", 4: f"url(#metal{uid})", 5: "#3d1d70"}[s]
        tipc = {1: sty["ember"], 2: sty["ice"], 3: sty["leaf"], 4: sty["copper"], 5: sty["rift"]}[s]
        g += (f'<path d="M{x:.1f},{y:.1f} l{size * 0.9 * flip:.1f},{-size * 0.5:.1f}" stroke="{shaft}" '
              f'stroke-width="{size * 0.26:.1f}" stroke-linecap="round"/>')
        for i in (-1, 1):
            g += (f'<line x1="{x + size * 0.85 * flip:.1f}" y1="{y - size * 0.46:.1f}" x2="{x + size * (1.35 + 0.1 * i) * flip:.1f}" '
                  f'y2="{y - size * (0.9 + 0.3 * i):.1f}" stroke="{tipc}" stroke-width="{size * 0.16:.1f}" stroke-linecap="round"/>')
        if s == 5:
            g += star(x + size * 1.35 * flip, y - size * 0.9, size * 0.24, sty["star"], .95)
    elif kind == "comet":
        g += (f'<path d="M{x:.1f},{y:.1f} Q{x + size * 1.4 * flip:.1f},{y - size * 0.2:.1f} {x + size * 2.2 * flip:.1f},{y - size * 1.1:.1f}" '
              f'fill="none" stroke="{ctx.glow}" stroke-width="{size * 0.3:.1f}" stroke-linecap="round" opacity=".6"/>')
        for i in range(4):
            g += star(x + size * (0.5 + i * 0.55) * flip, y - size * (0.05 + i * 0.3), size * (0.3 - i * 0.05), sty["star"], .95 - i * 0.15)
    elif kind == "whip":
        stroke = {1: sty["crust"], 2: pal[1], 3: f"url(#wood{uid})", 4: f"url(#metal{uid})", 5: f"url(#void{uid})"}[s]
        g += (f'<path d="M{x:.1f},{y:.1f} q{size * 1.1 * flip:.1f},{size * 0.1:.1f} {size * 1.2 * flip:.1f},{-size * 1.3:.1f}" '
              f'fill="none" stroke="{stroke}" stroke-width="{size * 0.2:.1f}" stroke-linecap="round"/>')
        g += tuft(el, x + size * 1.24 * flip, y - size * 1.5, size * 0.36, e, flip * 16)
    elif kind == "fan":
        for i in range(5):
            a = math.pi * (0.06 + 0.42 * i / 4)
            ex, ey = x + math.cos(a) * size * 1.5 * flip, y - math.sin(a) * size * 1.5
            spar = "#3d1d70" if s == 5 else f"url(#body{uid})"
            g += f'<path d="M{x:.1f},{y:.1f} L{ex:.1f},{ey:.1f}" stroke="{spar}" stroke-width="{size * 0.24:.1f}" stroke-linecap="round"/>'
            if s == 5:
                g += (f'<path d="M{x:.1f},{y:.1f} L{ex:.1f},{ey:.1f}" stroke="url(#rim{uid})" '
                      f'stroke-width="1" opacity=".8"/>')
            if s == 5:
                g += star(ex, ey, size * 0.2, sty["star"], .9)
            else:
                g += tuft(el, ex, ey, size * 0.26, e, math.degrees(a) * flip)
    return g


def sh_wing(ctx, cx, cy, span, kind="spread", stage=1, sgn=-1):
    """A single wing, rooted at (cx,cy), sweeping toward sgn."""
    s, uid, pal, sty, ink, el, e = ctx.s, ctx.uid, ctx.pal, ctx.sty, ctx.ink, ctx.el, ctx.e
    if kind == "none":
        return ""
    g = ""
    L = span
    if s == 1:
        d = (f"M{cx:.1f},{cy:.1f} Q{cx + sgn * L * 0.7:.1f},{cy - L * 0.78:.1f} {cx + sgn * L:.1f},{cy - L * 0.15:.1f} "
             f"L{cx + sgn * L * 0.82:.1f},{cy + L * 0.05:.1f} L{cx + sgn * L * 0.86:.1f},{cy + L * 0.25:.1f} "
             f"L{cx + sgn * L * 0.6:.1f},{cy + L * 0.14:.1f} L{cx + sgn * L * 0.58:.1f},{cy + L * 0.34:.1f} "
             f"L{cx + sgn * L * 0.3:.1f},{cy + L * 0.16:.1f} Z")
        g += P(ctx, d, f"url(#body2{uid})", 1.8)
        for i in range(3):
            g += (f'<path d="M{cx + sgn * L * 0.1:.1f},{cy:.1f} L{cx + sgn * L * (0.5 + i * 0.16):.1f},'
                  f'{cy - L * (0.36 - i * 0.16):.1f}" stroke="{sty["seam"]}" stroke-width="1.2" opacity=".8"/>')
    elif s == 2:
        d = (f"M{cx:.1f},{cy:.1f} Q{cx + sgn * L * 0.55:.1f},{cy - L * 0.85:.1f} {cx + sgn * L * 1.05:.1f},{cy - L * 0.3:.1f} "
             f"Q{cx + sgn * L * 0.7:.1f},{cy + L * 0.36:.1f} {cx:.1f},{cy + L * 0.2:.1f} Z")
        g += P(ctx, d, f"url(#body{uid})", 1.8, ' opacity=".95"')
        for i in range(4):
            t = 0.2 + i * 0.22
            g += (f'<path d="M{cx:.1f},{cy + L * 0.05:.1f} Q{cx + sgn * L * t * 0.7:.1f},{cy - L * 0.4 * t:.1f} '
                  f'{cx + sgn * L * (0.45 + t * 0.5):.1f},{cy - L * (0.28 - i * 0.12):.1f}" fill="none" '
                  f'stroke="{sty["ice"]}" stroke-width="1.2" opacity=".8"/>')
    elif s == 3:
        for i in range(3):
            t = 0.55 + i * 0.24
            ex, ey = cx + sgn * L * t, cy - L * (0.55 - i * 0.3)
            g += (f'<path d="M{cx:.1f},{cy:.1f} Q{(cx + ex) / 2:.1f},{ey - L * 0.3:.1f} {ex:.1f},{ey:.1f} '
                  f'Q{(cx + ex) / 2:.1f},{ey + L * 0.24:.1f} {cx:.1f},{cy:.1f} Z" fill="{sty["leaf"]}" '
                  f'stroke="{ink}" stroke-width="1.4"/>')
            g += f'<path d="M{cx:.1f},{cy:.1f} L{ex:.1f},{ey:.1f}" stroke="{ink}" stroke-width="0.9" opacity=".5"/>'
    elif s == 4:
        d = (f"M{cx:.1f},{cy:.1f} L{cx + sgn * L * 0.55:.1f},{cy - L * 0.66:.1f} L{cx + sgn * L * 1.02:.1f},{cy - L * 0.5:.1f} "
             f"L{cx + sgn * L * 0.86:.1f},{cy - L * 0.08:.1f} L{cx + sgn * L * 1.1:.1f},{cy + L * 0.2:.1f} "
             f"L{cx + sgn * L * 0.36:.1f},{cy + L * 0.24:.1f} Z")
        g += P(ctx, d, f"url(#metal{uid})", 1.7)
        g += (f'<polyline points="{cx + sgn * L * 0.4:.1f},{cy - L * 0.3:.1f} {cx + sgn * L * 0.66:.1f},{cy - L * 0.1:.1f} '
              f'{cx + sgn * L * 0.56:.1f},{cy + L * 0.02:.1f} {cx + sgn * L * 0.9:.1f},{cy + L * 0.1:.1f}" fill="none" '
              f'stroke="{sty["arc"]}" stroke-width="1.5" opacity=".95"/>')
    else:
        d = (f"M{cx:.1f},{cy:.1f} Q{cx + sgn * L * 0.5:.1f},{cy - L * 0.9:.1f} {cx + sgn * L * 1.08:.1f},{cy - L * 0.34:.1f} "
             f"Q{cx + sgn * L * 0.66:.1f},{cy + L * 0.4:.1f} {cx:.1f},{cy + L * 0.18:.1f} Z")
        cid = ctx.nid("cl")
        ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        g += f'<path d="{d}" fill="url(#void{uid})" opacity=".9"/>'
        g += (f'<g clip-path="url(#{cid})"><path d="{d}" fill="{sty["neb"]}" opacity=".45"/>'
              + starfield(cx - L * 1.1, cy - L, L * 2.2, L * 1.6, ctx.var["seed"] + 91 + int(sgn), count=14, tint=sty["star"]) + "</g>")
        g += f'<path d="{d}" fill="none" stroke="url(#rim{uid})" stroke-width="1.3" opacity=".9"/>'
        nodes = [(cx + sgn * L * 0.25, cy - L * 0.12), (cx + sgn * L * 0.6, cy - L * 0.42),
                 (cx + sgn * L * 0.95, cy - L * 0.28), (cx + sgn * L * 0.7, cy + L * 0.08)]
        g += f'<g stroke="{ctx.glow}" stroke-width="0.9" opacity=".8">'
        for i in range(len(nodes) - 1):
            g += f'<line x1="{nodes[i][0]:.1f}" y1="{nodes[i][1]:.1f}" x2="{nodes[i + 1][0]:.1f}" y2="{nodes[i + 1][1]:.1f}"/>'
        g += "</g>"
        for nx, ny in nodes:
            g += star(nx, ny, 1.9, sty["star"], .95)
    return g


def sh_motes(ctx, cx, cy, r, n=5, seed=0):
    """Ambient particles that follow the creature: embers, bubbles, spores, sparks, shards."""
    s, sty, rr = ctx.s, ctx.sty, ctx.rng(17 + seed)
    g = ""
    for i in range(n):
        a = rr.f(0, 2 * math.pi)
        d = rr.f(0.85, 1.35)
        px, py = cx + math.cos(a) * r * d, cy + math.sin(a) * r * d * 0.8
        if s == 1:
            g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{rr.f(0.8, 1.9):.1f}" fill="{sty["ember"]}" opacity="{rr.f(.5, .95):.2f}"/>'
        elif s == 2:
            g += (f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{rr.f(1.2, 2.6):.1f}" fill="none" stroke="{sty["ice"]}" '
                  f'stroke-width="1" opacity="{rr.f(.4, .85):.2f}"/>')
        elif s == 3:
            g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{rr.f(0.9, 1.8):.1f}" fill="{sty["spore"]}" opacity="{rr.f(.5, .9):.2f}"/>'
        elif s == 4:
            g += star(px, py, rr.f(1.2, 2.4), sty["arc"], rr.f(.5, .95))
        else:
            sz = rr.f(1.6, 3.4)
            g += (f'<path d="M{px:.1f},{py - sz:.1f} L{px + sz * 0.7:.1f},{py:.1f} L{px:.1f},{py + sz:.1f} '
                  f'L{px - sz * 0.7:.1f},{py:.1f} Z" fill="url(#void{ctx.uid})" stroke="{ctx.glow}" '
                  f'stroke-width="0.9" opacity=".95"/>')
            g += star(px, py, sz * 0.36, sty["star"], .9)
    return g


def sh_aura(ctx, cx, cy, r, level=1):
    """Rare/ultra flourish behind the creature."""
    s, sty, uid = ctx.s, ctx.sty, ctx.uid
    if level <= 0:
        return ""
    g = ""
    if s == 1:
        g += f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" stroke="{sty["seam"]}" stroke-width="2" opacity=".3"/>'
        for k in range(10):
            a = k * math.pi / 5
            g += (f'<line x1="{cx + math.cos(a) * r * 0.98:.1f}" y1="{cy + math.sin(a) * r * 0.98:.1f}" '
                  f'x2="{cx + math.cos(a) * r * 1.24:.1f}" y2="{cy + math.sin(a) * r * 1.24:.1f}" '
                  f'stroke="{ctx.glow}" stroke-width="1.4" opacity=".25"/>')
    elif s == 2:
        for i in range(3):
            g += (f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{r * (0.75 + i * 0.2):.1f}" ry="{r * (0.6 + i * 0.16):.1f}" '
                  f'fill="none" stroke="{sty["ice"]}" stroke-width="1.1" opacity="{0.34 - i * 0.09:.2f}"/>')
    elif s == 3:
        for k in range(9):
            a = k * 2 * math.pi / 9
            g += tuft("grass", cx + math.cos(a) * r, cy + math.sin(a) * r * 0.86, r * 0.13, ELE["grass"], math.degrees(a) + 90)
    elif s == 4:
        g += (f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="none" stroke="{sty["arc"]}" stroke-width="1.6" '
              f'stroke-dasharray="6 5" opacity=".45"/>')
        g += (f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r * 1.2:.1f}" fill="none" stroke="{ctx.glow}" stroke-width="1" '
              f'stroke-dasharray="2 6" opacity=".35"/>')
    else:
        if level >= 2:
            g += f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r * 1.15:.1f}" fill="url(#halo{uid})" opacity=".3"/>'
        for i, rot in enumerate((-22, 14)):
            g += (f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{r * (1.05 + i * 0.22):.1f}" ry="{r * (0.3 + i * 0.1):.1f}" '
                  f'fill="none" stroke="{sty["rift"] if i else ctx.glow}" stroke-width="{1.6 - i * 0.5:.1f}" '
                  f'opacity="{0.7 - i * 0.25:.2f}" transform="rotate({rot} {cx:.1f} {cy:.1f})"/>')
        g += starfield(cx - r, cy - r * 0.8, r * 2, r * 1.6, ctx.var["seed"] + 5, count=8, tint=sty["star"])
    return g


def sh_orbitals(ctx, cx, cy, r, n=3, seed=0):
    """Umbral Reach signature: pieces of the creature that broke off and stayed in orbit."""
    if ctx.s != 5:
        return sh_motes(ctx, cx, cy, r, n, seed)
    rr, sty, uid = ctx.rng(23 + seed), ctx.sty, ctx.uid
    n = min(n, 5)
    g = ""
    for i in range(n):
        a = (2 * math.pi * i / max(n, 1)) + rr.f(-0.35, 0.35)
        px = cx + math.cos(a) * r * rr.f(1.1, 1.4)
        py = cy + math.sin(a) * r * rr.f(0.66, 0.95)
        sz, rot = rr.f(2.6, 4.4), rr.f(0, 360)
        d = (f"M{px:.1f},{py - sz:.1f} L{px + sz * 0.62:.1f},{py - sz * 0.1:.1f} "
             f"L{px:.1f},{py + sz * 1.15:.1f} L{px - sz * 0.62:.1f},{py - sz * 0.1:.1f} Z")
        g += (f'<g transform="rotate({rot:.0f} {px:.1f} {py:.1f})">'
              f'<path d="{d}" fill="#150a2c" stroke="{sty["rift"]}" stroke-width="1"/>'
              f'<path d="M{px:.1f},{py - sz:.1f} L{px + sz * 0.62:.1f},{py - sz * 0.1:.1f} L{px:.1f},{py + sz * 1.15:.1f} Z" '
              f'fill="{ctx.glow}" opacity=".22"/></g>')
    for i in range(max(1, n // 2)):
        a = rr.f(0, 2 * math.pi)
        g += star(cx + math.cos(a) * r * rr.f(1.2, 1.5), cy + math.sin(a) * r * rr.f(0.7, 1.0),
                  rr.f(1.4, 2.4), sty["star"], .9)
    return g


def sh_face(ctx, hx, hy, r, mood="calm", mouth="smile", look=-0.8, pair=True, gap=None):
    g = sh_eyes(ctx, hx - r * 0.38, hy - r * 0.04, r * 0.26, look=look, mood=mood, pair=pair,
                gap=gap if gap is not None else r * 0.6)
    g += sh_mouth(ctx, hx - r * 0.92, hy + r * 0.52, r * 0.66, mouth)
    return g


def sh_mane(ctx, cx, cy, r, n=4, up=1.0):
    """Ruff / collar at the shoulders."""
    s, uid, sty, e, el, pal = ctx.s, ctx.uid, ctx.sty, ctx.e, ctx.el, ctx.pal
    g = ""
    for i in range(n):
        a = math.pi * (0.08 + 0.84 * i / max(1, n - 1))
        px, py = cx - math.cos(a) * r * 1.05, cy - math.sin(a) * r * 1.05 * up
        if s == 1:
            g += tuft("fire", px, py, r * 0.44, e, math.degrees(a) - 90)
        elif s == 2:
            g += P(ctx, f"M{px - r * 0.26:.1f},{py + r * 0.18:.1f} L{px:.1f},{py - r * 0.55:.1f} L{px + r * 0.26:.1f},{py + r * 0.18:.1f} Z", pal[1], 1.3, ' opacity=".92"')
        elif s == 3:
            g += tuft("grass", px, py, r * 0.42, ELE["grass"], math.degrees(a) - 90)
        elif s == 4:
            g += P(ctx, f"M{px - r * 0.2:.1f},{py + r * 0.2:.1f} L{px - r * 0.06:.1f},{py - r * 0.5:.1f} L{px + r * 0.24:.1f},{py - r * 0.1:.1f} Z", f"url(#metal{uid})", 1.2)
        else:
            g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{r * 0.26:.1f}" fill="url(#void{uid})" stroke="url(#rim{uid})" stroke-width="1.1"/>'
            g += star(px, py, r * 0.16, sty["star"], .95)
    return g


# ==================================================================================
# BODY PLANS — how a creature is put together. Concepts pick a plan and dress it.
# ==================================================================================
def bp_quad(ctx, p):
    """Four-legged beast, side profile, facing left."""
    cx, cy, bw, bh, hr = p["cx"], p["cy"], p["bw"], p["bh"], p["hr"]
    legh, lw = p.get("legh", bh * 1.0), p.get("lw", p["bw"] * 0.28)
    neck = min(p.get("neck", 0.0), 1.0)  # quads take a 0..1 neck lift, not pixels
    hx = cx - bw * (0.8 + p.get("dhx", 0.0)) - hr * 0.12
    hy = cy - bh * (0.66 + neck * 1.05) - hr * neck * 0.3
    gy = cy + bh + legh * 0.95
    g = sh_ground(ctx, cx, gy, bw * 1.05)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy - bh * 0.3, bw * 1.28, p["aura"])
    g += sh_tail(ctx, cx + bw * 0.86, cy - bh * 0.06, p.get("tsize", bh * 0.95), p.get("tail", "plume"))
    for i, wsgn in enumerate(p.get("wingsides", ())):
        g += sh_wing(ctx, cx + bw * 0.1, cy - bh * 0.7, p.get("wspan", bw * 0.8), p.get("wing", "spread"), p.get("stage", 1), wsgn)
    nl = p.get("legs", 4)
    if nl >= 4:
        for lx in (cx - bw * 0.3, cx + bw * 0.36):
            g += sh_leg(ctx, lx, cy + bh * 0.2, lw, legh, back=True)
    g += sh_torso(ctx, cx, cy, bw, bh)
    g += sh_spine(ctx, cx, cy, bw, bh, p.get("spine", "none"), p.get("spinen", 4))
    if nl:
        for lx in (cx - bw * 0.56, cx + bw * 0.6):
            g += sh_leg(ctx, lx, cy + bh * 0.26, lw, legh)
    if neck > 0.05:
        g += P(ctx, f"M{cx - bw * 0.82:.1f},{cy - bh * 0.2:.1f} L{hx - hr * 0.3:.1f},{hy + hr * 0.4:.1f} "
                    f"L{hx + hr * 0.55:.1f},{hy + hr * 0.7:.1f} L{cx - bw * 0.34:.1f},{cy - bh * 0.62:.1f} Z",
               f"url(#body{ctx.uid})", 2.0)
    if p.get("mane"):
        g += sh_mane(ctx, hx + hr * 0.5, hy + hr * 0.3, hr * 1.25, p.get("manen", 4))
    g += sh_head(ctx, hx, hy, hr, p.get("hkind", "muzzle"))
    g += sh_ears(ctx, hx, hy, hr, p.get("ears", "point"), p.get("espread", 1.0))
    g += sh_crest(ctx, hx, hy, hr, p.get("crest", "none"), p.get("stage", 1))
    g += sh_face(ctx, hx, hy, hr, p.get("mood", "calm"), p.get("mouth", "smile"), p.get("look", -0.8))
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy - bh * 0.2, bw * 1.2, p["motes"])
    return g


def bp_biped(ctx, p):
    """Upright figure: robe or torso over two legs, with arms."""
    cx, cy, bw, bh, hr = p["cx"], p["cy"], p["bw"], p["bh"], p["hr"]
    legh = p.get("legh", bh * 0.85)
    gy = cy + bh + legh
    hy = cy - bh - hr * 0.85
    g = sh_ground(ctx, cx, gy, bw * 1.15)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy - bh * 0.4, bw * 1.55, p["aura"])
    for wsgn in p.get("wingsides", ()):
        g += sh_wing(ctx, cx, cy - bh * 0.5, p.get("wspan", bw * 1.05), p.get("wing", "spread"), p.get("stage", 1), wsgn)
    if p.get("robe"):
        d = (f"M{cx - bw * 0.5:.1f},{cy - bh:.1f} L{cx + bw * 0.5:.1f},{cy - bh:.1f} L{cx + bw * 1.15:.1f},{gy:.1f} "
             f"Q{cx:.1f},{gy + bh * 0.28:.1f} {cx - bw * 1.15:.1f},{gy:.1f} Z")
        g += P(ctx, d, f"url(#body{ctx.uid})" if ctx.s != 5 else f"url(#void{ctx.uid})")
        if ctx.s == 5:
            cid = ctx.nid("cl")
            ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
            g += (f'<g clip-path="url(#{cid})">' + starfield(cx - bw * 1.2, cy - bh, bw * 2.4, bh + legh + 10,
                                                             ctx.var["seed"] + 3, count=22, tint=ctx.sty["star"]) + "</g>")
            g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="1.5" opacity=".9"/>'
        else:
            g += sh_marks(ctx, cx, cy + bh * 0.2, bw * 0.9, bh * 0.8)
    else:
        for lx in (cx - bw * 0.46, cx + bw * 0.46):
            g += sh_leg(ctx, lx, cy + bh * 0.5, p.get("lw", bw * 0.42), legh)
        g += sh_torso(ctx, cx, cy, bw, bh)
    aw = p.get("aw", bw * 0.34)
    for sgn in (-1, 1):
        g += sh_arm(ctx, cx + sgn * bw * 0.62, cy - bh * 0.42, cx + sgn * bw * (1.05 + p.get("reach", 0.0)),
                    cy + bh * (0.35 + p.get("armdrop", 0.0)), aw)
    if p.get("hands"):
        for sgn in (-1, 1):
            hxx = cx + sgn * bw * (1.05 + p.get("reach", 0.0))
            hyy = cy + bh * (0.35 + p.get("armdrop", 0.0))
            g += f'<circle cx="{hxx:.1f}" cy="{hyy:.1f}" r="{aw * 0.62:.1f}" fill="url(#{"void" if ctx.s == 5 else "body"}{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.5"/>'
    if p.get("core"):
        g += f'<circle cx="{cx:.1f}" cy="{cy + bh * 0.1:.1f}" r="{bw * 0.22:.1f}" fill="url(#orb{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.4"/>'
    if p.get("mane"):
        g += sh_mane(ctx, cx, cy - bh * 0.86, hr * 1.5, p.get("manen", 5))
    g += sh_head(ctx, cx, hy, hr, p.get("hkind", "blunt"))
    g += sh_ears(ctx, cx, hy, hr, p.get("ears", "none"), p.get("espread", 1.0))
    g += sh_crest(ctx, cx, hy, hr, p.get("crest", "crown"), p.get("stage", 1))
    g += sh_face(ctx, cx + hr * 0.34, hy, hr, p.get("mood", "calm"), p.get("mouth", "smile"), p.get("look", 0.0))
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy - bh * 0.3, bw * 1.5, p["motes"])
    return g


def bp_serpent(ctx, p):
    """Sinuous coil rising to a raised head — drakes, wyrms and eels."""
    cx, cy, k, hr = p["cx"], p["cy"], p.get("k", 1.0), p["hr"]
    coils = p.get("coils", 3)
    amp = p.get("amp", 26) * k
    span = p.get("span", 40) * k
    w = p.get("w", 13) * k
    g = sh_ground(ctx, cx + 6 * k, cy + 44 * k, span * 0.9)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy - 4, span * 1.25, p["aura"])
    pts = []
    for i in range(coils * 2 + 3):
        t = i / (coils * 2 + 2)
        px = cx + span * 0.75 - t * span * 1.5 + math.sin(t * math.pi * coils) * amp * 0.5
        py = cy + 40 * k - t * (78 * k)
        pts.append((px, py))
    d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
    stroke = {1: f"url(#body{ctx.uid})", 2: f"url(#body{ctx.uid})", 3: f"url(#wood{ctx.uid})",
              4: f"url(#metal{ctx.uid})", 5: "#3d1d70"}[ctx.s]
    g += f'<path d="{d}" fill="none" stroke="{ctx.ink}" stroke-width="{w + 4:.1f}" stroke-linejoin="round" stroke-linecap="round"/>'
    g += f'<path d="{d}" fill="none" stroke="{stroke}" stroke-width="{w:.1f}" stroke-linejoin="round" stroke-linecap="round"/>'
    if ctx.s == 5:
        g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="1.4" opacity=".85"/>'
        for (px, py) in pts[::2]:
            g += star(px, py, 2.0, ctx.sty["star"], .9)
    elif ctx.s == 4:
        for (px, py) in pts[1::2]:
            g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{w * 0.32:.1f}" fill="{ctx.sty["copper"]}" stroke="{ctx.ink}" stroke-width="1"/>'
    elif ctx.s == 1:
        for (px, py) in pts[1::2]:
            g += tuft("fire", px, py - w * 0.6, w * 0.5, ctx.e, 0)
    elif ctx.s == 3:
        for (px, py) in pts[1::2]:
            g += tuft("grass", px, py - w * 0.5, w * 0.5, ELE["grass"], -20)
    else:
        for (px, py) in pts[1::2]:
            g += P(ctx, f"M{px - w * 0.4:.1f},{py:.1f} L{px:.1f},{py - w * 0.8:.1f} L{px + w * 0.4:.1f},{py:.1f} Z", ctx.sty["ice"], 1.2)
    hx, hy = pts[-1]
    hx -= hr * 0.2
    hy -= hr * 0.5
    for wsgn in p.get("wingsides", ()):
        g += sh_wing(ctx, cx + 6 * k, cy - 6 * k, p.get("wspan", 30 * k), p.get("wing", "spread"), p.get("stage", 1), wsgn)
    g += sh_head(ctx, hx, hy, hr, p.get("hkind", "jaw"))
    g += sh_ears(ctx, hx, hy, hr, p.get("ears", "none"), p.get("espread", 1.0))
    g += sh_crest(ctx, hx, hy, hr, p.get("crest", "horn"), p.get("stage", 1))
    g += sh_face(ctx, hx, hy, hr, p.get("mood", "fierce"), p.get("mouth", "fang"), p.get("look", -0.9))
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, span * 1.1, p["motes"])
    return g


def bp_swimmer(ctx, p):
    """Finned body suspended mid-frame."""
    cx, cy, L, Hh = p["cx"], p["cy"], p["L"], p["H"]
    g = sh_ground(ctx, cx, cy + Hh + 26, L * 0.66)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy, L * 1.15, p["aura"])
    g += sh_tail(ctx, cx + L * 0.78, cy, p.get("tsize", Hh * 0.9), p.get("tail", "fluke"))
    g += sh_torso(ctx, cx, cy, L * 0.8, Hh, belly=True)
    g += sh_spine(ctx, cx, cy, L * 0.7, Hh, p.get("spine", "spikes"), p.get("spinen", 3))
    pf = p.get("pecfin", 1)
    if pf:
        g += (f'<path d="M{cx - L * 0.2:.1f},{cy + Hh * 0.35:.1f} q{-L * 0.28:.1f},{Hh * 0.6:.1f} '
              f'{-L * 0.04:.1f},{Hh * 0.85:.1f} q{L * 0.16:.1f},{-Hh * 0.36:.1f} {L * 0.1:.1f},{-Hh * 0.72:.1f} Z" '
              f'fill="url(#body2{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.5"/>')
    hx, hy = cx - L * 0.56, cy - Hh * 0.12
    g += sh_crest(ctx, hx, hy - Hh * 0.3, Hh * 0.5, p.get("crest", "none"), p.get("stage", 1))
    g += sh_face(ctx, hx + Hh * 0.28, hy, Hh * 0.62, p.get("mood", "calm"), p.get("mouth", "grin"),
                 p.get("look", -0.9), pair=p.get("pair", False))
    if p.get("lure"):
        g += (f'<path d="M{cx - L * 0.55:.1f},{cy - Hh * 0.8:.1f} q{-Hh * 0.4:.1f},{-Hh * 1.1:.1f} {Hh * 0.5:.1f},{-Hh * 1.5:.1f}" '
              f'fill="none" stroke="{ctx.pal[2]}" stroke-width="2"/>')
        g += f'<circle cx="{cx - L * 0.42:.1f}" cy="{cy - Hh * 2.3:.1f}" r="{Hh * 0.3:.1f}" fill="url(#orb{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.2"/>'
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, L * 0.95, p["motes"])
    return g


def bp_flyer(ctx, p):
    """Upright winged body on two legs — birds and cranes."""
    cx, cy, bw, bh, hr = p["cx"], p["cy"], p["bw"], p["bh"], p["hr"]
    legh = p.get("legh", 26)
    gy = cy + bh + legh
    g = sh_ground(ctx, cx, gy, bw * 1.9)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy - bh * 0.2, bh * 1.5, p["aura"])
    for lx in (cx - bw * 0.42, cx + bw * 0.42):
        if ctx.s == 4:
            g += (f'<polyline points="{lx:.1f},{cy + bh * 0.7:.1f} {lx + 4:.1f},{gy - legh * 0.4:.1f} {lx - 2:.1f},{gy:.1f}" '
                  f'fill="none" stroke="url(#metal{ctx.uid})" stroke-width="3" stroke-linejoin="round"/>')
        else:
            g += (f'<line x1="{lx:.1f}" y1="{cy + bh * 0.66:.1f}" x2="{lx:.1f}" y2="{gy:.1f}" '
                  f'stroke="{ctx.ink}" stroke-width="4.6" stroke-linecap="round"/>')
            g += (f'<line x1="{lx:.1f}" y1="{cy + bh * 0.66:.1f}" x2="{lx:.1f}" y2="{gy:.1f}" '
                  f'stroke="{ctx.pal[1] if ctx.s != 5 else ctx.sty["neb"]}" stroke-width="2.6" stroke-linecap="round"/>')
        g += (f'<path d="M{lx - 5:.1f},{gy + 1:.1f} h10 M{lx:.1f},{gy:.1f} v4" stroke="{ctx.ink}" '
              f'stroke-width="2.6" fill="none" stroke-linecap="round"/>')
    g += sh_tail(ctx, cx + bw * 0.3, cy + bh * 0.8, p.get("tsize", bh * 0.44), p.get("tail", "fan"))
    for wsgn in p.get("wingsides", (-1, 1)):
        g += sh_wing(ctx, cx + wsgn * bw * 0.5, cy - bh * 0.25, p.get("wspan", 30), p.get("wing", "spread"), p.get("stage", 1), wsgn)
    g += sh_torso(ctx, cx, cy, bw, bh)
    hy = cy - bh - hr * 0.72
    if p.get("neck", 0) > 0:
        nk = p["neck"]
        hy -= nk
        g += (f'<path d="M{cx - bw * 0.3:.1f},{cy - bh * 0.6:.1f} Q{cx - bw * 0.5:.1f},{hy + hr:.1f} {cx - hr * 0.5:.1f},{hy + hr * 0.7:.1f} '
              f'L{cx + hr * 0.5:.1f},{hy + hr * 0.9:.1f} Q{cx + bw * 0.2:.1f},{hy + hr * 1.4:.1f} {cx + bw * 0.34:.1f},{cy - bh * 0.5:.1f} Z" '
              f'fill="url(#{"void" if ctx.s == 5 else "body"}{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.9"/>')
    g += sh_head(ctx, cx, hy, hr, p.get("hkind", "beak"))
    g += sh_crest(ctx, cx, hy, hr, p.get("crest", "plume"), p.get("stage", 1))
    g += sh_face(ctx, cx + hr * 0.3, hy, hr, p.get("mood", "calm"), "none", p.get("look", -1.0))
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy - bh * 0.4, bw * 2.2, p["motes"])
    return g


def bp_insect(ctx, p):
    """Carapace, six legs, a working head — beetles, mites and grubs."""
    cx, cy, rw, rh = p["cx"], p["cy"], p["rw"], p["rh"]
    g = sh_ground(ctx, cx, cy + rh + 5, rw)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy, rw * 1.3, p["aura"])
    legc = p.get("legpairs", 3)
    for sgn in (-1, 1):
        for j in range(legc):
            ly = cy - rh * 0.25 + j * rh * (0.5 / max(1, legc - 1) * 2)
            if ctx.s == 4:
                g += (f'<polyline points="{cx + sgn * rw * 0.66:.1f},{ly:.1f} {cx + sgn * rw * 1.0:.1f},{ly - 3:.1f} '
                      f'{cx + sgn * rw * 1.12:.1f},{ly + 8:.1f}" fill="none" stroke="url(#metal{ctx.uid})" stroke-width="2.4" stroke-linejoin="round"/>')
            elif ctx.s == 5:
                g += (f'<path d="M{cx + sgn * rw * 0.7:.1f},{ly:.1f} q{sgn * rw * 0.36:.1f},-3 {sgn * rw * 0.5:.1f},7" fill="none" '
                      f'stroke="url(#void{ctx.uid})" stroke-width="2.6" stroke-linecap="round"/>')
                g += star(cx + sgn * rw * 1.2, ly + 7, 1.5, ctx.sty["star"], .85)
            else:
                g += (f'<path d="M{cx + sgn * rw * 0.7:.1f},{ly:.1f} q{sgn * rw * 0.36:.1f},-4 {sgn * rw * 0.5:.1f},6" fill="none" '
                      f'stroke="{ctx.pal[2]}" stroke-width="2.4" stroke-linecap="round"/>')
    hy = cy - rh * 0.8
    g += sh_head(ctx, cx, hy, rh * 0.44, p.get("hkind", "blunt"))
    g += sh_crest(ctx, cx, hy, rh * 0.5, p.get("crest", "horn"), p.get("stage", 1))
    d = sh_shape(ctx, cx, cy + rh * 0.1, rw, rh * 0.92, ctx.var["seed"] + 17)
    g += P(ctx, d, f"url(#void{ctx.uid})" if ctx.s == 5 else f"url(#body{ctx.uid})")
    if ctx.s == 5:
        cid = ctx.nid("cl")
        ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
        g += (f'<g clip-path="url(#{cid})">' + starfield(cx - rw, cy - rh, rw * 2, rh * 2, ctx.var["seed"] + 4,
                                                         count=14, tint=ctx.sty["star"]) + "</g>")
        g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="1.4" opacity=".9"/>'
    else:
        g += sh_marks(ctx, cx, cy + rh * 0.1, rw * 0.86, rh * 0.8)
    g += f'<line x1="{cx:.1f}" y1="{cy - rh * 0.72:.1f}" x2="{cx:.1f}" y2="{cy + rh * 0.86:.1f}" stroke="{ctx.ink}" stroke-width="1.6" opacity=".8"/>'
    if p.get("antennae"):
        for sgn in (-1, 1):
            g += (f'<path d="M{cx + sgn * rh * 0.22:.1f},{hy - rh * 0.3:.1f} q{sgn * 8:.1f},-9 {sgn * 14:.1f},-7" fill="none" '
                  f'stroke="{ctx.ink}" stroke-width="1.4" stroke-linecap="round"/>')
            g += tuft(ctx.el, cx + sgn * rh * 0.22 + sgn * 14, hy - rh * 0.3 - 7, 3.2, ctx.e, sgn * 30)
    g += sh_face(ctx, cx + rh * 0.36, hy, rh * 0.5, p.get("mood", "calm"), p.get("mouth", "none"), 0.0)
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, rw * 1.25, p["motes"])
    return g


def bp_wingbug(ctx, p):
    """Four wings, fuzzy thorax, antennae — moths, flies and their kin."""
    cx, cy, ws = p["cx"], p["cy"], p["ws"]
    g = sh_ground(ctx, cx, cy + 42, ws * 0.62)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy, ws * 1.05, p["aura"])
    for sgn in (-1, 1):
        if ctx.s == 5:
            for (dx, dy, rx, ry, rot) in [(0.52, -0.18, 0.5, 0.24, -16), (0.4, 0.2, 0.36, 0.17, 18)]:
                px, py = cx + sgn * ws * dx, cy + ws * dy
                d = smooth_poly(ring(px, py, ws * rx, ws * ry, 8, ctx.var["seed"] + int(dx * 100) + sgn, 0.16))
                cid = ctx.nid("cl")
                ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
                g += f'<path d="{d}" fill="url(#void{ctx.uid})" opacity=".95" transform="rotate({rot * sgn} {px:.1f} {py:.1f})"/>'
                g += (f'<g clip-path="url(#{cid})"><path d="{d}" fill="{ctx.sty["neb"]}" opacity=".4"/>'
                      + starfield(px - ws * rx, py - ws * ry, ws * rx * 2, ws * ry * 2, ctx.var["seed"] + int(rx * 90),
                                  count=9, tint=ctx.sty["star"]) + "</g>")
                g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="1.2" opacity=".9"/>'
        else:
            g += (f'<path d="M{cx:.1f},{cy - ws * 0.1:.1f} Q{cx + sgn * ws * 0.62:.1f},{cy - ws * 0.42:.1f} '
                  f'{cx + sgn * ws * 0.58:.1f},{cy - ws * 0.02:.1f} Q{cx + sgn * ws * 0.4:.1f},{cy + ws * 0.06:.1f} '
                  f'{cx:.1f},{cy:.1f} Z" fill="url(#body{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.9"/>')
            g += (f'<path d="M{cx:.1f},{cy + ws * 0.03:.1f} Q{cx + sgn * ws * 0.44:.1f},{cy + ws * 0.16:.1f} '
                  f'{cx + sgn * ws * 0.38:.1f},{cy + ws * 0.36:.1f} Q{cx + sgn * ws * 0.2:.1f},{cy + ws * 0.3:.1f} '
                  f'{cx:.1f},{cy + ws * 0.1:.1f} Z" fill="url(#body2{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.7"/>')
            g += spots(ctx.el, [(cx + sgn * ws * 0.34, cy - ws * 0.16, 3.2), (cx + sgn * ws * 0.28, cy + ws * 0.2, 2.6)], ctx.e)
    g += (f'<ellipse cx="{cx:.1f}" cy="{cy + ws * 0.06:.1f}" rx="{ws * 0.09:.1f}" ry="{ws * 0.22:.1f}" '
          f'fill="url(#{"void" if ctx.s == 5 else "belly"}{ctx.uid})" stroke="{ctx.ink}" stroke-width="1.6"/>')
    hy = cy - ws * 0.2
    g += sh_head(ctx, cx, hy, ws * 0.11, "blunt")
    for sgn in (-1, 1):
        g += (f'<path d="M{cx + sgn * 3:.1f},{hy - ws * 0.08:.1f} q{sgn * 9:.1f},-10 {sgn * 15:.1f},-8" fill="none" '
              f'stroke="{ctx.ink}" stroke-width="1.5" stroke-linecap="round"/>')
        if ctx.s == 5:
            g += star(cx + sgn * 15, hy - ws * 0.08 - 8, 2.2, ctx.sty["star"], .95)
        else:
            g += tuft(ctx.el, cx + sgn * 15, hy - ws * 0.08 - 8, 3.4, ctx.e, sgn * 30)
    g += sh_face(ctx, cx + ws * 0.08, hy, ws * 0.14, p.get("mood", "calm"), "none", 0.0)
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, ws * 0.72, p["motes"])
    return g


def bp_float(ctx, p):
    """Hovering core with trailing tendrils — wisps, jellies and lanterns."""
    cx, cy, r = p["cx"], p["cy"], p["r"]
    g = sh_ground(ctx, cx, cy + r * 2.6, r * 0.9)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy, r * 1.9, p["aura"])
    n = p.get("tendrils", 5)
    for i in range(n):
        tx = cx - r * 0.7 + i * (r * 1.4 / max(1, n - 1))
        sway = -5 if i % 2 else 5
        if ctx.s == 5:
            g += (f'<path d="M{tx:.1f},{cy + r * 0.6:.1f} q{sway:.0f},{r * 0.9:.1f} {sway * 0.3:.0f},{r * 1.8:.1f}" fill="none" '
                  f'stroke="{ctx.sty["neb"]}" stroke-width="2.2" opacity=".85" stroke-linecap="round"/>')
            g += star(tx + sway * 0.3, cy + r * 2.4, 1.8, ctx.sty["star"], .9)
        else:
            g += (f'<path d="M{tx:.1f},{cy + r * 0.6:.1f} q{sway:.0f},{r * 0.9:.1f} {sway * 0.3:.0f},{r * 1.8:.1f}" fill="none" '
                  f'stroke="{ctx.pal[1]}" stroke-width="2.4" opacity=".9" stroke-linecap="round"/>')
    if p.get("bell", 1):
        d = (f"M{cx - r:.1f},{cy + r * 0.55:.1f} a{r:.1f},{r * 0.92:.1f} 0 0 1 {r * 2:.1f},0 "
             f"Q{cx:.1f},{cy + r * 0.9:.1f} {cx - r:.1f},{cy + r * 0.55:.1f} Z")
        g += P(ctx, d, f"url(#orb{ctx.uid})" if ctx.s != 5 else f"url(#void{ctx.uid})")
        if ctx.s == 5:
            cid = ctx.nid("cl")
            ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
            g += (f'<g clip-path="url(#{cid})">' + starfield(cx - r, cy - r, r * 2, r * 1.8, ctx.var["seed"] + 8,
                                                             count=12, tint=ctx.sty["star"]) + "</g>")
            g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="1.4" opacity=".9"/>'
    else:
        g += f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="url(#orb{ctx.uid})" stroke="{ctx.ink}" stroke-width="2"/>'
    g += sh_crest(ctx, cx, cy - r * 0.2, r * 0.7, p.get("crest", "plume"), p.get("stage", 1))
    g += sh_face(ctx, cx + r * 0.28, cy + r * 0.05, r * 0.72, p.get("mood", "calm"), p.get("mouth", "smile"), 0.0)
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, r * 1.6, p["motes"])
    return g


def bp_plant(ctx, p):
    """Rooted body with a crown — sprouts, buds and thickets."""
    cx, cy, bw, bh = p["cx"], p["cy"], p["bw"], p["bh"]
    g = sh_ground(ctx, cx, cy + bh + 4, bw * 1.35)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy - bh * 0.3, bw * 1.9, p["aura"])
    for sgn in (-1, 1):
        g += sh_arm(ctx, cx + sgn * bw * 0.8, cy - bh * 0.1, cx + sgn * bw * 1.7, cy - bh * (0.6 + p.get("armlift", 0.0)), bw * 0.24)
        if ctx.s == 5:
            g += star(cx + sgn * bw * 1.7, cy - bh * (0.6 + p.get("armlift", 0.0)), 2.6, ctx.sty["star"], .95)
        else:
            g += tuft(ctx.el, cx + sgn * bw * 1.78, cy - bh * (0.68 + p.get("armlift", 0.0)), bw * 0.38, ctx.e, sgn * 52)
    g += sh_torso(ctx, cx, cy, bw, bh)
    fy = cy - bh - bw * 0.16
    petals = p.get("petals", 5)
    pr = p.get("pr", bw * 0.9)
    for i in range(petals):
        a = math.pi * (0.1 + 0.8 * i / max(1, petals - 1))
        px, py = cx - math.cos(a) * pr, fy - math.sin(a) * pr * 0.74
        if ctx.s == 5:
            g += f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{pr * 0.2:.1f}" fill="url(#void{ctx.uid})" stroke="url(#rim{ctx.uid})" stroke-width="1.1"/>'
            g += star(px, py, pr * 0.13, ctx.sty["star"], .95)
        else:
            g += tuft(ctx.el, px, py, pr * 0.42, ctx.e, math.degrees(a) - 90)
    g += (f'<circle cx="{cx:.1f}" cy="{fy + bw * 0.16:.1f}" r="{bw * 0.3:.1f}" fill="url(#orb{ctx.uid})" '
          f'stroke="{ctx.ink}" stroke-width="1.6"/>')
    g += sh_face(ctx, cx + bw * 0.3, cy - bh * 0.06, bw * 0.8, p.get("mood", "calm"), p.get("mouth", "smile"), 0.0)
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy - bh * 0.2, bw * 1.7, p["motes"])
    return g


def bp_shell(ctx, p):
    """A hard home plus whatever pokes out of it — crabs and snails."""
    cx, cy, rw, rh = p["cx"], p["cy"], p["rw"], p["rh"]
    kind = p.get("shell", "dome")
    g = sh_ground(ctx, cx, cy + rh + 8, rw * 1.15)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy, rw * 1.25, p["aura"])
    if kind == "dome":
        for sgn in (-1, 1):
            for j in range(3):
                g += (f'<path d="M{cx + sgn * rw * 0.7:.1f},{cy + 4 + j * 4:.1f} q{sgn * rw * 0.4:.1f},4 {sgn * rw * 0.48:.1f},14" '
                      f'fill="none" stroke="{ctx.pal[2] if ctx.s != 5 else ctx.sty["neb"]}" stroke-width="2.4" stroke-linecap="round"/>')
            g += sh_arm(ctx, cx + sgn * rw * 0.66, cy - 2, cx + sgn * rw * 1.36, cy - rh * 0.6, 5)
            cxx, cyy = cx + sgn * rw * 1.44, cy - rh * 0.7
            g += P(ctx, f"M{cxx:.1f},{cyy:.1f} q{sgn * 10:.1f},-6 {sgn * 2:.1f},-12 q{-sgn * 6:.1f},2 {-sgn * 2:.1f},8 "
                        f"q{-sgn * 8:.1f},-2 {-sgn * 8:.1f},6 Z",
                   f"url(#void{ctx.uid})" if ctx.s == 5 else f"url(#body{ctx.uid})", 1.6)
        d = sh_shape(ctx, cx, cy - rh * 0.1, rw, rh, ctx.var["seed"] + 19)
        g += P(ctx, d, f"url(#void{ctx.uid})" if ctx.s == 5 else f"url(#body{ctx.uid})")
        if ctx.s == 5:
            cid = ctx.nid("cl")
            ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
            g += (f'<g clip-path="url(#{cid})">' + starfield(cx - rw, cy - rh, rw * 2, rh * 2, ctx.var["seed"] + 6,
                                                             count=14, tint=ctx.sty["star"]) + "</g>")
            g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="1.4" opacity=".9"/>'
        else:
            g += sh_marks(ctx, cx, cy - rh * 0.1, rw * 0.8, rh * 0.8)
        for sgn in (-1, 1):
            g += (f'<line x1="{cx + sgn * rw * 0.24:.1f}" y1="{cy - rh * 0.6:.1f}" x2="{cx + sgn * rw * 0.26:.1f}" '
                  f'y2="{cy - rh * 1.15:.1f}" stroke="{ctx.pal[2] if ctx.s != 5 else ctx.sty["neb"]}" stroke-width="2.4"/>')
        g += sh_eyes(ctx, cx - rw * 0.26, cy - rh * 1.24, 3.0, look=0, mood=p.get("mood", "calm"), gap=rw * 0.52)
        g += sh_mouth(ctx, cx - rw * 0.22, cy + rh * 0.28, rw * 0.44, p.get("mouth", "grin"))
    else:  # coiled shell on a soft body
        g += (f'<path d="M{cx - rw * 1.2:.1f},{cy + rh * 0.6:.1f} q-2,-14 {rw * 0.5:.1f},-14 l{rw * 0.62:.1f},0 '
              f'q{rw * 0.2:.1f},10 {-rw * 0.14:.1f},14 Z" fill="url(#{"void" if ctx.s == 5 else "belly"}{ctx.uid})" '
              f'stroke="{ctx.ink}" stroke-width="2"/>')
        hx, hy = cx - rw * 1.12, cy - rh * 0.12
        g += sh_head(ctx, hx, hy, rw * 0.3, "blunt")
        for sgn in (-1, 1):
            g += (f'<line x1="{hx - rw * 0.06:.1f}" y1="{hy - rw * 0.26:.1f}" x2="{hx - rw * 0.2:.1f}" '
                  f'y2="{hy - rw * 0.26 + sgn * rw * 0.3:.1f}" stroke="{ctx.pal[2] if ctx.s != 5 else ctx.sty["neb"]}" stroke-width="2"/>')
        g += sh_face(ctx, hx + rw * 0.12, hy, rw * 0.34, p.get("mood", "calm"), "none", -0.9, pair=False)
        d = sh_shape(ctx, cx, cy - rh * 0.2, rw * 0.78, rh * 0.86, ctx.var["seed"] + 23)
        g += P(ctx, d, f"url(#void{ctx.uid})" if ctx.s == 5 else f"url(#body{ctx.uid})")
        spiral = (f'M{cx:.1f},{cy - rh * 0.2:.1f} m0,0 a4,4 0 1 1 6,-2 a9,9 0 1 1 -13,3 a15,15 0 1 1 22,-4')
        g += f'<path d="{spiral}" fill="none" stroke="{ctx.sty["star"] if ctx.s == 5 else ctx.pal[3]}" stroke-width="1.8" opacity=".9"/>'
        g += sh_crest(ctx, cx, cy - rh * 0.9, rw * 0.4, p.get("crest", "plume"), p.get("stage", 1))
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, rw * 1.3, p["motes"])
    return g


def bp_construct(ctx, p):
    """Built, not born: stacked masses with a glowing face."""
    cx, cy, bw, bh = p["cx"], p["cy"], p["bw"], p["bh"]
    g = sh_ground(ctx, cx, cy + bh * 1.9, bw * 1.1)
    if p.get("aura"):
        g += sh_aura(ctx, cx, cy - bh * 0.2, bw * 1.5, p["aura"])
    float_parts = ctx.s == 5 or p.get("float")
    gap = bh * (0.34 if float_parts else 0.0)
    for lx in (cx - bw * 0.5, cx + bw * 0.5):
        if float_parts:
            d = sh_shape(ctx, lx, cy + bh * 1.4, bw * 0.36, bh * 0.5, ctx.var["seed"] + int(lx))
            g += P(ctx, d, f"url(#void{ctx.uid})" if ctx.s == 5 else f"url(#body2{ctx.uid})", 1.8)
        else:
            g += sh_leg(ctx, lx, cy + bh * 0.62, bw * 0.44, bh * 0.8)
    for sgn in (-1, 1):
        ax = cx + sgn * (bw + bw * 0.02)
        d = sh_shape(ctx, ax, cy + bh * 0.28 + gap, bw * 0.3, bh * 0.66, ctx.var["seed"] + 40 + sgn)
        g += P(ctx, d, f"url(#void{ctx.uid})" if ctx.s == 5 else f"url(#body2{ctx.uid})", 2.0)
    g += sh_torso(ctx, cx, cy, bw, bh, belly=False)
    g += (f'<rect x="{cx - bw * 0.62:.1f}" y="{cy - bh * 0.55:.1f}" width="{bw * 1.24:.1f}" height="{bh * 0.9:.1f}" '
          f'rx="{bw * 0.2:.1f}" fill="{ctx.pal[3]}" opacity=".55"/>')
    g += sh_eyes(ctx, cx - bw * 0.28, cy - bh * 0.1, bw * 0.15, look=0, mood=p.get("mood", "calm"), gap=bw * 0.56)
    g += sh_mouth(ctx, cx - bw * 0.3, cy + bh * 0.34, bw * 0.6, p.get("mouth", "grin"))
    g += sh_crest(ctx, cx, cy - bh * 0.95, bw * 0.44, p.get("crest", "crown"), p.get("stage", 1))
    if p.get("motes"):
        g += sh_orbitals(ctx, cx, cy, bw * 1.4, p["motes"])
    return g


PLANS = {
    "quad": bp_quad, "biped": bp_biped, "serpent": bp_serpent, "swimmer": bp_swimmer,
    "flyer": bp_flyer, "insect": bp_insect, "wingbug": bp_wingbug, "float": bp_float,
    "plant": bp_plant, "shell": bp_shell, "construct": bp_construct,
}


# --------------------------------------------------------------- card -> role
SETS = [
  {"element": "fire",
   "lines3": [["Emberpup", "Cinderhound", "Pyrewolf"], ["Pebblit", "Boulderkin", "Magmalith"],
              ["Wickling", "Candloth", "Infernaya"], ["Emberchick", "Blazecrow", "Cindraven"],
              ["Flintling", "Scorchmaw", "Vulcanine"], ["Emberling", "Scaldrake", "Pyrothraxx"]],
   "lines2": [["Ashling", "Cendrake"], ["Flicktail", "Emberdon"], ["Sootcub", "Charbruin"],
              ["Smoldfin", "Searpike"], ["Kindlebug", "Flarebeetle"], ["Emberkit", "Flarelynx"],
              ["Torchbud", "Bloomfire"]],
   "singles_common": ["Sootmoth", "Coalcrab", "Wispfox", "Flarebud", "Torchfin", "Ashhare",
                      "Cindermite", "Smokewisp", "Charsnail", "Emberfly", "Warmtoad", "Glowmoth"],
   "singles_uncommon": ["Magmaw", "Blazehorn"], "singles_rare": ["Obsidra"],
   "singles_ultra": ["Ignarok", "Solmyr", "Emberyx"]},
  {"element": "water",
   "lines3": [["Dripling", "Splashound", "Tidalwolf"], ["Frostnib", "Glacikin", "Glacialith"],
              ["Bubblet", "Coralad", "Reeflord"], ["Mistchick", "Fogcrane", "Vaporegal"],
              ["Snowpup", "Frostmaw", "Blizzardine"], ["Rilling", "Streamsnout", "Torrentyx"]],
   "lines2": [["Puddlit", "Marshark"], ["Icktail", "Frostdon"], ["Sleetcub", "Chillbruin"],
              ["Minnowisp", "Anglerfright"], ["Krillbug", "Nautibeetle"], ["Frostkit", "Rimelynx"],
              ["Kelpbud", "Bloomtide"]],
   "singles_common": ["Dewmoth", "Icecrab", "Mistfox", "Foambud", "Coldfin", "Snowhare",
                      "Frostmite", "Vaporwisp", "Shellsnail", "Brinefly", "Chilltoad", "Glowjelly"],
   "singles_uncommon": ["Maelmaw", "Frosthorn"], "singles_rare": ["Nacreon"],
   "singles_ultra": ["Abyssos", "Glaciera", "Maelstros"]},
  {"element": "grass",
   "lines3": [["Seedling", "Sprouthound", "Thornwolf"], ["Budnib", "Bloomkin", "Bloomalith"],
              ["Vinelet", "Bramblad", "Canopylord"], ["Sporechick", "Mosscrane", "Verduregal"],
              ["Leafpup", "Thornmaw", "Sylvandine"], ["Rootling", "Barksnout", "Titanyx"]],
   "lines2": [["Spriglit", "Bramblark"], ["Ivytail", "Petaldon"], ["Ferncub", "Timberbruin"],
              ["Tadseed", "Lilypike"], ["Aphidbug", "Beetlebloom"], ["Sporekit", "Mosslynx"],
              ["Seedbud", "Bloomthicket"]],
   "singles_common": ["Pollmoth", "Barkcrab", "Fernfox", "Petalbud", "Reedfin", "Cloverhare",
                      "Sporemite", "Pollenwisp", "Vinesnail", "Dewfly", "Mosstoad", "Glowspore"],
   "singles_uncommon": ["Bramblehorn", "Saproot"], "singles_rare": ["Verdanox"],
   "singles_ultra": ["Sylvareth", "Floreon", "Eldwyrm"]},
  {"element": "electric",
   "lines3": [["Sparkpup", "Volthound", "Thunderwolf"], ["Zapnib", "Boltkin", "Fulgralith"],
              ["Statlet", "Arclad", "Stormlord"], ["Fizzchick", "Wattcrane", "Voltregal"],
              ["Joltpup", "Surgemaw", "Galvandine"], ["Currentling", "Coilsnout", "Teslyx"]],
   "lines2": [["Buzzlit", "Sparkshark"], ["Ziptail", "Voltdon"], ["Staticub", "Thunderbruin"],
              ["Sparkfin", "Zappike"], ["Mothbolt", "Beetlesurge"], ["Joltkit", "Arclynx"],
              ["Sparkbud", "Boltthicket"]],
   "singles_common": ["Zapmoth", "Voltcrab", "Sparkfox", "Fizzbud", "Wattfin", "Bolthare",
                      "Staticmite", "Ozonewisp", "Coilsnail", "Amperefly", "Buzztoad", "Glowvolt"],
   "singles_uncommon": ["Surgehorn", "Dynamaw"], "singles_rare": ["Voltanox"],
   "singles_ultra": ["Fulguros", "Tempesta", "Voltaeon"]},
  {"element": "shadow",
   "lines3": [["Duskpup", "Shadowhound", "Nightwolf"], ["Voidnib", "Umbrakin", "Voidalith"],
              ["Gloamlet", "Shadelad", "Eclipselord"], ["Wispchick", "Nebulacrane", "Astregal"],
              ["Shadepup", "Diremaw", "Umbrandine"], ["Riftling", "Starsnout", "Cosmyx"]],
   "lines2": [["Murklit", "Voidshark"], ["Shadetail", "Umbradon"], ["Gloomcub", "Nightbruin"],
              ["Inkfin", "Voidpike"], ["Mothshade", "Beetlevoid"], ["Duskkit", "Shadelynx"],
              ["Starbud", "Voidthicket"]],
   "singles_common": ["Duskmoth", "Voidcrab", "Shadefox", "Gloombud", "Darkfin", "Umbrahare",
                      "Shademite", "Netherwisp", "Voidsnail", "Cometfly", "Murktoad", "Glowshade"],
   "singles_uncommon": ["Nebulahorn", "Riftmaw"], "singles_rare": ["Umbranox"],
   "singles_ultra": ["Nyxaros", "Astralon", "Eclipsar"]},
]

LINE3_SLOTS = ["canine", "golem", "lord", "bird", "saber", "dragon"]
LINE2_SLOTS = ["shark", "don", "bear", "fish", "beetle", "lynx", "plant"]
SINGLE_COMMON_SLOTS = ["moth", "crab", "fox", "sprout", "finling", "hare",
                       "mite", "wisp", "snail", "fly", "toad", "glow"]


def build_roles():
    """name -> dict(set, slot, stage, sc, leg). One (set, slot, stage) per card."""
    roles = {}
    for si, s in enumerate(SETS):
        n = si + 1
        for li, line in enumerate(s["lines3"]):
            for st, nm in enumerate(line):
                roles[nm] = dict(set=n, slot=LINE3_SLOTS[li], stage=st + 1, sc=3, leg=None)
        for li, line in enumerate(s["lines2"]):
            for st, nm in enumerate(line):
                roles[nm] = dict(set=n, slot=LINE2_SLOTS[li], stage=st + 1, sc=2, leg=None)
        for i, nm in enumerate(s["singles_common"]):
            roles[nm] = dict(set=n, slot=SINGLE_COMMON_SLOTS[i], stage=1, sc=1, leg=None)
        for nm in s["singles_uncommon"]:
            # The name decides the body, not the list order: "-horn" cards get horns.
            roles[nm] = dict(set=n, slot="horn" if nm.endswith("horn") else "maw",
                             stage=1, sc=1, leg=None)
        for nm in s["singles_rare"]:
            roles[nm] = dict(set=n, slot="majestic", stage=1, sc=1, leg=None)
        for nm in s["singles_ultra"]:
            roles[nm] = dict(set=n, slot="legendary", stage=1, sc=1, leg=nm)
    return roles


ROLES = build_roles()


# ------------------------------------------------------------- concept tables
# SLOT_BASE gives the family silhouette and how it grows across a line.
# SET_OVR then re-imagines that family for one set, so (set, slot) is a
# different creature everywhere, not a palette swap.
SLOT_BASE = {
    "canine": dict(plan="quad", base=dict(cx=108, cy=80, bw=34, bh=23, hr=18, legh=22,
                                          hkind="muzzle", ears="point", tail="plume", mouth="smile"),
                   st=[dict(bw=25, bh=17, hr=14, legh=15, tsize=15),
                       dict(bw=32, bh=22, hr=17, legh=21, spine="spikes", spinen=4, tsize=22),
                       dict(bw=37, bh=24, hr=19, legh=27, spine="spikes", spinen=6, tsize=28,
                            mouth="fang", mood="fierce", crest="horn")]),
    "golem": dict(plan="construct", base=dict(cx=108, cy=74, bw=26, bh=24, mouth="grin"),
                  st=[dict(bw=18, bh=16, crest="none", cy=84),
                      dict(bw=25, bh=23, crest="cap", cy=78),
                      dict(bw=33, bh=30, crest="crown", aura=1, float=1, mood="fierce", mouth="fang")]),
    "lord": dict(plan="biped", base=dict(cx=108, cy=76, bw=21, bh=23, hr=15, legh=20,
                                         crest="crown", hands=1, core=1),
                 st=[dict(bw=14, bh=15, hr=11, legh=14, crest="cap", core=0, hands=0),
                     dict(bw=19, bh=21, hr=14, robe=1),
                     dict(bw=24, bh=27, hr=17, robe=1, wingsides=(-1, 1), wspan=30, aura=2,
                          mane=1, mood="fierce")]),
    "bird": dict(plan="flyer", base=dict(cx=108, cy=76, bw=19, bh=21, hr=12, legh=24,
                                         tail="fan", crest="plume"),
                 st=[dict(bw=13, bh=14, hr=9, legh=15, wspan=17, tsize=9),
                     dict(bw=18, bh=20, hr=11, legh=25, wspan=27, neck=10, tsize=13),
                     dict(bw=22, bh=24, hr=13, legh=30, wspan=38, neck=20, tsize=19, aura=1,
                          mood="fierce")]),
    "saber": dict(plan="quad", base=dict(cx=108, cy=82, bw=38, bh=27, hr=20, legh=14,
                                         hkind="feline", ears="small", tail="brush",
                                         mouth="fang", mood="fierce", espread=0.75, lw=13),
                  st=[dict(bw=27, bh=20, hr=15, legh=10, mouth="smile", mood="calm", tsize=15),
                      dict(bw=35, bh=26, hr=19, legh=13, mane=1, manen=4, tsize=20),
                      dict(bw=43, bh=32, hr=23, legh=16, mane=1, manen=7, spine="spikes",
                           spinen=6, tsize=25, dhx=0.04)]),
    "dragon": dict(plan="serpent", base=dict(cx=104, cy=74, hr=16, coils=3, hkind="jaw",
                                             crest="horn", mouth="fang", mood="fierce"),
                   st=[dict(k=0.66, hr=11, coils=2, crest="none", mouth="smile", mood="calm"),
                       dict(k=0.86, hr=14, coils=3),
                       dict(k=1.08, hr=18, coils=4, wingsides=(-1, 1), wspan=42, aura=2, ears="point")]),
    "shark": dict(plan="swimmer", base=dict(cx=108, cy=76, L=44, H=20, tail="fluke",
                                            spine="sail", mouth="fang", mood="fierce"),
                  st=[dict(L=34, H=15, spinen=2, tsize=14),
                      dict(L=50, H=23, spinen=4, tsize=22, crest="horn", aura=1)]),
    "don": dict(plan="quad", base=dict(cx=108, cy=80, bw=32, bh=22, hr=17, legh=22,
                                       hkind="muzzle", ears="round", tail="brush", neck=0.35),
                st=[dict(bw=25, bh=17, hr=14, legh=16, neck=0.0, tsize=17),
                    dict(bw=35, bh=24, hr=19, legh=25, neck=0.55, crest="crown", aura=1,
                         tsize=26, spine="rings", spinen=5)]),
    "bear": dict(plan="biped", base=dict(cx=108, cy=80, bw=25, bh=22, hr=17, legh=16,
                                         ears="round", hands=1, mouth="grin", lw=16),
                 st=[dict(bw=19, bh=17, hr=14, legh=12),
                     dict(bw=29, bh=26, hr=20, legh=19, mane=1, manen=5, mood="fierce",
                          mouth="fang", crest="horn", armdrop=0.15)]),
    "fish": dict(plan="swimmer", base=dict(cx=108, cy=78, L=38, H=17, tail="fan",
                                           spine="spikes", mouth="grin"),
                 st=[dict(L=28, H=13, spinen=2, tsize=11),
                     dict(L=44, H=20, spinen=4, tsize=18, lure=1, mouth="fang", mood="fierce")]),
    "beetle": dict(plan="insect", base=dict(cx=108, cy=84, rw=27, rh=22, crest="horn",
                                            antennae=1, mouth="none"),
                   st=[dict(rw=20, rh=16, crest="none"),
                       dict(rw=31, rh=26, crest="horn", aura=1, legpairs=3, mood="fierce")]),
    "lynx": dict(plan="quad", base=dict(cx=108, cy=74, bw=28, bh=16, hr=15, legh=32,
                                        hkind="feline", ears="tuft", tail="whip", espread=1.2, lw=6),
                 st=[dict(bw=23, bh=13, hr=12, legh=25, tsize=18),
                     dict(bw=31, bh=18, hr=17, legh=36, tsize=27, spine="spikes",
                          spinen=3, mood="fierce")]),
    "plant": dict(plan="plant", base=dict(cx=108, cy=96, bw=17, bh=26, petals=5, pr=26),
                  st=[dict(bw=12, bh=18, petals=4, pr=18),
                      dict(bw=21, bh=32, petals=7, pr=33, aura=1, armlift=0.25)]),
    "moth": dict(plan="wingbug", base=dict(cx=108, cy=72, ws=62, mood="calm")),
    "crab": dict(plan="shell", base=dict(cx=108, cy=84, rw=28, rh=20, shell="dome", mouth="grin")),
    "fox": dict(plan="quad", base=dict(cx=110, cy=84, bw=24, bh=16, hr=17, legh=17, lw=6,
                                       hkind="feline", ears="point", espread=1.5,
                                       tail="brush", tsize=30)),
    "sprout": dict(plan="plant", base=dict(cx=108, cy=100, bw=13, bh=17, petals=3, pr=17, armlift=0.3)),
    "finling": dict(plan="swimmer", base=dict(cx=108, cy=80, L=30, H=14, tail="frond",
                                              spine="none", pecfin=1, tsize=12, mouth="smile")),
    "hare": dict(plan="biped", base=dict(cx=108, cy=86, bw=17, bh=16, hr=14, legh=18,
                                         ears="long", espread=0.7, hands=1, mouth="smile")),
    "mite": dict(plan="insect", base=dict(cx=108, cy=92, rw=17, rh=14, legpairs=2,
                                          crest="none", antennae=1, mouth="grin")),
    "wisp": dict(plan="float", base=dict(cx=108, cy=68, r=17, bell=0, tendrils=4,
                                         crest="plume", mouth="smile", aura=1)),
    "snail": dict(plan="shell", base=dict(cx=112, cy=84, rw=24, rh=20, shell="coil", crest="plume")),
    "fly": dict(plan="wingbug", base=dict(cx=108, cy=74, ws=44, mood="fierce")),
    "toad": dict(plan="quad", base=dict(cx=108, cy=92, bw=30, bh=17, hr=17, legh=8, lw=12,
                                        hkind="toad", ears="none", tail="none", mouth="grin",
                                        look=-0.2, dhx=-0.12)),
    "glow": dict(plan="float", base=dict(cx=108, cy=66, r=20, bell=1, tendrils=6,
                                         crest="none", mouth="smile", aura=2)),
    "maw": dict(plan="quad", base=dict(cx=108, cy=84, bw=31, bh=22, hr=22, legh=13, lw=12,
                                       hkind="jaw", ears="none", tail="whip", spine="sail",
                                       spinen=5, mouth="fang", mood="fierce", dhx=0.1, tsize=24)),
    "horn": dict(plan="quad", base=dict(cx=108, cy=80, bw=33, bh=24, hr=18, legh=22,
                                        hkind="blunt", ears="small", tail="prong", crest="horn",
                                        stage=3, spine="rings", spinen=4, tsize=20)),
    "majestic": dict(plan="flyer", base=dict(cx=108, cy=74, bw=21, bh=23, hr=13, legh=28,
                                             wspan=36, neck=14, tail="fan", tsize=18,
                                             crest="crown", aura=2, motes=4, stage=3)),
}


# Emberfall — cooling crust over a living furnace. Heavy, plated, ember-crowned.
_S1 = {
    "canine": dict(tail="plume", ears="point", espread=1.1,
                   st=[dict(), dict(crest="horn"), dict(crest="horn", motes=4)]),
    "golem": dict(mouth="grin", st=[dict(), dict(crest="horn"), dict(crest="crown", motes=5)]),
    "lord": dict(crest="plume", st=[dict(crest="plume"), dict(crest="plume", core=1),
                                    dict(crest="crown", motes=4, wing="spread")]),
    "bird": dict(tail="plume", crest="plume", st=[dict(), dict(crest="horn"),
                                                  dict(crest="crown", motes=5, wspan=42)]),
    "saber": dict(crest="none", tail="brush",
                  st=[dict(), dict(manen=5), dict(manen=8, motes=4)]),
    "dragon": dict(crest="horn", st=[dict(), dict(spine="spikes"), dict(motes=6, aura=2)]),
    "shark": dict(tail="fluke", spine="sail", st=[dict(), dict(crest="horn", motes=4)]),
    "don": dict(ears="round", tail="brush", st=[dict(), dict(crest="crown", motes=3)]),
    "bear": dict(ears="round", st=[dict(), dict(crest="horn", motes=3)]),
    "fish": dict(tail="fan", st=[dict(), dict(lure=1, motes=3)]),
    "beetle": dict(crest="horn", st=[dict(), dict(crest="antler", motes=4)]),
    "lynx": dict(ears="tuft", tail="whip", st=[dict(), dict(motes=3, mane=1, manen=3)]),
    "plant": dict(petals=5, st=[dict(), dict(petals=8, pr=35, motes=4)]),
    "moth": dict(ws=60, motes=4),
    "crab": dict(rw=29, rh=19, crest="horn", mood="fierce"),
    "fox": dict(tail="plume", tsize=29, ears="point", espread=1.4, crest="none"),
    "sprout": dict(petals=3, pr=18, bh=16),
    "finling": dict(tail="fan", spine="spikes", spinen=2),
    "hare": dict(ears="long", espread=0.65, crest="none", mouth="smile"),
    "mite": dict(rw=16, rh=13, crest="horn", legpairs=2),
    "wisp": dict(bell=0, tendrils=3, crest="plume", r=16, motes=4),
    "snail": dict(crest="plume", rw=25),
    "fly": dict(ws=42, mood="fierce", motes=3),
    "toad": dict(bw=29, bh=18, mouth="grin", crest="none"),
    "glow": dict(bell=1, tendrils=5, crest="plume", r=19, motes=5),
    "maw": dict(hkind="jaw", spine="sail", tail="whip", crest="none", motes=4),
    "horn": dict(crest="horn", tail="prong", spine="rings", motes=3),
    "majestic": dict(plan="quad", cx=108, cy=78, bw=38, bh=26, hr=20, legh=24, hkind="jaw",
                     ears="small", crest="antler", tail="plume", tsize=30, spine="spikes",
                     spinen=6, mane=1, manen=5, mouth="fang", mood="fierce",
                     wingsides=(-1, 1), wspan=34, aura=2, motes=6, stage=3),
}

# Tidecaller — pressure, current and freeze. Streamlined, finned, buoyant.
_S2 = {
    "canine": dict(tail="fluke", ears="round", hkind="muzzle",
                   st=[dict(), dict(spine="sail", spinen=3), dict(crest="frill", spine="sail",
                                                                  spinen=5, motes=4)]),
    "golem": dict(st=[dict(), dict(crest="cap"), dict(crest="frill", motes=5, float=1)]),
    "lord": dict(crest="crown", st=[dict(crest="cap"), dict(crest="frill"),
                                    dict(crest="crown", motes=4, wspan=28)]),
    "bird": dict(tail="frond", crest="plume", legh=30,
                 st=[dict(), dict(neck=16), dict(neck=26, crest="frill", motes=4)]),
    "saber": dict(crest="none", tail="fluke", ears="round",
                  st=[dict(), dict(manen=5), dict(manen=8, motes=4)]),
    "dragon": dict(crest="frill", hkind="jaw",
                   st=[dict(), dict(ears="point"), dict(motes=5, aura=2, spine="sail")]),
    "shark": dict(tail="fluke", spine="sail", L=46, st=[dict(), dict(crest="frill", motes=4)]),
    "don": dict(ears="round", tail="fluke", st=[dict(), dict(crest="frill", motes=3)]),
    "bear": dict(ears="round", st=[dict(), dict(crest="frill", motes=3)]),
    "fish": dict(tail="fluke", st=[dict(), dict(lure=1, crest="horn", motes=3)]),
    "beetle": dict(crest="frill", rw=29, st=[dict(), dict(crest="horn", motes=4)]),
    "lynx": dict(ears="tuft", tail="frond", st=[dict(), dict(motes=3, mane=1, manen=3)]),
    "plant": dict(petals=6, pr=28, st=[dict(), dict(petals=9, pr=35, motes=4)]),
    "moth": dict(ws=58, motes=3),
    "crab": dict(rw=30, rh=21, crest="none", mouth="grin"),
    "fox": dict(tail="plume", tsize=26, ears="point", espread=1.25),
    "sprout": dict(petals=4, pr=19, bh=15),
    "finling": dict(tail="fluke", spine="none", L=31),
    "hare": dict(ears="long", espread=0.8, crest="cap"),
    "mite": dict(rw=17, rh=13, crest="none", legpairs=3),
    "wisp": dict(bell=0, tendrils=5, crest="frill", r=17, motes=3),
    "snail": dict(crest="frill", rw=26, rh=22),
    "fly": dict(ws=46, mood="calm", motes=3),
    "toad": dict(bw=30, bh=19, crest="frill", mouth="grin"),
    "glow": dict(bell=1, tendrils=8, crest="none", r=22, motes=6),
    "maw": dict(hkind="jaw", spine="sail", tail="fluke", crest="frill", motes=4),
    "horn": dict(crest="horn", tail="fluke", spine="sail", motes=3),
    "majestic": dict(plan="serpent", cx=104, cy=72, k=1.05, hr=17, coils=4, hkind="jaw",
                     crest="frill", ears="point", mouth="fang", mood="fierce",
                     wingsides=(-1, 1), wspan=30, aura=2, motes=6, stage=3),
}


# Verdspire — everything is overgrown. Antlers, fronds, blossoms, bark rings.
_S3 = {
    "canine": dict(tail="frond", ears="tuft", hkind="muzzle",
                   st=[dict(), dict(crest="antler"), dict(crest="antler", spine="spikes",
                                                          spinen=6, motes=5)]),
    "golem": dict(st=[dict(), dict(crest="cap"), dict(crest="antler", motes=6, aura=1)]),
    "lord": dict(crest="cap", st=[dict(crest="cap"), dict(crest="crown"),
                                  dict(crest="antler", motes=5, wspan=32)]),
    "bird": dict(tail="frond", crest="cap", legh=30,
                 st=[dict(), dict(neck=14), dict(neck=24, crest="antler", motes=5)]),
    "saber": dict(crest="none", tail="frond", ears="tuft",
                  st=[dict(), dict(manen=5), dict(manen=9, motes=5)]),
    "dragon": dict(crest="antler", hkind="jaw",
                   st=[dict(), dict(spine="spikes"), dict(motes=6, aura=2, spine="sail")]),
    "shark": dict(tail="frond", spine="spikes", st=[dict(), dict(crest="antler", motes=4)]),
    "don": dict(ears="tuft", tail="frond", st=[dict(), dict(crest="cap", motes=4, aura=1)]),
    "bear": dict(ears="round", st=[dict(), dict(crest="antler", motes=4)]),
    "fish": dict(tail="frond", st=[dict(), dict(crest="cap", lure=1, motes=3)]),
    "beetle": dict(crest="antler", st=[dict(), dict(crest="antler", rw=32, motes=5, aura=1)]),
    "lynx": dict(ears="tuft", tail="frond", st=[dict(), dict(motes=4, mane=1, manen=4)]),
    "plant": dict(petals=7, pr=30, armlift=0.15, st=[dict(), dict(petals=11, pr=38, motes=6, aura=1)]),
    "moth": dict(ws=64, motes=5),
    "crab": dict(rw=28, rh=21, crest="cap", mouth="grin"),
    "fox": dict(tail="frond", tsize=28, ears="tuft", espread=1.2),
    "sprout": dict(petals=5, pr=21, bh=19, armlift=0.4),
    "finling": dict(tail="frond", spine="spikes", spinen=3, L=32),
    "hare": dict(ears="long", espread=0.75, crest="cap"),
    "mite": dict(rw=18, rh=14, crest="cap", legpairs=3),
    "wisp": dict(bell=0, tendrils=6, crest="cap", r=18, motes=5),
    "snail": dict(crest="cap", rw=25, rh=21),
    "fly": dict(ws=44, mood="calm", motes=4),
    "toad": dict(bw=29, bh=19, crest="cap", mouth="grin"),
    "glow": dict(bell=1, tendrils=6, crest="cap", r=20, motes=6),
    "maw": dict(hkind="jaw", spine="spikes", tail="frond", crest="antler", legh=10, motes=5),
    "horn": dict(crest="antler", tail="frond", spine="spikes", motes=4),
    "majestic": dict(plan="plant", cx=108, cy=104, bw=24, bh=40, petals=13, pr=44, armlift=0.5,
                     aura=2, motes=7, mood="fierce", mouth="fang"),
}

# Voltcrest — charge routed through machined plate. Prongs, coils, visors, rivets.
_S4 = {
    "canine": dict(tail="prong", ears="point", espread=1.2, hkind="muzzle",
                   st=[dict(), dict(spine="coil"), dict(crest="horn", spine="coil", motes=5)]),
    "golem": dict(st=[dict(), dict(crest="cap"), dict(crest="crown", motes=6, float=1, aura=1)]),
    "lord": dict(crest="crown", st=[dict(crest="cap"), dict(crest="horn"),
                                    dict(crest="crown", motes=6, wspan=32, aura=2)]),
    "bird": dict(tail="prong", crest="horn", legh=28,
                 st=[dict(), dict(neck=13), dict(neck=22, crest="crown", motes=5)]),
    "saber": dict(crest="none", tail="prong", ears="point", espread=0.9,
                  st=[dict(), dict(manen=5), dict(manen=8, spine="coil", motes=5)]),
    "dragon": dict(crest="horn", hkind="jaw",
                   st=[dict(), dict(spine="coil"), dict(motes=6, aura=2, spine="coil")]),
    "shark": dict(tail="prong", spine="coil", st=[dict(), dict(crest="horn", motes=4)]),
    "don": dict(ears="point", tail="prong", st=[dict(), dict(crest="crown", motes=4)]),
    "bear": dict(ears="round", st=[dict(), dict(crest="horn", motes=4)]),
    "fish": dict(tail="prong", st=[dict(), dict(lure=1, crest="horn", motes=4)]),
    "beetle": dict(crest="horn", st=[dict(), dict(crest="horn", rw=32, motes=5, aura=1)]),
    "lynx": dict(ears="point", espread=1.3, tail="prong", st=[dict(), dict(motes=4, mane=1, manen=4)]),
    "plant": dict(petals=6, pr=29, st=[dict(), dict(petals=9, pr=36, motes=5, aura=1)]),
    "moth": dict(ws=56, motes=5),
    "crab": dict(rw=29, rh=20, crest="horn", mouth="grin"),
    "fox": dict(tail="prong", tsize=26, ears="point", espread=1.5),
    "sprout": dict(petals=4, pr=20, bh=17),
    "finling": dict(tail="prong", spine="coil", spinen=3, L=31),
    "hare": dict(ears="long", espread=0.9, crest="horn"),
    "mite": dict(rw=17, rh=13, crest="horn", legpairs=3),
    "wisp": dict(bell=0, tendrils=4, crest="horn", r=17, motes=5),
    "snail": dict(crest="horn", rw=26, rh=20),
    "fly": dict(ws=48, mood="fierce", motes=5),
    "toad": dict(bw=30, bh=18, crest="horn", mouth="grin"),
    "glow": dict(bell=1, tendrils=5, crest="horn", r=21, motes=6),
    "maw": dict(hkind="jaw", spine="coil", tail="prong", crest="horn", motes=5),
    "horn": dict(crest="horn", tail="prong", spine="coil", motes=4),
    "majestic": dict(plan="construct", cx=108, cy=76, bw=30, bh=28, crest="crown", float=1,
                     mouth="fang", mood="fierce", aura=2, motes=7, stage=3),
}


# Umbral Reach — every body is a hole cut in the sky. Haloes, comet trails,
# constellation stitching and pieces that broke off and never fell.
_S5 = {
    "canine": dict(tail="comet", ears="point", espread=1.2, hkind="muzzle", aura=1,
                   st=[dict(motes=3), dict(crest="horn", spine="rings", motes=5),
                       dict(crest="horn", spine="rings", spinen=6, motes=8, aura=2,
                            wingsides=(-1,), wspan=30)]),
    "golem": dict(float=1, aura=1,
                  st=[dict(motes=4), dict(crest="halo", motes=6),
                      dict(crest="halo", motes=9, aura=2)]),
    "lord": dict(crest="halo", aura=1,
                 st=[dict(crest="halo", motes=4), dict(crest="halo", motes=6, robe=1),
                     dict(crest="halo", motes=10, wspan=34, aura=2, mood="fierce")]),
    "bird": dict(tail="fan", crest="plume", legh=28, aura=1,
                 st=[dict(motes=4), dict(neck=15, motes=6),
                     dict(neck=26, motes=9, wspan=44, aura=2)]),
    "saber": dict(crest="none", tail="plume", tsize=17, aura=1, ears="round", mane=1,
                  st=[dict(manen=4, motes=3), dict(manen=6, motes=5),
                      dict(manen=10, motes=9, spine="spikes", spinen=5, aura=2)]),
    "dragon": dict(crest="halo", hkind="jaw", aura=1,
                   st=[dict(motes=4), dict(spine="rings", motes=6),
                       dict(motes=10, aura=2, spine="rings")]),
    "shark": dict(tail="fluke", spine="spikes", spinen=4, aura=1, st=[dict(motes=4), dict(crest="frill", motes=7, aura=2)]),
    "don": dict(ears="round", tail="brush", tsize=18, aura=1, st=[dict(motes=4), dict(crest="crown", motes=7, aura=2)]),
    "bear": dict(ears="round", aura=1, st=[dict(motes=4), dict(crest="halo", motes=7, aura=2)]),
    "fish": dict(tail="fan", aura=1, st=[dict(motes=4), dict(lure=1, crest="frill", motes=7)]),
    "beetle": dict(crest="halo", aura=1, st=[dict(motes=4), dict(rw=32, motes=8, aura=2)]),
    "lynx": dict(ears="tuft", tail="whip", tsize=20, aura=1, st=[dict(motes=4), dict(motes=7, crest="antler")]),
    "plant": dict(petals=6, pr=30, aura=1, st=[dict(motes=5), dict(petals=10, pr=38, motes=9, aura=2)]),
    "moth": dict(ws=66, motes=7, aura=1),
    "crab": dict(rw=29, rh=21, crest="horn", mouth="void", motes=5, aura=1),
    "fox": dict(tail="fan", tsize=30, ears="long", espread=1.3, motes=5, aura=1),
    "sprout": dict(petals=4, pr=21, bh=17, motes=4, aura=1),
    "finling": dict(tail="fluke", spine="rings", spinen=3, L=32, motes=4, aura=1),
    "hare": dict(ears="long", espread=0.85, crest="none", tail="comet", motes=5, aura=1),
    "mite": dict(rw=18, rh=14, crest="plume", legpairs=3, motes=4, aura=1),
    "wisp": dict(bell=0, tendrils=5, crest="halo", r=18, motes=7, aura=2),
    "snail": dict(crest="plume", rw=26, rh=21, motes=5, aura=1),
    "fly": dict(ws=50, mood="fierce", motes=6, aura=1),
    "toad": dict(bw=30, bh=19, crest="antler", mouth="void", motes=5, aura=1),
    "glow": dict(bell=1, tendrils=7, crest="halo", r=22, motes=8, aura=2),
    "maw": dict(hkind="jaw", spine="spikes", spinen=6, tail="prong", crest="none", motes=7, aura=2),
    "horn": dict(crest="horn", tail="whip", spine="rings", motes=6, aura=2),
    "majestic": dict(plan="float", cx=108, cy=68, r=26, bell=0, tendrils=7, crest="halo",
                     mouth="void", mood="fierce", aura=2, motes=10, stage=3),
}

SET_OVR = {}
for _n, _t in ((1, _S1), (2, _S2), (3, _S3), (4, _S4), (5, _S5)):
    for _slot, _o in _t.items():
        SET_OVR[(_n, _slot)] = _o


def resolve(setno, slot, stage, sc):
    """Merge slot family -> stage growth -> set re-imagining -> set stage growth."""
    fam = SLOT_BASE[slot]
    plan = fam["plan"]
    p = dict(fam["base"])
    fst = fam.get("st")
    if fst:
        p.update(fst[min(stage - 1, len(fst) - 1)])
    o = SET_OVR.get((setno, slot))
    if o:
        plan = o.get("plan", plan)
        p.update({k: v for k, v in o.items() if k not in ("plan", "st")})
        ost = o.get("st")
        if ost:
            p.update(ost[min(stage - 1, len(ost) - 1)])
    p.setdefault("stage", stage)
    p["sc"] = sc
    return plan, p


# =================================================================================
# LEGENDARIES — one bespoke drawing each.
# =================================================================================


def l_emberyx(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_glaciera(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_eldwyrm(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_voltaeon(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_ignarok(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_solmyr(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_abyssos(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_maelstros(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_sylvareth(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_floreon(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_fulguros(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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


def l_tempesta(ctx):
    uid, e, var = ctx.uid, ctx.e, ctx.var
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



# --- Umbral Reach ultras: the payoff cards. Built from scratch, not from a plan.
def voidfill(ctx, d, bx, by, bw, bh, count=26, seed=0, neb=".45", rimw=1.6):
    """Turn a silhouette into a window onto deep space."""
    cid = ctx.nid("cl")
    ctx.defs.append(f'<clipPath id="{cid}"><path d="{d}"/></clipPath>')
    g = f'<path d="{d}" fill="url(#void{ctx.uid})"/>'
    g += (f'<g clip-path="url(#{cid})"><path d="{d}" fill="{ctx.sty["neb"]}" opacity="{neb}"/>'
          + starfield(bx, by, bw, bh, ctx.var["seed"] + seed, count=count, tint=ctx.sty["star"]) + "</g>")
    g += f'<path d="{d}" fill="none" stroke="url(#rim{ctx.uid})" stroke-width="{rimw}" opacity=".95"/>'
    return g


def _corona(cx, cy, r, glow, spokes=28, inner=1.0, outer=1.42, w=1.3, op=.5):
    g = ""
    for k in range(spokes):
        a = k * 2 * math.pi / spokes
        ln = outer if k % 2 == 0 else outer - 0.16
        g += (f'<line x1="{cx + math.cos(a) * r * inner:.1f}" y1="{cy + math.sin(a) * r * inner:.1f}" '
              f'x2="{cx + math.cos(a) * r * ln:.1f}" y2="{cy + math.sin(a) * r * ln:.1f}" '
              f'stroke="{glow}" stroke-width="{w}" opacity="{op}" stroke-linecap="round"/>')
    return g


def l_nyxaros(ctx):
    """Nyxaros, the Unlit Star — a void lion prowling out of a dead sun."""
    uid, sty, glow = ctx.uid, ctx.sty, ctx.glow
    g = '<g>'
    g += f'<ellipse cx="112" cy="80" rx="102" ry="64" fill="url(#halo{uid})" opacity=".4"/>'
    g += _corona(150, 54, 33, glow, 40, 1.02, 1.55, 1.3, .4)
    g += f'<circle cx="150" cy="54" r="33" fill="#040110" stroke="{glow}" stroke-width="2.6"/>'
    g += f'<circle cx="150" cy="54" r="33" fill="none" stroke="{sty["rift"]}" stroke-width="1" opacity=".75"/>'
    g += star(176, 33, 5.4, "#ffffff", .98)
    g += f'<ellipse cx="102" cy="137" rx="62" ry="7" fill="#000" opacity=".4"/>'
    tail = ("M132,98 C164,96 188,80 200,52 C200,86 178,110 142,116 Z")
    g += voidfill(ctx, tail, 130, 50, 74, 68, 14, 3)
    g += star(198, 50, 4.4, "#ffffff", .95)
    for (lx, ly, sw, lean) in ((118, 106, 11, 5), (68, 104, 10, -4)):
        d = (f"M{lx - sw:.1f},{ly:.1f} L{lx + sw:.1f},{ly:.1f} L{lx + sw * 0.5 + lean:.1f},134 "
             f"L{lx - sw * 0.5 + lean:.1f},134 Z")
        g += voidfill(ctx, d, lx - sw, ly, sw * 2, 34, 5, int(lx))
    body = ("M44,102 C40,80 60,66 88,66 C116,66 136,78 138,98 C140,118 118,130 90,130 "
            "C62,130 48,120 44,102 Z")
    g += voidfill(ctx, body, 42, 64, 98, 68, 30, 7)
    for (lx, ly, sw, lean) in ((104, 108, 10, 4), (56, 106, 9, -5),):
        d = (f"M{lx - sw:.1f},{ly:.1f} L{lx + sw:.1f},{ly:.1f} L{lx + sw * 0.55 + lean:.1f},135 "
             f"L{lx - sw * 0.55 + lean:.1f},135 Z")
        g += voidfill(ctx, d, lx - sw, ly, sw * 2, 34, 5, int(lx) + 40)
        g += star(lx + lean, 137, 2.4, sty["star"], .9)
    hx, hy, hr = 52, 68, 23
    for i in range(13):
        a = math.pi * (0.42 + 1.22 * i / 12)
        px, py = hx - math.cos(a - 1.57) * hr * 1.5, hy - math.sin(a - 1.57) * hr * 1.5
        sz = 9 - abs(i - 6) * 0.5
        d = (f"M{px:.1f},{py - sz:.1f} L{px + sz * 0.5:.1f},{py:.1f} L{px:.1f},{py + sz:.1f} "
             f"L{px - sz * 0.5:.1f},{py:.1f} Z")
        rot = math.degrees(a) + 90
        g += (f'<g transform="rotate({rot:.0f} {px:.1f} {py:.1f})"><path d="{d}" fill="#1b0c38" '
              f'stroke="url(#rim{uid})" stroke-width="1.2"/></g>')
        if i % 2 == 0:
            g += star(px, py, 2.2, sty["star"], .95)
    head = ("M30,72 C28,56 42,45 58,45 C74,45 84,56 83,70 C82,86 68,95 54,93 "
            "C40,91 31,84 30,72 Z")
    g += voidfill(ctx, head, 28, 44, 58, 52, 16, 11)
    g += (f'<path d="M36,50 L27,26 L52,42 Z M70,44 L84,23 L84,50 Z" fill="#1b0c38" '
          f'stroke="url(#rim{uid})" stroke-width="1.5"/>')
    g += star(31, 30, 2.6, sty["star"], .95) + star(82, 28, 2.4, sty["star"], .95)
    g += f'<path d="M34,80 q16,12 34,5 q-12,13 -27,6 Z" fill="#050214" stroke="{glow}" stroke-width="1.2"/>'
    g += f'<path d="M40,82 l3,7 4,-6 M53,86 l2,7 5,-6" stroke="#fff" stroke-width="1.3" fill="none"/>'
    for (ex, ey) in ((44, 66), (66, 62)):
        g += f'<circle cx="{ex}" cy="{ey}" r="7.5" fill="url(#halo{uid})"/>'
        g += f'<circle cx="{ex}" cy="{ey}" r="4" fill="{sty["star"]}"/>'
        g += star(ex, ey, 5.4, "#ffffff", 1)
    for (ox, oy, sz) in [(20, 120, 5), (186, 122, 5.6), (204, 92, 4), (16, 46, 4.2), (104, 22, 3.6)]:
        d = sharp_poly(ring(ox, oy, sz, sz * 0.8, 5, int(ox * 7 + oy), 0.3))
        g += f'<path d="{d}" fill="#1b0c38" stroke="url(#rim{uid})" stroke-width="1.2"/>'
        g += star(ox, oy, sz * 0.45, sty["star"], .9)
    return g + '</g>'


def l_astralon(ctx):
    """Astralon, the Constellation Leviathan — a whale-shaped hole full of stars."""
    uid, sty, glow = ctx.uid, ctx.sty, ctx.glow
    g = '<g>'
    g += f'<ellipse cx="104" cy="72" rx="104" ry="60" fill="url(#halo{uid})" opacity=".5"/>'
    for i, (rx, ry, rot, op) in enumerate([(96, 30, -16, .5), (80, 22, 22, .35), (104, 42, 6, .22)]):
        g += (f'<ellipse cx="104" cy="74" rx="{rx}" ry="{ry}" fill="none" stroke="{sty["rift"] if i else glow}" '
              f'stroke-width="{1.6 - i * 0.35:.1f}" opacity="{op}" transform="rotate({rot} 104 74)"/>')
    fin_up = "M112,46 C118,16 140,2 168,4 C146,18 136,34 132,52 Z"
    fin_dn = "M96,102 C86,124 66,138 42,140 C62,124 72,110 76,94 Z"
    g += voidfill(ctx, fin_up, 110, 2, 60, 52, 12, 21, neb=".55")
    g += voidfill(ctx, fin_dn, 40, 92, 58, 50, 12, 27, neb=".55")
    body = ("M16,84 C22,60 50,44 84,46 C120,48 150,62 176,84 C158,96 140,102 118,104 "
            "C96,106 70,104 48,98 C34,94 22,90 16,84 Z")
    g += voidfill(ctx, body, 12, 42, 168, 66, 54, 33, neb=".4", rimw=1.9)
    fluke = "M176,84 C192,66 206,58 214,58 C206,72 204,84 208,98 C198,96 186,92 176,84 Z"
    g += voidfill(ctx, fluke, 174, 56, 44, 46, 10, 39)
    nodes = [(40, 84), (62, 70), (88, 62), (116, 64), (142, 74), (164, 84)]
    g += f'<g stroke="{glow}" stroke-width="1.1" opacity=".85">'
    for i in range(len(nodes) - 1):
        g += f'<line x1="{nodes[i][0]}" y1="{nodes[i][1]}" x2="{nodes[i + 1][0]}" y2="{nodes[i + 1][1]}"/>'
    g += f'<line x1="88" y1="62" x2="96" y2="40"/><line x1="116" y1="64" x2="126" y2="90"/></g>'
    for (nx, ny) in nodes + [(96, 40), (126, 90)]:
        g += star(nx, ny, 2.8, sty["star"], .95)
    g += (f'<path d="M18,86 C34,96 62,102 92,102" fill="none" stroke="{sty["rift"]}" stroke-width="2" opacity=".7"/>')
    for i in range(7):
        px = 26 + i * 11
        g += f'<line x1="{px}" y1="{92 + i * 0.6:.0f}" x2="{px + 3}" y2="{100 + i * 0.4:.0f}" stroke="{glow}" stroke-width="1" opacity=".55"/>'
    g += f'<circle cx="40" cy="72" r="9" fill="url(#halo{uid})"/>'
    g += star(40, 72, 5.4, "#ffffff", 1)
    g += f'<circle cx="40" cy="72" r="10" fill="none" stroke="{glow}" stroke-width="1.2" opacity=".9"/>'
    for (ox, oy, s) in [(196, 30, 5), (14, 34, 4.4), (190, 122, 5), (60, 130, 4), (108, 14, 3.6)]:
        d = sharp_poly(ring(ox, oy, s, s * 0.76, 5, int(ox * 5 + oy), 0.3))
        g += f'<path d="{d}" fill="url(#void{uid})" stroke="url(#rim{uid})" stroke-width="1.2"/>'
        g += star(ox, oy, s * 0.4, sty["star"], .9)
    return g + '</g>'


def l_eclipsar(ctx):
    """Eclipsar, the Eclipse Made Flesh — wings of night around a ring of fire."""
    uid, sty, glow = ctx.uid, ctx.sty, ctx.glow
    g = '<g>'
    g += _corona(108, 60, 36, glow, 40, 1.0, 1.62, 1.5, .42)
    g += f'<circle cx="108" cy="60" r="37" fill="none" stroke="#fff2c8" stroke-width="3.4" opacity=".95"/>'
    g += f'<circle cx="108" cy="60" r="36" fill="#05020f"/>'
    g += f'<circle cx="132" cy="38" r="6.5" fill="#ffffff" opacity=".95"/>'
    g += star(132, 38, 11, "#ffffff", .9)
    for sgn in (-1, 1):
        w = (f"M108,66 C{108 + sgn * 34},18 {108 + sgn * 84},12 {108 + sgn * 108},34 "
             f"C{108 + sgn * 92},36 {108 + sgn * 80},44 {108 + sgn * 74},54 "
             f"C{108 + sgn * 96},52 {108 + sgn * 106},60 {108 + sgn * 104},74 "
             f"C{108 + sgn * 80},62 {108 + sgn * 52},68 {108 + sgn * 30},88 Z")
        g += voidfill(ctx, w, 108 - 110 if sgn < 0 else 108, 10, 112, 84, 26, 51 + sgn, neb=".5")
        nodes = [(108 + sgn * 30, 56), (108 + sgn * 58, 38), (108 + sgn * 86, 30), (108 + sgn * 78, 54)]
        g += f'<g stroke="{glow}" stroke-width="1" opacity=".8">'
        for i in range(len(nodes) - 1):
            g += f'<line x1="{nodes[i][0]}" y1="{nodes[i][1]}" x2="{nodes[i + 1][0]}" y2="{nodes[i + 1][1]}"/>'
        g += "</g>"
        for (nx, ny) in nodes:
            g += star(nx, ny, 2.4, sty["star"], .95)
    body = ("M108,52 C122,52 130,70 126,96 C124,114 116,128 108,140 C100,128 92,114 90,96 "
            "C86,70 94,52 108,52 Z")
    g += voidfill(ctx, body, 86, 48, 44, 94, 22, 63, neb=".35", rimw=1.8)
    g += f'<circle cx="108" cy="92" r="9" fill="url(#halo{uid})"/>'
    g += star(108, 92, 6.5, "#ffffff", 1)
    for sgn in (-1, 1):
        g += (f'<path d="M108,64 C{108 + sgn * 22},70 {108 + sgn * 30},86 {108 + sgn * 26},104" fill="none" '
              f'stroke="{sty["rift"]}" stroke-width="1.6" opacity=".75"/>')
    head = "M108,26 C120,26 127,36 125,48 C123,58 116,63 108,63 C100,63 93,58 91,48 C89,36 96,26 108,26 Z"
    g += voidfill(ctx, head, 89, 24, 38, 42, 12, 71, neb=".3")
    g += f'<path d="M92,34 L84,10 L102,28 Z M124,34 L132,10 L114,28 Z M108,24 L108,4 L114,22 Z" fill="url(#void{uid})" stroke="url(#rim{uid})" stroke-width="1.4"/>'
    for (sx, sy) in ((85, 12), (133, 12), (109, 6)):
        g += star(sx, sy, 2.6, sty["star"], .95)
    for ex, dx in ((101, -1), (115, 1)):
        g += f'<circle cx="{ex}" cy="46" r="5.5" fill="url(#halo{uid})"/>'
        g += star(ex, 46, 3.8, "#ffffff", 1)
    g += f'<ellipse cx="108" cy="58" rx="46" ry="12" fill="none" stroke="{glow}" stroke-width="1.6" opacity=".65" transform="rotate(-14 108 58)"/>'
    g += f'<ellipse cx="108" cy="64" rx="58" ry="16" fill="none" stroke="{sty["rift"]}" stroke-width="1.1" opacity=".45" transform="rotate(12 108 64)"/>'
    for (ox, oy, s) in [(28, 108, 5.5), (188, 104, 5), (14, 66, 4), (200, 62, 4.4), (60, 132, 4), (156, 130, 4.6)]:
        d = sharp_poly(ring(ox, oy, s, s * 0.78, 5, int(ox * 3 + oy), 0.3))
        g += f'<path d="{d}" fill="url(#void{uid})" stroke="url(#rim{uid})" stroke-width="1.2"/>'
        g += star(ox, oy, s * 0.42, sty["star"], .92)
    return g + '</g>'


LEG = {
    "Emberyx": l_emberyx, "Ignarok": l_ignarok, "Solmyr": l_solmyr,
    "Glaciera": l_glaciera, "Abyssos": l_abyssos, "Maelstros": l_maelstros,
    "Eldwyrm": l_eldwyrm, "Sylvareth": l_sylvareth, "Floreon": l_floreon,
    "Voltaeon": l_voltaeon, "Fulguros": l_fulguros, "Tempesta": l_tempesta,
    "Nyxaros": l_nyxaros, "Astralon": l_astralon, "Eclipsar": l_eclipsar,
}


# =================================================================================
# COMPOSITION
# =================================================================================
with open(os.path.join(ROOT, "data", "cards.json")) as f:
    CARDS = json.load(f)


def creature(ctx, role):
    if role["leg"]:
        return LEG[role["leg"]](ctx)
    plan, p = resolve(role["set"], role["slot"], role["stage"], role["sc"])
    return PLANS[plan](ctx, p)


def art_inner(card):
    e = ELE[card["element"]]
    uid = card["id"].replace("-", "_")
    role = ROLES[card["name"]]
    ctx = Ctx(uid, e, card["set"], vary(card["name"]), card["name"])
    body = creature(ctx, role)
    return defs(ctx) + SCENES[card["set"]](uid) + body


def art_svg(card):
    return f'<svg viewBox="0 0 {VB_W} {VB_H}" xmlns="http://www.w3.org/2000/svg">{art_inner(card)}</svg>'


def _xml(s):
    return s.replace("&", "&amp;").replace("<", "&lt;")


# ------------------------------------------------------------------ duplicate check
def design_key(card):
    """Geometry fingerprint with palette and elemental accents neutralised, so two
    cards only collide when they are genuinely the same character design."""
    import re
    global tuft, spots, star
    real = (tuft, spots, star)
    tuft = lambda *a, **k: "<TUFT/>"
    spots = lambda *a, **k: "<SPOTS/>"
    star = lambda *a, **k: "<STAR/>"
    try:
        e = ELE[card["element"]]
        uid = card["id"].replace("-", "_")
        role = ROLES[card["name"]]
        ctx = Ctx(uid, e, card["set"], vary(card["name"]), card["name"])
        s = creature(ctx, role) + "".join(ctx.defs)
    finally:
        tuft, spots, star = real
    s = s.replace(uid, "U")
    s = re.sub(r'(fill|stroke|stop-color)="[^"]*"', r'\1="X"', s)
    s = re.sub(r'\s(opacity|fill-opacity|stroke-opacity|stop-opacity)="[^"]*"', "", s)
    return hashlib.md5(s.encode()).hexdigest()


def dupes():
    seen = {}
    for c in CARDS:
        seen.setdefault(design_key(c), []).append(c)
    clashes = {k: v for k, v in seen.items() if len(v) > 1}
    print(f"{len(seen)} unique designs across {len(CARDS)} cards")
    for v in clashes.values():
        print("  DUPLICATE:", ", ".join(f'{c["name"]} (set {c["set"]})' for c in v))
    if clashes:
        raise SystemExit(f"{sum(len(v) for v in clashes.values())} cards share a design")
    print("OK: every card has its own character design")


# ------------------------------------------------------------------------- outputs
def qa_sheet(setno, out_dir="/tmp"):
    """Contact sheet of all 50 cards in a set."""
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
        role = ROLES[c["name"]]
        tag = role["leg"] or f'{role["slot"]} {role["stage"]}/{role["sc"]}'
        body += f'<g transform="translate({cx},{cy})">'
        body += f'<rect x="-5" y="-5" width="{cw + 10}" height="{ch + 6}" rx="9" fill="#171a22"/>'
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
MOCKART = os.path.join(ROOT, "docs", "mockups", "art")


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
        # Base art window (216x150).
        svg = art_svg(c)
        svg_path = os.path.join(MOCKART, f"{fid}.svg")
        open(svg_path, "w").write(svg)
        iset = os.path.join(CARDART, f"{fid}.imageset")
        os.makedirs(iset, exist_ok=True)
        open(os.path.join(iset, "Contents.json"), "w").write(_contents_json(fid))
        jobs.append((svg_path, os.path.join(iset, f"{fid}.png"), "864", "600"))

        # Extended full-card art (216x302) — the Gauntlet win reward.
        eid = f"{fid}-ext"
        esvg_path = os.path.join(MOCKART, f"{eid}.svg")
        open(esvg_path, "w").write(ext_art_svg(c))
        eiset = os.path.join(CARDART, f"{eid}.imageset")
        os.makedirs(eiset, exist_ok=True)
        open(os.path.join(eiset, "Contents.json"), "w").write(_contents_json(eid))
        jobs.append((esvg_path, os.path.join(eiset, f"{eid}.png"), "864", "1208"))

    def render_one(job):
        svg_path, png, w, h = job
        subprocess.run(["rsvg-convert", "-w", w, "-h", h, svg_path, "-o", png],
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
    elif cmd == "dupes":
        dupes()
    else:
        print("usage: generate_art.py [assets | qa [setno] | dupes]")
