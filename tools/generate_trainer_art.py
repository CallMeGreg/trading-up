#!/usr/bin/env python3
"""Trainer emblems — six bespoke flat-vector badges for the Gauntlet roster.

Same stdlib-only SVG -> ``rsvg-convert`` pipeline as ``generate_art.py``: one
emblem per Trainer, drawn in that Trainer's signature colour and a motif that
reads its strategic lane, in the app's flat/gradient look. Nothing here is
third-party art — no licence, no attribution, no dependency, in keeping with the
project's all-procedural-art ethos.

Every emblem is a self-contained badge (dark-violet plate + signature-colour glow
and ring + bold motif) on a transparent background, so it drops onto a Trainer
card as an avatar. The in-app card supplies the name, so the app assets carry no
text; the docs contact sheet adds name + role labels for review.

Commands (needs ``rsvg-convert`` from librsvg: ``brew install librsvg``):
  python3 tools/generate_trainer_art.py assets   # (re)render the 6 app emblems
  python3 tools/generate_trainer_art.py sheet     # labelled contact sheet for docs
  python3 tools/generate_trainer_art.py all        # both (default)

Outputs:
  - app assets  TradingUp/Assets.xcassets/TrainerArt/trainer-<id>.imageset/*.png (400x400)
  - mockup SVGs docs/mockups/trainers/<name>.svg
  - contact     docs/mockups/trainers/trainers_contact.png
The app (TrainerCard) shows these via UIImage(named: "trainer-<id>").
"""
import json, os, sys, math, subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRAINERART = os.path.join(ROOT, "TradingUp", "Assets.xcassets", "TrainerArt")
MOCK = os.path.join(ROOT, "docs", "mockups", "trainers")

# id is the persistence + asset key (Fred keeps the legacy id "appraiser").
# (id, display name, role tag, signature colour, deep shade)
TRAINERS = [
    ("ripper",    "Jack the Ripper",   "Tempo",         "#ff6b9d", "#7a1f45"),
    ("curator",   "Curator Curtis",    "Build width",   "#9b6cf7", "#3d2778"),
    ("appraiser", "Fred the Farmer",   "Value",         "#74d680", "#1f6b34"),
    ("grader",    "Lucky Lucy",        "Grading",       "#ffd54a", "#7a5a10"),
    ("merchant",  "Sally the Seller",  "Economy",       "#ff9f43", "#7a441a"),
    ("neutral",   "Average Joe",       "Neutral start", "#8a94a6", "#3a4150"),
    ("red",       "Ash",               "???",           "#ff3b3b", "#5a1417"),
]


# --------------------------------------------------------------------- plate
def defs(uid, c):
    """Shared gradients/glow for one emblem, id-suffixed so many can composite."""
    return f'''
  <linearGradient id="bg{uid}" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="#231240"/><stop offset="100%" stop-color="#0b0e14"/>
  </linearGradient>
  <radialGradient id="glow{uid}" cx="50%" cy="34%" r="55%">
    <stop offset="0%" stop-color="{c}" stop-opacity="0.36"/>
    <stop offset="100%" stop-color="{c}" stop-opacity="0"/>
  </radialGradient>
  <linearGradient id="mot{uid}" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="{c}"/><stop offset="100%" stop-color="{c}" stop-opacity="0.72"/>
  </linearGradient>'''


def plate(uid, c, box):
    """Circular badge plate + signature rim and top glow filling the whole square
    box. The app crops the emblem to a circle of the same radius and seats it inside
    a circular difficulty ring, so the plate is a full disc edge-to-edge — a rounded
    square would leave dead corners and flat sides inside that ring. The signature
    rim is drawn just inside the edge so it renders cleanly rather than being clipped."""
    r = box / 2
    return f'''
  <circle cx="{r:.0f}" cy="{r:.0f}" r="{r:.0f}" fill="url(#bg{uid})"/>
  <circle cx="{r:.0f}" cy="{r:.0f}" r="{r:.0f}" fill="url(#glow{uid})"/>
  <circle cx="{r:.0f}" cy="{r:.0f}" r="{r - 2:.0f}" fill="none"
          stroke="{c}" stroke-opacity="0.32" stroke-width="2"/>
  <circle cx="{box/2:.0f}" cy="{box*0.46:.0f}" r="{box*0.30:.0f}" fill="{c}" fill-opacity="0.10"/>'''


# ---------------------------------------------------------- motifs (origin 0,0)
def m_ripper(uid, c, d):
    # a foil pack torn open by a bright bolt, framed by two speed slashes
    return f'''
    <rect x="-34" y="-56" width="68" height="112" rx="10" fill="url(#mot{uid})"/>
    <path d="M-34,-44 l9,-7 l9,7 l9,-7 l9,7 l9,-7 l9,7 l5,-3 v-9 h-77 z" fill="{d}"/>
    <rect x="-34" y="-56" width="68" height="14" rx="7" fill="{c}"/>
    <path d="M-5,-58 L-20,4 L-3,4 L-15,58 L27,-13 L5,-13 L19,-58 Z"
          fill="#fff3c4" stroke="#ffffff" stroke-width="2.5" stroke-linejoin="round"/>
    <path d="M-54,-30 q15,10 6,32" stroke="{c}" stroke-width="6" fill="none" stroke-linecap="round" opacity="0.85"/>
    <path d="M54,-30 q-15,10 -6,32" stroke="{c}" stroke-width="6" fill="none" stroke-linecap="round" opacity="0.85"/>'''


def m_curator(uid, c, d):
    # an ornate showcase frame cradling a bright gem
    return f'''
    <rect x="-58" y="-58" width="116" height="116" rx="14" fill="none" stroke="url(#mot{uid})" stroke-width="15"/>
    <rect x="-39" y="-39" width="78" height="78" rx="8" fill="none" stroke="{d}" stroke-width="4"/>
    <circle cx="-58" cy="-58" r="8" fill="{c}"/><circle cx="58" cy="-58" r="8" fill="{c}"/>
    <circle cx="-58" cy="58" r="8" fill="{c}"/><circle cx="58" cy="58" r="8" fill="{c}"/>
    <path d="M0,-27 L23,-4 L0,33 L-23,-4 Z" fill="#ffffff" fill-opacity="0.95"/>
    <path d="M0,-27 L23,-4 L0,33 Z" fill="{c}"/>
    <path d="M0,-27 L-23,-4 L0,-11 L23,-4 Z" fill="{c}" fill-opacity="0.55"/>'''


def m_farmer(uid, c, d):
    # a sun rising behind a bound wheat sheaf
    rays = "".join(
        f'<line x1="{58*math.cos(a):.1f}" y1="{-8+58*math.sin(a):.1f}" '
        f'x2="{78*math.cos(a):.1f}" y2="{-8+78*math.sin(a):.1f}" '
        f'stroke="{c}" stroke-width="5" stroke-linecap="round" opacity="0.5"/>'
        for a in (math.radians(x) for x in range(198, 343, 18)))

    def ear(dx, rot):
        grains = "".join(
            f'<path d="M0,{y} q11,-5 3,-17 q-11,3 -3,17 Z" fill="url(#mot{uid})"/>'
            f'<path d="M0,{y} q-11,-5 -3,-17 q11,3 3,17 Z" fill="{c}"/>' for y in (-16, 2, 20))
        return (f'<g transform="translate({dx},0) rotate({rot})">'
                f'<line x1="0" y1="60" x2="0" y2="-26" stroke="{d}" stroke-width="6" stroke-linecap="round"/>'
                f'{grains}<path d="M-9,-26 q9,-16 9,-32 q0,16 9,32 Z" fill="{c}"/></g>')

    return f'''
    <circle cx="0" cy="-8" r="34" fill="{c}" fill-opacity="0.22"/>
    {rays}
    {ear(-27,-17)}{ear(27,17)}{ear(0,0)}
    <path d="M-22,44 q22,10 44,0 l-4,14 q-18,7 -36,0 Z" fill="{d}"/>'''


def m_grader(uid, c, d):
    # a graded slab under a magnifier, a sparkle caught in the lens
    return f'''
    <g transform="rotate(-12)">
      <rect x="-58" y="-48" width="72" height="100" rx="10" fill="{d}"/>
      <rect x="-46" y="-54" width="48" height="21" rx="6" fill="{c}"/>
    </g>
    <line x1="34" y1="34" x2="66" y2="66" stroke="{d}" stroke-width="15" stroke-linecap="round"/>
    <circle cx="13" cy="11" r="41" fill="#0b0e14" fill-opacity="0.62" stroke="url(#mot{uid})" stroke-width="13"/>
    <circle cx="13" cy="11" r="41" fill="none" stroke="#ffffff" stroke-opacity="0.25" stroke-width="2"/>
    <path d="M2,2 l6,11 l11,6 l-11,6 l-6,11 l-6,-11 l-11,-6 l11,-6 Z" fill="#ffffff"/>'''


def m_merchant(uid, c, d):
    # a stack of coins with a dollar face and a sparkle
    coin = lambda cy: f'<ellipse cx="0" cy="{cy}" rx="47" ry="16" fill="url(#mot{uid})" stroke="{d}" stroke-width="3"/>'
    return f'''
    <rect x="-47" y="-9" width="94" height="36" fill="url(#mot{uid})"/>
    {coin(27)}{coin(9)}{coin(-9)}
    <ellipse cx="0" cy="-9" rx="47" ry="16" fill="{c}"/>
    <ellipse cx="0" cy="-9" rx="35" ry="10" fill="{d}" fill-opacity="0.5"/>
    <text x="0" y="1" text-anchor="middle" font-family="Arial, sans-serif" font-size="30"
          font-weight="900" fill="#ffffff">$</text>
    <path d="M42,-46 l4,11 l11,4 l-11,4 l-4,11 l-4,-11 l-11,-4 l11,-4 Z" fill="{c}"/>'''


def m_rookie(uid, c, d):
    # a humble shield badge with a single star — the free starter
    return f'''
    <path d="M0,-60 L56,-39 V6 Q56,46 0,66 Q-56,46 -56,6 V-39 Z" fill="url(#mot{uid})" stroke="{d}" stroke-width="4"/>
    <path d="M0,-47 L43,-31 V4 Q43,35 0,52 Q-43,35 -43,4 V-31 Z" fill="#0b0e14" fill-opacity="0.34"/>
    <path d="M0,-31 l10,20 l23,3 l-16,16 l4,22 l-21,-11 l-21,11 l4,-22 l-16,-16 l23,-3 Z" fill="#ffffff"/>'''


def m_red(uid, c, d):
    # the mystery rival, revealed as a champion: a trophy cup with side handles, a
    # pedestal base and the roster's white star on the bowl — same bold flat-vector
    # build as the rest of the badges (signature-colour gradient, deep-shade rim).
    star = ('<path d="M0,-31 l10,20 l23,3 l-16,16 l4,22 l-21,-11 l-21,11 '
            'l4,-22 l-16,-16 l23,-3 Z" transform="translate(0,-10) scale(0.44)"'
            ' fill="#ffffff"/>')
    return f'''
    <path d="M-30,-30 q-24,3 -19,24 q3,13 17,12" fill="none" stroke="url(#mot{uid})"
          stroke-width="8" stroke-linecap="round"/>
    <path d="M30,-30 q24,3 19,24 q-3,13 -17,12" fill="none" stroke="url(#mot{uid})"
          stroke-width="8" stroke-linecap="round"/>
    <rect x="-37" y="-44" width="74" height="11" rx="5.5" fill="url(#mot{uid})" stroke="{d}" stroke-width="3"/>
    <path d="M-32,-33 L32,-33 L26,4 Q19,28 0,30 Q-19,28 -26,4 Z" fill="url(#mot{uid})"
          stroke="{d}" stroke-width="4" stroke-linejoin="round"/>
    <rect x="-6" y="30" width="12" height="13" fill="{d}"/>
    <path d="M-22,58 L22,58 L15,43 L-15,43 Z" fill="url(#mot{uid})" stroke="{d}" stroke-width="3" stroke-linejoin="round"/>
    {star}'''


MOTIF = dict(ripper=m_ripper, curator=m_curator, appraiser=m_farmer,
             grader=m_grader, merchant=m_merchant, neutral=m_rookie, red=m_red)


# --------------------------------------------------------------------- emit
def emblem_svg(tid, c, d, box=200, scale=0.72, cy=0.47):
    """One standalone app emblem (no text) as an SVG string."""
    uid = tid
    motif = MOTIF[tid](uid, c, d)
    return (f'<svg viewBox="0 0 {box} {box}" xmlns="http://www.w3.org/2000/svg">'
            f'<defs>{defs(uid, c)}</defs>{plate(uid, c, box)}'
            f'<g transform="translate({box/2:.0f},{box*cy:.0f}) scale({scale})">{motif}</g></svg>')


def _contents_json(name):
    return json.dumps({
        "images": [{"filename": f"{name}.png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2)


def build_assets():
    os.makedirs(TRAINERART, exist_ok=True)
    os.makedirs(MOCK, exist_ok=True)
    # a plain (non-namespaced) catalog folder, so names resolve globally like CardArt
    open(os.path.join(TRAINERART, "Contents.json"), "w").write(
        json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    for tid, name, _role, c, d in TRAINERS:
        asset = f"trainer-{tid}"
        svg = emblem_svg(tid, c, d)
        # keep a readable SVG mockup next to the docs contact sheet
        open(os.path.join(MOCK, f"{name.lower()}.svg"), "w").write(svg)
        iset = os.path.join(TRAINERART, f"{asset}.imageset")
        os.makedirs(iset, exist_ok=True)
        open(os.path.join(iset, "Contents.json"), "w").write(_contents_json(asset))
        svg_path = os.path.join(MOCK, f"{name.lower()}.svg")
        subprocess.run(["rsvg-convert", "-w", "400", "-h", "400", svg_path,
                        "-o", os.path.join(iset, f"{asset}.png")], check=True)
    print(f"wrote {len(TRAINERS)} emblems -> {TRAINERART}")


def build_sheet():
    os.makedirs(MOCK, exist_ok=True)
    cols = 3
    rows = (len(TRAINERS) + cols - 1) // cols
    W, H, gap = 220, 260, 16
    box = 176
    SW = cols * W + (cols + 1) * gap
    SH = rows * H + (rows + 1) * gap
    parts = [f'<svg viewBox="0 0 {SW} {SH}" xmlns="http://www.w3.org/2000/svg">',
             f'<rect width="{SW}" height="{SH}" fill="#07060d"/>']
    for i, (tid, name, role, c, d) in enumerate(TRAINERS):
        x = gap + (i % cols) * (W + gap)
        y = gap + (i // cols) * (H + gap)
        uid = f"s{i}"
        cx = W / 2
        motif = MOTIF[tid](uid, c, d)
        parts.append(
            f'<g transform="translate({x},{y})"><defs>{defs(uid, c)}</defs>'
            f'<g transform="translate({(W-box)/2:.0f},4)">{plate(uid, c, box)}</g>'
            f'<g transform="translate({cx:.0f},{4+box*0.47:.0f}) scale(0.72)">{motif}</g>'
            f'<text x="{cx:.0f}" y="{box+42:.0f}" text-anchor="middle" '
            f'font-family="Arial Rounded MT Bold, Arial, sans-serif" font-size="24" '
            f'font-weight="900" fill="#ffffff">{name}</text>'
            f'<text x="{cx:.0f}" y="{box+64:.0f}" text-anchor="middle" '
            f'font-family="Arial, sans-serif" font-size="13" font-weight="700" '
            f'letter-spacing="2" fill="{c}">{role.upper()}</text></g>')
    parts.append("</svg>")
    sheet = os.path.join(MOCK, "trainers_contact.svg")
    open(sheet, "w").write("\n".join(parts))
    subprocess.run(["rsvg-convert", "-w", str(SW * 2), "-h", str(SH * 2),
                    sheet, "-o", sheet[:-4] + ".png"], check=True)
    print("wrote", sheet[:-4] + ".png")


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "all"
    if cmd in ("assets", "all"):
        build_assets()
    if cmd in ("sheet", "all"):
        build_sheet()


if __name__ == "__main__":
    main()
