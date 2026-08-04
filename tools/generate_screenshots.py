#!/usr/bin/env python3
"""App Store marketing screenshots for Trading Up — deterministic, no simulator.

Recreates the app's real screens in SVG using the exact palette, metrics and card
layout from the SwiftUI source (Theme.swift / CardView.swift), embeds the real
generated card art, wraps each screen in a floating device frame with a marketing
caption, and renders everything to PNG at official App Store pixel sizes with
`rsvg-convert` (from librsvg — `brew install librsvg`).

It renders a curated set of ten scenes — one screenshot slot each — at the two
sizes App Store Connect requires for this app: iPhone 6.5" and iPad Pro 13". The
device frame scales to fit whichever canvas, so the same faithful phone screens
compose cleanly on the squarer iPad background too.

Because it's driven by `data/cards.json` and the checked-in card-art PNGs, the whole
screenshot set regenerates on any machine with just `python3` + `rsvg-convert`, and
stays in sync with the game's real content and styling.

Usage:
  python3 tools/generate_screenshots.py           # render every scene at every size
  python3 tools/generate_screenshots.py --list     # list scenes and output sizes

Output: docs/screenshots/<scene>_<w>x<h>.png — 10 scenes x 2 sizes = 20 PNGs.
"""
import json
import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "docs", "screenshots")
ART_DIR = os.path.join(ROOT, "TradingUp", "Assets.xcassets", "CardArt")

# ------------------------------------------------------------------- app palette
# Mirrors TradingUp/Views/Theme.swift.
BG0, BG1 = "#0b0e14", "#121722"
PANEL, PANEL_HI = "#1a2130", "#232c40"
STROKE = "#2c3750"
TEXT, SUBTLE, MONEY = "#e7ecf5", "#8a94a6", "#5be08a"

ELEMENT = {
    "fire":     ["#ffd15c", "#ff7a1a", "#e01f1f", "#5c1004"],
    "rock":     ["#f0c27a", "#c98a3c", "#8a5a2b", "#3d2413"],
    "water":    ["#9fe8ff", "#39a7ff", "#1e5bd6", "#0a2a66"],
    "grass":    ["#c6f68d", "#5fd35f", "#2f9e44", "#12481f"],
    "electric": ["#fff3a3", "#ffd21a", "#f5a300", "#6b4a00"],
    "shadow":   ["#d9b3ff", "#9b5cf6", "#5b2bb3", "#1f0d3d"],
}
BADGE_TINT = {"fire": "#ff9a6b", "rock": "#e0b483", "water": "#8fd3ff",
              "grass": "#9fe08a", "electric": "#ffdf66", "shadow": "#c6a3ff"}
EMOJI = {"fire": "\U0001F525", "rock": "\U0001FAA8", "water": "\U0001F4A7",
         "grass": "\U0001F33F", "electric": "\u26A1", "shadow": "\U0001F311"}
RARITY_ACCENT = {"common": "#8a94a6", "uncommon": "#3fbf7f",
                 "rare": "#3b82f6", "ultra": "#b06cf7"}
SET_ELEMENT = {1: "fire", 2: "water", 3: "grass", 4: "electric", 5: "shadow"}
SET_NAME = {1: "Emberfall", 2: "Tidecaller", 3: "Verdspire", 4: "Voltcrest", 5: "Umbral Reach"}

ROUND = "'SF Pro Rounded','SF Pro Display','Helvetica Neue',Arial,sans-serif"
MONO = "'SF Mono','Menlo',ui-monospace,monospace"
SERIF = "'New York','Georgia',serif"

# Official App Store portrait sizes (px). The two display classes this app must
# provide screenshots for: iPhone 6.5" and iPad Pro 13" (it ships
# TARGETED_DEVICE_FAMILY "1,2", so iPad is required). App Store Connect accepts
# up to 10 screenshots per size, which is exactly what the scene list fills.
SIZES = [(1242, 2688), (2064, 2752)]

# ------------------------------------------------------------------ card catalog
def _load_cards():
    data = json.load(open(os.path.join(ROOT, "data", "cards.json")))
    cards = data["cards"] if isinstance(data, dict) else data
    return {c["id"]: c for c in cards}


_CARDS = _load_cards()


def money(v):
    return "${:,.2f}".format(v)


def art_path(cid):
    p = os.path.join(ART_DIR, cid + ".imageset", cid + ".png")
    return p if os.path.exists(p) else None


def value_of(card, foil=False, grade=None):
    v = card["baseValue"]
    if foil:
        v *= 3.0
    mult = {10: 5.0, 9: 2.0, 8: 1.0, 7: 0.8, 6: 0.7, 5: 0.6,
            4: 0.5, 3: 0.4, 2: 0.3, 1: 10.0}
    if grade is not None:
        v *= mult.get(grade, 1.0)
    return v


# --------------------------------------------------------------------- svg utils

def esc(s):
    return (str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def rrect(x, y, w, h, r, fill=None, stroke=None, sw=1.0, opacity=1.0, grad=None):
    f = "url(#%s)" % grad if grad else (fill or "none")
    s = ' stroke="%s" stroke-width="%.2f"' % (stroke, sw) if stroke else ""
    o = ' opacity="%.3f"' % opacity if opacity != 1.0 else ""
    return '<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="%s"%s%s/>' % (
        x, y, w, h, r, f, s, o)


def circle(cx, cy, r, fill=None, stroke=None, sw=1.0, opacity=1.0, grad=None):
    f = "url(#%s)" % grad if grad else (fill or "none")
    s = ' stroke="%s" stroke-width="%.2f"' % (stroke, sw) if stroke else ""
    o = ' opacity="%.3f"' % opacity if opacity != 1.0 else ""
    return '<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"%s%s/>' % (cx, cy, r, f, s, o)


def line(x1, y1, x2, y2, stroke, sw=1.0, opacity=1.0):
    return '<line x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f" stroke="%s" stroke-width="%.2f" opacity="%.3f"/>' % (
        x1, y1, x2, y2, stroke, sw, opacity)


def ell(cx, cy, rx, ry, fill=None, opacity=1.0, grad=None):
    f = "url(#%s)" % grad if grad else (fill or "none")
    return '<ellipse cx="%.2f" cy="%.2f" rx="%.2f" ry="%.2f" fill="%s" opacity="%.3f"/>' % (
        cx, cy, rx, ry, f, opacity)


def path(d, fill=None, stroke=None, sw=1.0, opacity=1.0, grad=None, cap="round"):
    f = "url(#%s)" % grad if grad else (fill or "none")
    s = (' stroke="%s" stroke-width="%.2f" stroke-linecap="%s" stroke-linejoin="round"'
         % (stroke, sw, cap)) if stroke else ""
    return '<path d="%s" fill="%s"%s opacity="%.3f"/>' % (d, f, s, opacity)


def poly(pts, fill=None, stroke=None, sw=1.0, opacity=1.0, grad=None):
    d = "M%.2f %.2f " % pts[0] + " ".join("L%.2f %.2f" % p for p in pts[1:]) + " Z"
    return path(d, fill=fill, stroke=stroke, sw=sw, opacity=opacity, grad=grad)


def text(x, y, s, size, fill, weight=600, anchor="start", family=ROUND,
         tracking=None, italic=False, opacity=1.0):
    a = {"start": "start", "middle": "middle", "end": "end"}[anchor]
    tr = ' letter-spacing="%.2f"' % tracking if tracking else ""
    it = ' font-style="italic"' if italic else ""
    o = ' opacity="%.3f"' % opacity if opacity != 1.0 else ""
    return ('<text x="%.2f" y="%.2f" font-family="%s" font-size="%.2f" font-weight="%s" '
            'fill="%s" text-anchor="%s"%s%s%s>%s</text>') % (
        x, y, family, size, weight, fill, a, tr, it, o, esc(s))


import base64

_IMG_CACHE = {}


def _data_uri(path):
    if path not in _IMG_CACHE:
        with open(path, "rb") as f:
            _IMG_CACHE[path] = "data:image/png;base64," + base64.b64encode(f.read()).decode("ascii")
    return _IMG_CACHE[path]


def image(x, y, w, h, path, clip_id):
    return ('<g clip-path="url(#%s)"><image x="%.2f" y="%.2f" width="%.2f" height="%.2f" '
            'preserveAspectRatio="xMidYMid slice" xlink:href="%s"/></g>') % (
        clip_id, x, y, w, h, _data_uri(path))


class Defs:
    """Accumulates gradient / clip defs, de-duplicating by id."""
    def __init__(self):
        self.items = {}

    def linear(self, stops, x1=0, y1=0, x2=0, y2=1):
        key = "lg_%d" % (hash((tuple(stops), x1, y1, x2, y2)) & 0xFFFFFFFF)
        body = "".join('<stop offset="%s" stop-color="%s" stop-opacity="%s"/>' % (o, c, a)
                       for o, c, a in stops)
        self.items[key] = ('<linearGradient id="%s" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>'
                            % (key, x1, y1, x2, y2, body))
        return key

    def radial(self, stops, cx=0.5, cy=0.5, r=0.5):
        key = "rg_%d" % (hash((tuple(stops), cx, cy, r)) & 0xFFFFFFFF)
        body = "".join('<stop offset="%s" stop-color="%s" stop-opacity="%s"/>' % (o, c, a)
                       for o, c, a in stops)
        self.items[key] = ('<radialGradient id="%s" cx="%s" cy="%s" r="%s">%s</radialGradient>'
                            % (key, cx, cy, r, body))
        return key

    def blur(self, r):
        key = "bl_%d" % (hash(("blur", r)) & 0xFFFFFFFF)
        self.items[key] = ('<filter id="%s" x="-60%%" y="-60%%" width="220%%" height="220%%">'
                           '<feGaussianBlur stdDeviation="%.2f"/></filter>') % (key, r)
        return key

    def clip_rrect(self, x, y, w, h, r):
        key = "cl_%d" % (hash((x, y, w, h, r)) & 0xFFFFFFFF)
        self.items[key] = '<clipPath id="%s"><rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f"/></clipPath>' % (
            key, x, y, w, h, r)
        return key

    def render(self):
        return "<defs>" + "".join(self.items.values()) + "</defs>"


def wrap(s, max_chars):
    out, cur = [], ""
    for word in s.split():
        if len(cur) + len(word) + 1 <= max_chars:
            cur = (cur + " " + word).strip()
        else:
            out.append(cur)
            cur = word
    if cur:
        out.append(cur)
    return out


# --------------------------------------------------------------- card component

def full_card(defs, x, y, w, cid, foil=False, grade=None):
    """A faithful CardView render at width `w` (height 1.4w), matching the app."""
    card = _CARDS[cid]
    s = w / 230.0
    h = w * 1.4
    pad = 10 * s
    corner = 16 * s
    ele = card["element"]
    epal = ELEMENT[ele]
    out = []

    body = defs.linear([("0%", PANEL_HI, "1"), ("100%", PANEL, "1")])
    out.append(rrect(x, y, w, h, corner, grad=body))

    inner_x = x + pad
    inner_w = w - 2 * pad
    cy = y + pad

    # header: name + element badge
    out.append(text(inner_x, cy + 13 * s, card["name"], 16 * s, TEXT, weight=800))
    bt = BADGE_TINT[ele]
    badge_w = (len(card["element"]) * 5.4 + 12) * s
    out.append(rrect(x + w - pad - badge_w, cy + 2 * s, badge_w, 15 * s, 7 * s, fill=bt, opacity=0.14))
    out.append(text(x + w - pad - badge_w / 2, cy + 12.5 * s, card["element"].capitalize(),
                    9 * s, bt, weight=700, anchor="middle"))
    cy += 20 * s + 6 * s

    # art window with embedded illustration
    aw_h = 150 * s
    agrad = defs.radial([("0%", epal[1], "0.55"), ("55%", epal[2], "1"), ("100%", epal[3], "1")],
                        cy=0.5, r=0.62)
    clip = defs.clip_rrect(inner_x, cy, inner_w, aw_h, 10 * s)
    out.append(rrect(inner_x, cy, inner_w, aw_h, 10 * s, grad=agrad))
    ap = art_path(cid)
    if ap:
        out.append(image(inner_x, cy, inner_w, aw_h, ap, clip))
    out.append(rrect(inner_x, cy, inner_w, aw_h, 10 * s, stroke="#ffffff", sw=1, opacity=0.08))
    if foil:
        holo = defs.linear([("0%", "#ff4d4d", "0.30"), ("25%", "#ffd24d", "0.22"),
                            ("50%", "#4dff88", "0.26"), ("75%", "#4dd2ff", "0.22"),
                            ("100%", "#b06cf7", "0.30")], x1=0, y1=0, x2=1, y2=1)
        out.append('<g clip-path="url(#%s)">%s</g>' % (
            clip, rrect(inner_x, cy, inner_w, aw_h, 10 * s, grad=holo)))
    cy += aw_h + 6 * s

    # meta row
    gem = defs.linear([("0%", _rarity_c(card, 0), "1"), ("100%", _rarity_c(card, 1), "1")], x1=0, y1=0, x2=1, y2=1)
    out.append(circle(inner_x + 4.5 * s, cy + 6 * s, 4.5 * s, grad=gem))
    out.append(text(inner_x + 13 * s, cy + 9 * s, SET_NAME[card["set"]], 10 * s, SUBTLE, weight=600))
    out.append(text(x + w - pad, cy + 9 * s, "%03d / 050" % card["number"], 10 * s, SUBTLE,
                    weight=600, anchor="end", family=MONO))
    cy += 12 * s + 6 * s

    # flavor (up to 3 lines)
    for i, ln in enumerate(wrap(card["flavor"], int(inner_w / (5.3 * s)))[:3]):
        out.append(text(inner_x, cy + 9 * s + i * 12 * s, ln, 10.5 * s, TEXT, weight=400,
                        family=SERIF, italic=True, opacity=0.72))

    # value bar pinned to bottom
    vb_y = y + h - pad - 20 * s
    acc = RARITY_ACCENT[card["rarity"]]
    disp = {"common": "COMMON", "uncommon": "UNCOMMON", "rare": "RARE", "ultra": "ULTRA RARE"}[card["rarity"]]
    pill_w = (len(disp) * 5.6 + 14) * s
    out.append(rrect(inner_x, vb_y, pill_w, 17 * s, 8.5 * s, fill=acc, opacity=0.16))
    out.append(text(inner_x + pill_w / 2, vb_y + 12 * s, disp, 9.5 * s, acc, weight=800, anchor="middle"))
    out.append(text(x + w - pad, vb_y + 14 * s, money(value_of(card, foil, grade)), 15 * s, MONEY,
                    weight=800, anchor="end"))

    # rarity frame
    fw = (3 if card["rarity"] == "ultra" else 2) * s
    if card["rarity"] == "ultra":
        fr = defs.linear([("0%", "#ffd54a", "1"), ("50%", "#ff8ad6", "1"), ("100%", "#b06cf7", "1")], x1=0, y1=0, x2=1, y2=1)
        out.append(rrect(x, y, w, h, corner, stroke="url(#%s)" % fr, sw=fw))
    else:
        out.append(rrect(x, y, w, h, corner, stroke=acc, sw=fw))

    if grade is not None:
        gc = "#ffd54a" if grade >= 9 else ("#8a94a6" if grade >= 8 else ("#ff5cf0" if grade == 1 else "#e0663b"))
        bx, by = x + w - 20 * s, y + 6 * s
        out.append(circle(bx, by + 14 * s, 17 * s, fill=gc, stroke="#ffffff", sw=2 * s))
        out.append(text(bx, by + 9 * s, "PSA", 8 * s, "#111", weight=900, anchor="middle"))
        out.append(text(bx, by + 22 * s, str(grade), 16 * s, "#111", weight=900, anchor="middle"))

    return "".join(out)


def _rarity_c(card, idx):
    if card["rarity"] == "ultra":
        return ["#ffd54a", "#ff8ad6"][idx]
    acc = RARITY_ACCENT[card["rarity"]]
    return acc


def locked_card(defs, x, y, w, card):
    s = w / 230.0
    h = w * 1.4
    out = [rrect(x, y, w, h, 16 * s, fill=BG0, opacity=0.55)]
    out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="none" '
               'stroke="%s" stroke-width="%.2f" stroke-dasharray="%.1f %.1f"/>' % (
                   x, y, w, h, 16 * s, STROKE, 1.5 * s, 5 * s, 4 * s))
    out.append(text(x + w / 2, y + h / 2 - 2 * s, "?", 34 * s, STROKE, weight=900, anchor="middle"))
    out.append(text(x + w / 2, y + h / 2 + 22 * s, "%03d / 050" % card["number"], 11 * s,
                    SUBTLE, weight=600, anchor="middle", family=MONO, opacity=0.7))
    return "".join(out)


def placed_card(defs, cx, cy, w, cid, angle=0.0, foil=False, grade=None):
    """A full_card centred on (cx, cy) and rotated `angle` degrees — the building
    block for fanned, overlapping card collages."""
    h = w * 1.4
    card = full_card(defs, cx - w / 2, cy - h / 2, w, cid, foil=foil, grade=grade)
    if angle:
        return '<g transform="rotate(%.2f %.2f %.2f)">%s</g>' % (angle, cx, cy, card)
    return card


# ------------------------------------------------------------- shared UI pieces

def progress(defs, x, y, w, frac, tint, h=8):
    out = [rrect(x, y, w, h, h / 2, fill=BG0)]
    if frac > 0:
        out.append(rrect(x, y, max(h, w * frac), h, h / 2, fill=tint))
    return "".join(out)


def stat_tile(x, y, w, value, label, tint=TEXT):
    h = 66
    out = [rrect(x, y, w, h, 14, fill=BG0, opacity=0.5)]
    out.append(text(x + w / 2, y + 30, value, 20, tint, weight=800, anchor="middle"))
    out.append(text(x + w / 2, y + 50, label.upper(), 10, SUBTLE, weight=600, anchor="middle"))
    return "".join(out)


def tab_bar(defs, w, y):
    out = [rrect(0, y, w, 852 - y, 0, fill=BG1, opacity=0.96)]
    out.append(line(0, y, w, y, STROKE, 0.75))
    tabs = [("Shop", MONEY, True), ("Collection", SUBTLE, False), ("Stats", SUBTLE, False)]
    seg = w / 3
    for i, (name, col, on) in enumerate(tabs):
        cx = seg * i + seg / 2
        out.append(circle(cx, y + 24, 9, fill=col, opacity=0.9 if on else 0.7))
        out.append(text(cx, y + 46, name, 11, col, weight=700 if on else 500, anchor="middle"))
    return "".join(out)


def panel(defs, x, y, w, h):
    return rrect(x, y, w, h, 18, fill=PANEL, stroke=STROKE, sw=1)


# -------------------------------------------------------------------- screens
# Each returns SVG drawn in a 393 x 852 viewBox (iPhone point space), matching
# the app's real metrics.

SCREEN_W, SCREEN_H = 393, 852


PACK_PRICES = {1: 10.0, 2: 30.0, 3: 75.0, 4: 160.0, 5: 400.0}


def _blend(a, b, t):
    """Interpolate two hex colours, mirroring blend() in SetArt.swift."""
    ai = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    bi = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02x%02x%02x" % tuple(int(round(ai[i] + (bi[i] - ai[i]) * t)) for i in range(3))


# Crown lobes: angle, distance, size. Deliberately uneven, so the silhouette
# breaks into leaf clusters instead of settling into a smooth cloud.
_LOBES = [(-2.35, 0.78, 0.46), (-1.62, 0.66, 0.50), (-1.05, 0.80, 0.44), (-0.42, 0.80, 0.42),
          (0.24, 0.70, 0.44), (0.95, 0.58, 0.36), (1.75, 0.55, 0.34), (2.35, 0.74, 0.42),
          (2.95, 0.80, 0.44)]


def _tree(defs, x, base, crown_y, r, depth, op=1.0, detail=True):
    """One tree, mirroring SetScene.tree in SetArt.swift: tapered trunk, forked
    branches, lobed crown. depth runs 0 (far, hazed back) to 1 (front, lit)."""
    shell = _blend("06240e", "093315", depth)
    body = _blend("11421d", "3fbb52", depth)
    lit = _blend("1e6129", "96f57e", depth)
    bark = _blend("0a2711", "48331a", depth)
    bark_dark = _blend("051b0a", "171007", depth)
    out = []

    w = r * 0.15 + 0.55
    ctrl = base - (base - crown_y) * 0.55
    trunk = defs.linear([("0%", bark, "1"), ("100%", bark_dark, "1")], x1=0, y1=0, x2=1, y2=0.6)
    out.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f L%.2f %.2f Q%.2f %.2f %.2f %.2f Z" % (
        x - w * 1.7, base, x - w * 0.85, ctrl, x - w * 0.45, crown_y,
        x + w * 0.45, crown_y, x + w * 0.85, ctrl, x + w * 1.7, base),
        grad=trunk, opacity=op))
    for side in (-1, 1):
        out.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f" % (
            x, crown_y + r * 0.85, x + side * r * 0.16, crown_y + r * 0.55,
            x + side * r * 0.6, crown_y + r * 0.1),
            stroke=bark, sw=max(0.7, w * 0.55), opacity=op))

    def crown(scale, dx, dy, fill, opacity):
        # Opaque lobes inside one group: the union reads as a single mass, and
        # the group opacity keeps overlaps from seaming.
        parts = [ell(x + dx, crown_y + dy, r * 0.62 * scale, r * 0.66 * scale, fill=fill)]
        for a, d, sz in _LOBES:
            parts.append(ell(x + dx + math.cos(a) * r * d * 0.9 * scale,
                             crown_y + dy + math.sin(a) * r * d * scale,
                             r * sz * scale, r * sz * 0.92 * scale, fill=fill))
        return '<g opacity="%.3f">%s</g>' % (opacity, "".join(parts))

    out.append(crown(1, 0, 0, shell, op))
    out.append(crown(0.84, -r * 0.05, -r * 0.09, body, op))
    out.append(crown(0.46, -r * 0.16, -r * 0.26, lit, 0.5 * op))
    if depth > 0.25:
        for a, d in ((-2.45, 0.82), (-1.72, 0.74), (-1.1, 0.84), (-0.55, 0.86)):
            out.append(ell(x + math.cos(a) * r * d * 0.9, crown_y + math.sin(a) * r * d,
                           r * 0.26, r * 0.2, fill=lit, opacity=0.55 * op))
    if not detail:
        return "".join(out)

    for a, d in ((-2.5, 1.0), (-1.75, 0.96), (-0.95, 1.02), (-0.18, 0.98), (2.55, 0.98)):
        bx, by = x + math.cos(a) * r * d * 0.9, crown_y + math.sin(a) * r * d
        tx, ty = x + math.cos(a) * r * (d + 0.2) * 0.9, crown_y + math.sin(a) * r * (d + 0.2)
        nx, ny = -math.sin(a) * r * 0.18, math.cos(a) * r * 0.18
        out.append(poly([(bx + nx, by + ny), (tx, ty), (bx - nx, by - ny)], fill=body, opacity=op))

    out.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f" % (
        x - w * 1.35, base - 2, x - w * 1.1, base - (base - crown_y) * 0.5,
        x - w * 0.5, crown_y + 4), stroke="#4faf4f", sw=w * 0.55, opacity=0.35 * op))
    return "".join(out)


def _wisp(x, y, s, op):
    w, h = 5.2 * s, 6.4 * s
    d = ("M%.2f %.2f L%.2f %.2f A%.2f %.2f 0 0 1 %.2f %.2f L%.2f %.2f "
         "L%.2f %.2f L%.2f %.2f L%.2f %.2f Z") % (
        x - w, y + h, x - w, y - h * 0.15, w, w, x + w, y - h * 0.15,
        x + w, y + h, x + w * 0.5, y + h * 0.55, x, y + h, x - w * 0.5, y + h * 0.55)
    out = [path(d, fill="#d9b3ff", opacity=0.72 * op)]
    for ex in (-w * 0.42, w * 0.42):
        out.append(ell(x + ex, y - h * 0.05, 1.1 * s, 1.5 * s, fill="#1f0d3d", opacity=0.85 * op))
    return "".join(out)


def set_emblem(defs, cx, cy, size, set_no, op=1.0):
    """Per-set pack artwork, an SVG echo of SetEmblem/SetScene in SetArt.swift.

    Drawn in the same 100x100 design space the SwiftUI Canvas uses, then scaled
    into place, so the marketing screenshots match what ships in the app.
    """
    pal = ELEMENT[SET_ELEMENT[set_no]]
    hi, mid, deep, dark = pal
    k = size / 100.0
    o = []

    def wash(wx, wy, color):
        g = defs.radial([("0%", color, "0.92"), ("62%", color, "0.62"), ("100%", color, "0")])
        return circle(wx, wy, 50, grad=g, opacity=0.95 * op)

    def soft(body, r):
        return '<g filter="url(#%s)">%s</g>' % (defs.blur(r), body)

    if set_no == 1:  # Emberfall - volcano, magma, rock
        o.append(wash(50, 56, "#2a0f08"))
        o.append(soft(poly([(45, 32), (55, 32), (58, 22), (42, 22)],
                           fill="#6b4a3a", opacity=0.45 * op), 2.2))
        o.append(soft("".join([
            ell(50, 19, 17, 8, fill="#6b4a3a", opacity=0.8 * op),
            ell(37, 22, 10, 6, fill="#5e4034", opacity=0.7 * op),
            ell(63, 21, 11, 6, fill="#5e4034", opacity=0.7 * op),
            ell(50, 13, 9, 5, fill="#7a5949", opacity=0.5 * op)]), 2.4))
        o.append(poly([(66, 76), (78, 48), (90, 76)], fill=dark, opacity=0.55 * op))
        o.append(poly([(12, 76), (24, 52), (36, 76)], fill=dark, opacity=0.5 * op))
        cone = defs.linear([("0%", "#8a4a34", "1"), ("55%", "#5a2c20", "1"), ("100%", "#33150f", "1")])
        o.append(poly([(16, 78), (41, 33), (59, 33), (84, 78)], grad=cone, opacity=op))
        o.append(path("M41 33 L16 78", stroke="#c9714a", sw=1.4, opacity=0.5 * op))
        o.append(path("M59 33 L84 78", stroke="#8d4630", sw=1.2, opacity=0.35 * op))
        for d, sw, a in (("M46 34 C43 46 39 56 33 76", 2.6, 0.95),
                         ("M54 34 C58 47 62 58 68 76", 2.4, 0.9),
                         ("M50 34 C50 50 49 62 47 77", 1.9, 0.8)):
            o.append(path(d, stroke=mid, sw=sw, opacity=a * op))
            o.append(path(d, stroke=hi, sw=sw * 0.42, opacity=a * 0.9 * op))
        o.append(soft(ell(50, 33, 11, 4.4, fill=mid, opacity=0.9 * op), 2.0))
        o.append(ell(50, 33, 9, 3.0, fill=mid, opacity=0.95 * op))
        o.append(ell(50, 32, 5.4, 2.0, fill=hi, opacity=op))
        pool = defs.linear([("0%", hi, "1"), ("45%", mid, "1"), ("100%", deep, "1")])
        o.append(ell(50, 80, 34, 7.5, grad=pool, opacity=0.95 * op))
        for rx, ry, rw in ((33, 81, 5.5), (50, 83, 4.6), (66, 80, 5.0)):
            o.append(poly([(rx - rw, ry), (rx, ry - 2.6), (rx + rw, ry), (rx, ry + 2.6)],
                          fill="#2a0f08", opacity=0.85 * op))
        for ex, ey, er in ((28, 46, 1.5), (72, 40, 1.3), (22, 62, 1.2), (80, 58, 1.4), (34, 30, 1.1)):
            o.append(circle(ex, ey, er, fill=hi, opacity=0.85 * op))

    elif set_no == 2:  # Tidecaller - small islands amongst massive swells
        o.append(wash(50, 54, "#061c40"))
        o.append(circle(33, 21, 5.5, fill="#dff2ff", opacity=0.85 * op))
        for sx, sy in ((22, 34), (44, 16), (58, 12), (70, 24), (26, 15), (78, 38)):
            o.append(circle(sx, sy, 0.9, fill="#ffffff", opacity=0.6 * op))
        body = defs.linear([("0%", hi, "1"), ("34%", mid, "1"), ("100%", deep, "1")],
                           x1=0.15, y1=0, x2=0.85, y2=1)
        crest = ("M28 82 C24 50 34 24 54 22 C72 20 85 32 84 48 C83 62 74 70 62 68 "
                 "C72 64 77 54 72 45 C66 35 53 34 46 44 C39 54 38 68 40 82 Z")
        o.append(path(crest, grad=body, opacity=op))
        o.append(path("M28 82 C24 50 34 24 54 22 C72 20 85 32 84 48 C83 62 74 70 62 68",
                      stroke="#ffffff", sw=2.6, opacity=0.92 * op))
        for d in ("M62 68 C60 74 58 78 57 82", "M69 66 C69 73 68 78 67 82",
                  "M39 60 C37 68 37 75 38 82"):
            o.append(path(d, stroke=hi, sw=1.4, opacity=0.5 * op))
        for fx, fy, fr in ((36, 34, 2.4), (44, 25, 2.9), (55, 21, 3.1), (67, 24, 2.4),
                           (78, 33, 2.0), (61, 68, 2.6)):
            o.append(circle(fx, fy, fr, fill="#ffffff", opacity=0.9 * op))
        for sx, sy in ((30, 26), (40, 17), (52, 13), (66, 15), (76, 22)):
            o.append(circle(sx, sy, 1.1, fill="#dff2ff", opacity=0.7 * op))
        sea = defs.linear([("0%", mid, "1"), ("100%", "#061c40", "1")])
        o.append(ell(48, 86, 40, 13, grad=sea, opacity=0.95 * op))
        for ix, ib, iw in ((28, 74, 9), (48, 77, 7)):
            o.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f Z" % (
                ix - iw, ib, ix, ib - iw * 0.85, ix + iw, ib), fill="#2b4a70", opacity=op))
            o.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f" % (
                ix - iw * 0.7, ib - iw * 0.25, ix, ib - iw * 0.9, ix + iw * 0.35, ib - iw * 0.55),
                stroke="#7fb0dc", sw=1.1, opacity=0.55 * op))
            o.append(path("M%.2f %.2f L%.2f %.2f" % (ix, ib, ix + 1, ib - iw * 1.5),
                          stroke="#6fd6a6", sw=1.2, opacity=0.9 * op))
            for a in (-1, 1):
                o.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f" % (
                    ix + 1, ib - iw * 1.5, ix + 1 + a * 3, ib - iw * 1.9,
                    ix + 1 + a * 6, ib - iw * 1.5), stroke="#6fd6a6", sw=1.1, opacity=0.9 * op))
        for wx, wy, ww in ((26, 86, 9), (48, 90, 8), (68, 85, 7)):
            o.append(ell(wx, wy, ww, 2.4, fill=hi, opacity=0.3 * op))

    elif set_no == 3:  # Verdspire - mossy jungle
        o.append(wash(50, 48, "#051d0b"))
        day = defs.radial([("0%", "#b6e88a", "0.22"), ("50%", "#2f9e44", "0.07"),
                           ("100%", "#07240f", "0")], cy=0.35)
        o.append(circle(50, 40, 40, grad=day, opacity=op))
        for fx, fbase, fcy, fr in ((16, 78, 56, 6.5), (37, 77, 53, 5.4),
                                   (63, 77, 54, 5.8), (85, 78, 57, 6.2)):
            o.append(_tree(defs, fx, fbase, fcy, fr, 0, op, detail=False))
        beam = defs.linear([("0%", "#eaffb0", "0"), ("50%", "#eaffb0", "0.13"),
                            ("100%", "#eaffb0", "0")])
        for bx, bw, spread in ((37, 5, 22), (68, 4, 18)):
            o.append(poly([(bx, 16), (bx + bw, 16), (bx + bw + spread, 90), (bx - spread * 0.3, 90)],
                          grad=beam, opacity=op))
        o.append(_tree(defs, 23, 85, 34, 12.5, 0.5, op))
        o.append(_tree(defs, 79, 85, 37, 11.5, 0.45, op))
        o.append(_tree(defs, 51, 88, 22, 15.0, 1.0, op))
        for vx, vy0, vy1, sway in ((36, 31, 60, 4), (65, 30, 64, -4),
                                   (12, 42, 62, 3.5), (90, 46, 66, -3)):
            o.append(path("M%.2f %.2f Q%.2f %.2f %.2f %.2f" % (
                vx, vy0, vx + sway * 1.9, (vy0 + vy1) / 2, vx + sway, vy1),
                stroke="#1f6b30", sw=1.1, opacity=op))
        floor = defs.linear([("0%", "#0c3417", "0"), ("20%", "#0c3417", "1"),
                             ("50%", "#1c5f2b", "1"), ("80%", "#0c3417", "1"),
                             ("100%", "#0c3417", "0")], x1=0, y1=0, x2=1, y2=0)
        o.append(ell(50, 89, 42, 9, grad=floor, opacity=0.95 * op))
        for mx, my, mr in ((30, 85, 11), (60, 86, 10), (80, 88, 8), (17, 88, 8)):
            o.append(ell(mx, my, mr, mr * 0.22, fill="#3fae52", opacity=0.35 * op))
        for fx, a in ((11, 1), (89, -1)):
            for i in range(4):
                o.append(path("M%.2f 91 Q%.2f %.2f %.2f %.2f" % (
                    fx, fx + a * (3 + i * 2), 83 - i * 2, fx + a * (5 + i * 4), 77 - i * 4),
                    stroke="#3fbf5f", sw=1.4, opacity=0.85 * op))
        for gx, gy in ((33, 50), (66, 42), (44, 62), (74, 64), (18, 64), (40, 38), (85, 52)):
            o.append(circle(gx, gy, 1.1, fill="#f6ffcf", opacity=0.7 * op))

    elif set_no == 4:  # Voltcrest - static, thunderstorms
        o.append(wash(50, 50, "#231a05"))
        o.append(poly([(14, 82), (30, 64), (42, 74), (56, 60), (70, 73), (86, 82)],
                      fill="#333e60", opacity=op))
        o.append(path("M14 82 L30 64 L42 74 L56 60 L70 73 L86 82", stroke="#8fa0c8",
                      sw=1.1, opacity=0.38 * op))
        o.append(soft("".join(
            ell(bx, by, br, br * 0.62, fill="#39415f", opacity=op)
            for bx, by, br in ((30, 30, 15), (48, 25, 17), (66, 29, 15), (48, 33, 16))), 0.7))
        for bx, by, br in ((34, 24, 9), (52, 19, 10), (66, 24, 8)):
            o.append(ell(bx, by, br, br * 0.5, fill="#5a6389", opacity=0.55 * op))
        glow = defs.radial([("0%", hi, "0.55"), ("100%", hi, "0")])
        o.append(soft(circle(52, 50, 30, grad=glow, opacity=op), 3.0))
        bolt = [(54, 30), (43, 52), (53, 51), (42, 76), (67, 46), (57, 47), (65, 28)]
        o.append(poly(bolt, fill=mid, opacity=op))
        o.append(path("M56 32 L47 51 L56 50 L48 68", stroke="#fffbe0", sw=1.6, opacity=0.9 * op))
        for sx, sy, ss in ((28, 44, 1.0), (74, 40, 0.9), (34, 62, 0.8), (78, 60, 1.0)):
            o.append(poly([(sx, sy - 8 * ss), (sx - 4 * ss, sy), (sx, sy - 1 * ss),
                           (sx - 2 * ss, sy + 8 * ss), (sx + 5 * ss, sy - 2 * ss),
                           (sx + 1 * ss, sy - 1 * ss), (sx + 4 * ss, sy - 8 * ss)],
                          fill=mid, opacity=0.8 * op))
        for rx, ry in ((20, 40), (26, 56), (40, 38), (62, 36), (80, 50), (86, 36)):
            o.append(path("M%.2f %.2f L%.2f %.2f" % (rx, ry, rx - 2, ry + 12),
                          stroke=hi, sw=1.1, opacity=0.35 * op))
        for sx, sy, ss in ((36, 34, 3.2), (70, 56, 2.8), (24, 66, 2.4), (64, 22, 2.6)):
            o.append(path("M%.2f %.2f L%.2f %.2f M%.2f %.2f L%.2f %.2f" % (
                sx, sy - ss, sx, sy + ss, sx - ss, sy, sx + ss, sy),
                stroke="#fffbe0", sw=1.2, opacity=0.8 * op))

    else:  # Umbral Reach - shadow, spirits, eclipse
        o.append(wash(50, 50, "#170830"))
        halo = defs.radial([("0%", hi, "0.5"), ("100%", hi, "0")])
        o.append(soft(circle(57, 27, 26, grad=halo, opacity=op), 2.4))
        o.append(circle(57, 27, 14, fill="#120726", opacity=op))
        o.append(circle(57, 27, 14, stroke="#e9d4ff", sw=2.0, opacity=0.95 * op))
        o.append(ell(50, 82, 38, 10, fill="#2a1250", opacity=0.9 * op))
        for tx, a in ((18, 1), (84, -1)):
            o.append(path("M%.2f 80 L%.2f 56" % (tx, tx + a * 3), stroke="#3a2060",
                          sw=2.2, opacity=op))
            for i in (0, 1):
                o.append(path("M%.2f %.2f L%.2f %.2f" % (
                    tx + a * 2, 64 - i * 5, tx + a * (8 + i * 2), 58 - i * 7),
                    stroke="#3a2060", sw=1.5, opacity=op))
        o.append(_wisp(36, 62, 1.15, op))
        o.append(_wisp(72, 60, 0.85, op))
        o.append(_wisp(54, 52, 0.6, 0.7 * op))
        for dx, dy in ((22, 30), (40, 22), (76, 46), (30, 48), (66, 70), (86, 26), (14, 62)):
            o.append(circle(dx, dy, 1.0, fill="#e9d4ff", opacity=0.55 * op))

    return '<g transform="translate(%.2f,%.2f) scale(%.4f)">%s</g>' % (
        cx - size / 2, cy - size / 2, k, "".join(o))


def pack_thumb(defs, x, y, w, set_no, dim=False):

    """The shop's 58pt PackWrapper: crimped foil sleeve, sigil, set name."""
    ele = SET_ELEMENT[set_no]
    pal = ELEMENT[ele]
    crimp = w * 0.085
    tooth = w * 0.072
    fh = w * 1.30
    out = []
    op = 0.4 if dim else 1.0

    def crimp_band(cy, point_down):
        g = defs.linear([("0%", pal[1], "1"), ("100%", pal[2], "1")], x1=0, y1=0, x2=1, y2=0)
        pts = []
        n = max(2, int(round(w / tooth)))
        step = w / n
        if point_down:
            pts.append("M%.2f %.2f" % (x, cy))
            for i in range(n):
                pts.append("L%.2f %.2f L%.2f %.2f" % (
                    x + step * (i + 0.5), cy + step * 0.5, x + step * (i + 1), cy))
            pts.append("L%.2f %.2f L%.2f %.2f Z" % (x + w, cy - crimp, x, cy - crimp))
        else:
            pts.append("M%.2f %.2f" % (x, cy))
            for i in range(n):
                pts.append("L%.2f %.2f L%.2f %.2f" % (
                    x + step * (i + 0.5), cy - step * 0.5, x + step * (i + 1), cy))
            pts.append("L%.2f %.2f L%.2f %.2f Z" % (x + w, cy + crimp, x, cy + crimp))
        return '<path d="%s" fill="url(#%s)" opacity="%.2f"/>' % (" ".join(pts), g, op)

    top = y + tooth * 0.5
    out.append(crimp_band(top + crimp, True))
    face = defs.linear([("0%", pal[1], "1"), ("42%", pal[2], "1"), ("100%", pal[3], "1")],
                       x1=0.29, y1=0, x2=0.71, y2=1)
    out.append(rrect(x, top + crimp, w, fh, 1.5, grad=face, opacity=op))
    sheen = defs.linear([("0%", "#ffffff", "0"), ("45%", "#ffffff", "0.30"),
                         ("62%", "#ffffff", "0.03"), ("100%", "#ffffff", "0")], x1=0, y1=0, x2=1, y2=1)
    clip = defs.clip_rrect(x, top + crimp, w, fh, 1.5)
    out.append('<g clip-path="url(#%s)">%s</g>' % (
        clip, rrect(x - w * 0.5, top + crimp, w * 0.7, fh, 0, grad=sheen, opacity=op)))
    out.append(crimp_band(top + crimp + fh, False))

    # per-set emblem, mirroring SetEmblem / SetScene
    cx, cy = x + w / 2, top + crimp + fh * 0.42
    out.append(set_emblem(defs, cx, cy, w * 0.66, set_no, op))

    gold = defs.linear([("0%", "#fff6d0", "1"), ("55%", "#ffd54a", "1"), ("100%", "#b8860b", "1")])
    name = SET_NAME[set_no]
    size = w * 0.16 if len(name) <= 10 else w * 0.115
    out.append(text(cx, top + crimp + fh * 0.87, name, size, "url(#%s)" % gold,
                    weight=900, anchor="middle", opacity=op))
    return "".join(out)


def progress_ring(defs, cx, cy, r, value, total, tint):
    out = [circle(cx, cy, r, stroke="#ffffff", sw=4, opacity=0.09)]
    frac = max(0.0, min(1.0, value / float(total)))
    if frac > 0:
        a0 = -math.pi / 2
        a1 = a0 + frac * 2 * math.pi
        large = 1 if frac > 0.5 else 0
        out.append('<path d="M%.2f %.2f A%.2f %.2f 0 %d 1 %.2f %.2f" fill="none" stroke="%s" '
                   'stroke-width="4" stroke-linecap="round"/>' % (
                       cx + math.cos(a0) * r, cy + math.sin(a0) * r, r, r, large,
                       cx + math.cos(a1) * r, cy + math.sin(a1) * r, tint))
    out.append(text(cx, cy + 4, str(value), 11, TEXT, weight=700, anchor="middle"))
    return "".join(out)


def shelf_row(defs, x, y, w, set_no, owned, unlocked, remaining=0):
    """One SetShelfRow: pack art, title + ring, one buy."""
    ele = SET_ELEMENT[set_no]
    pal = ELEMENT[ele]
    h = 108 if unlocked else 84
    out = [rrect(x, y, w, h, 20, fill=PANEL, stroke=STROKE, sw=1)]
    glow = defs.radial([("0%", pal[2], "0.26" if unlocked else "0.08"), ("100%", pal[2], "0")],
                       cx=0.05, cy=0.05, r=0.85)
    clip = defs.clip_rrect(x, y, w, h, 20)
    out.append('<g clip-path="url(#%s)">%s%s</g>' % (
        clip, rrect(x, y, w, h, 0, grad=glow),
        rrect(x, y, 4, h, 0, grad=defs.linear([("0%", pal[1], "1"), ("100%", pal[2], "1")]),
              opacity=1.0 if unlocked else 0.4)))

    pw = 42
    out.append(pack_thumb(defs, x + 16, y + (h - pw * 1.47) / 2, pw, set_no, dim=not unlocked))

    tx = x + 16 + pw + 14
    tw = w - (tx - x) - 14
    out.append(text(tx, y + 30, SET_NAME[set_no], 19, TEXT, weight=800))
    sub = "Set %d \u00b7 %d of 50 collected" % (set_no, owned) if unlocked else "Set %d \u00b7 locked" % set_no
    out.append(text(tx, y + 46, sub, 11.5, SUBTLE, weight=600))

    if unlocked:
        out.append(progress_ring(defs, x + w - 14 - 21, y + 34, 19, owned, 50, pal[1]))
        by = y + 56
        bh = 38
        g = defs.linear([("0%", pal[1], "1"), ("100%", pal[2], "1")], x1=0, y1=0, x2=1, y2=0)
        out.append(rrect(tx, by, tw, bh, 13, grad=g))
        out.append(rrect(tx, by, tw, bh, 13, stroke="#ffffff", sw=1, opacity=0.2))
        out.append(text(tx + 14, by + 24, "Buy a pack", 15, "#ffffff", weight=700))
        out.append(text(tx + tw - 14, by + 24, money(PACK_PRICES[set_no]), 15, "#ffffff",
                        weight=900, anchor="end"))
    else:
        out.append(text(x + w - 16, y + 34, "\U0001f512", 14, SUBTLE, weight=700, anchor="end"))
        cy = y + 54
        out.append('<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="13" fill="none" '
                   'stroke="%s" stroke-width="1" stroke-dasharray="4 3"/>' % (tx, cy, tw, 34, STROKE))
        out.append(text(tx + 14, cy + 22,
                        "%d more unique cards to unlock" % remaining, 12.5, SUBTLE, weight=600))

    return "".join(out), h


def screen_shop(defs):
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", BG1, "1"), ("100%", BG0, "1")]))]
    m = 16
    # Pinned wallet header
    out.append(rrect(0, 0, SCREEN_W, 116, 0, fill=BG1, opacity=0.96))
    out.append(line(0, 116, SCREEN_W, 116, "#ffffff", 1, opacity=0.07))
    cg = defs.radial([("0%", "#b8ffd6", "1"), ("55%", MONEY, "1"), ("100%", "#2c9c5c", "1")],
                     cx=0.35, cy=0.3, r=0.85)
    out.append(circle(18 + 15, 62, 15, grad=cg))
    out.append(text(18 + 15, 67, "$", 15, "#06301b", weight=900, anchor="middle"))
    out.append(text(18 + 38, 72, "$248.50", 26, MONEY, weight=900))
    out.append(text(SCREEN_W - 18, 58, "NET WORTH", 10, SUBTLE, weight=800, anchor="end", tracking=0.8))
    out.append(text(SCREEN_W - 18, 74, "$1,062.75", 15, TEXT, weight=700, anchor="end"))
    out.append(text(18, 99, "BINDER", 11, SUBTLE, weight=700))
    out.append(progress(defs, 70, 92, SCREEN_W - 70 - 18 - 44, 63 / 250, MONEY, h=6))
    out.append(text(SCREEN_W - 18, 99, "63/250", 11, SUBTLE, weight=700, anchor="end", family=MONO))

    # Shelf starts one gutter below the pinned header, matching ShopView's
    # LazyVStack top padding now that the section eyebrow is gone.
    y = 128

    rows = [(1, 24, True, 0), (2, 21, True, 0), (3, 18, True, 0), (4, 0, False, 12), (5, 0, False, 37)]
    for set_no, owned, unlocked, remaining in rows:
        svg, h = shelf_row(defs, m, y, SCREEN_W - 2 * m, set_no, owned, unlocked, remaining)
        out.append(svg)
        y += h + 12

    out.append(tab_bar(defs, SCREEN_W, 788))
    return "".join(out)


def screen_reveal(defs):
    """A rare hit flipping over mid-pack — the moment worth chasing."""
    cid = "S1-003"           # Pyrewolf, the set-1 fire rare
    acc = RARITY_ACCENT["rare"]
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0, fill=BG0)]
    glow = defs.radial([("0%", acc, "0.42"), ("100%", acc, "0")], r=0.7)
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, grad=glow))

    # progress dots — six cards; we're stopped on the fifth, the rare.
    dots = ["common", "common", "uncommon", "common", "rare", "uncommon"]
    dw = 16
    x0 = (SCREEN_W - len(dots) * dw) / 2
    for i, r in enumerate(dots):
        out.append(circle(x0 + i * dw + dw / 2, 96, 4.5, fill=RARITY_ACCENT[r],
                          opacity=1.0 if i == 4 else 0.45))

    # rotating glow burst behind hero card
    cx, cy = SCREEN_W / 2, 400
    burst = defs.radial([("0%", "#7db4ff", "0.55"), ("70%", "#7db4ff", "0")], r=0.5)
    out.append(circle(cx, cy, 230, grad=burst))
    for i in range(16):
        a = i / 16 * 2 * math.pi
        out.append(line(cx, cy, cx + math.cos(a) * 250, cy + math.sin(a) * 250,
                        acc, 6, opacity=0.10))

    # hero card: the rare, with a holo sheen
    cw = 230
    hx, hy = cx - cw / 2, cy - cw * 0.7
    out.append(full_card(defs, hx, hy, cw, cid, foil=True))

    # "NEW" flag above the hero — a fresh pull entering the collection
    nb_w = 92
    out.append(rrect(cx - nb_w / 2, hy - 32, nb_w, 26, 13,
                     grad=defs.linear([("0%", "#5be08a", "1"), ("100%", "#2c9c5c", "1")],
                                      x1=0, y1=0, x2=1, y2=0)))
    out.append(text(cx, hy - 14, "NEW!", 13, "#06301b", weight=900, anchor="middle"))

    # sparkle particles
    import hashlib
    seed = int(hashlib.md5(cid.encode()).hexdigest(), 16)
    cols = ["#7db4ff", "#3b82f6", "#bfe0ff", "#ffffff"]
    for i in range(30):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        a = (seed % 1000) / 1000 * 2 * math.pi
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        dist = 120 + (seed % 130)
        px = cx + math.cos(a) * dist
        py = cy + math.sin(a) * dist * 0.9
        r = 2 + (seed % 4)
        out.append(circle(px, py, r, fill=cols[i % len(cols)], opacity=0.85))

    # labels
    out.append(text(cx, 690, "RARE", 15, acc, weight=900, anchor="middle", tracking=2))
    out.append(text(cx, 726, "Tap for next card", 14, SUBTLE, weight=600, anchor="middle"))
    return "".join(out)


def screen_collection(defs):
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", BG1, "1"), ("100%", BG0, "1")]))]
    m = 16
    # segmented set picker
    y = 58
    seg_w = (SCREEN_W - 2 * m) / 5
    out.append(rrect(m, y, SCREEN_W - 2 * m, 32, 9, fill=BG0, opacity=0.6))
    out.append(rrect(m + 2, y + 2, seg_w - 4, 28, 7, fill=PANEL_HI))
    for i in range(5):
        out.append(text(m + seg_w * i + seg_w / 2, y + 21, str(i + 1), 14,
                        TEXT if i == 0 else SUBTLE, weight=700, anchor="middle"))
    # header
    y = 104
    out.append(text(m, y, "Emberfall", 18, TEXT, weight=800))
    out.append(text(SCREEN_W - m, y, "30 / 50", 14, MONEY, weight=700, anchor="end", family=MONO))
    out.append(progress(defs, m, y + 10, SCREEN_W - 2 * m, 30 / 50, ELEMENT["fire"][1]))
    # filter chips
    y = 138
    chips = [("Dupes", False), ("Foils", True), ("Rare+", False)]
    cw = (SCREEN_W - 2 * m - 16) / 3
    for i, (name, on) in enumerate(chips):
        cx = m + (cw + 8) * i
        if on:
            g = defs.linear([("0%", "#3b82f6", "1"), ("100%", "#6d5cf7", "1")], x1=0, y1=0, x2=1, y2=0)
            out.append(rrect(cx, y, cw, 34, 11, grad=g))
        else:
            out.append(rrect(cx, y, cw, 34, 11, fill=BG0, stroke=STROKE, sw=1, opacity=0.9))
        out.append(text(cx + cw / 2, y + 22, name, 13, "#ffffff" if on else SUBTLE, weight=700, anchor="middle"))

    # grid: 3 columns
    y0 = 190
    gap = 12
    col_w = (SCREEN_W - 2 * m - 2 * gap) / 3
    # owned pattern with real art; some foils / dupes / locked
    layout = [
        ("S1-001", None, 0), ("S1-002", None, 2), ("S1-003", "foil", 0),
        ("S1-006", None, 0), ("S1-007", None, 0), ("S1-050", "ultra", 0),
        ("S1-018", None, 3), ("S1-021", None, 0), (None, None, 0),
        ("S1-030", None, 0), (None, None, 0), ("S1-049", None, 0),
    ]
    idx = 0
    for row in range(4):
        for col in range(3):
            cid, tag, dupes = layout[idx]
            idx += 1
            x = m + (col_w + gap) * col
            yy = y0 + (col_w * 1.4 + 14) * row
            if cid is None:
                out.append(locked_card(defs, x, yy, col_w, _CARDS["S1-%03d" % (idx + 8)]))
            else:
                foil = tag == "foil"
                out.append(full_card(defs, x, yy, col_w, cid, foil=foil))
                if dupes > 1:
                    bw = 26
                    out.append(rrect(x + col_w - bw - 6, yy + 6, bw, 16, 8, fill=BG0, stroke=STROKE, sw=1, opacity=0.85))
                    out.append(text(x + col_w - bw / 2 - 6, yy + 18, "\u00d7%d" % dupes, 11, "#ffffff", weight=900, anchor="middle"))
    return "".join(out)


def screen_grade(defs):
    # Card detail dimmed under a PSA-10 grade reveal popup.
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", BG1, "1"), ("100%", BG0, "1")]))]
    # faint detail behind
    out.append(full_card(defs, SCREEN_W / 2 - 110, 90, 220, "S1-049", grade=10))
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, fill="#000000", opacity=0.72))

    # popup
    pw, ph = 320, 300
    px, py = (SCREEN_W - pw) / 2, 250
    out.append(rrect(px, py, pw, ph, 22, fill=PANEL, stroke=STROKE, sw=1))
    cx = SCREEN_W / 2
    out.append(text(cx, py + 40, "GRADED", 13, SUBTLE, weight=900, anchor="middle", tracking=3))
    out.append(text(cx, py + 108, "PSA 10", 60, "#ffd54a", weight=900, anchor="middle"))
    out.append(text(cx, py + 138, "Gem Mint", 13, TEXT, weight=700, anchor="middle"))
    # was -> now
    out.append(text(cx - 70, py + 176, "Was", 10, SUBTLE, weight=700, anchor="middle"))
    out.append(text(cx - 70, py + 198, "$42.00", 16, SUBTLE, weight=800, anchor="middle"))
    out.append(text(cx, py + 192, "\u2192", 16, SUBTLE, weight=700, anchor="middle"))
    out.append(text(cx + 70, py + 176, "Now", 10, SUBTLE, weight=700, anchor="middle"))
    out.append(text(cx + 70, py + 198, "$210.00", 16, MONEY, weight=800, anchor="middle"))
    out.append(text(cx, py + 232, "\u25b2 Value up!", 13, MONEY, weight=800, anchor="middle"))
    out.append(rrect(cx - 70, py + 250, 140, 36, 18, fill=PANEL_HI))
    out.append(text(cx, py + 273, "Continue", 15, "#ffffff", weight=700, anchor="middle"))
    return "".join(out)


def screen_pack_sealed(defs):
    """A fresh, unopened booster pack waiting to be torn open."""
    ele = SET_ELEMENT[1]
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0, fill=BG0)]
    glow = defs.radial([("0%", ELEMENT[ele][2], "0.45"), ("100%", ELEMENT[ele][2], "0")], cy=0.46, r=0.72)
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, grad=glow))
    cx = SCREEN_W / 2

    out.append(text(cx, 150, "NEW PACK", 14, ELEMENT[ele][0], weight=900, anchor="middle", tracking=4))
    out.append(text(cx, 186, "%s Booster" % SET_NAME[1], 25, TEXT, weight=900, anchor="middle"))

    # rotating glow burst behind the pack
    cy = 440
    burst = defs.radial([("0%", ELEMENT[ele][1], "0.5"), ("70%", ELEMENT[ele][1], "0")], r=0.5)
    out.append(circle(cx, cy, 210, grad=burst))
    for i in range(14):
        a = i / 14 * 2 * math.pi
        out.append(line(cx, cy, cx + math.cos(a) * 235, cy + math.sin(a) * 235,
                        ELEMENT[ele][0], 5, opacity=0.10))

    # the sealed pack, large and centred
    pw = 188
    out.append(pack_thumb(defs, cx - pw / 2, cy - pw * 1.47 / 2, pw, 1))

    # sparkle particles
    import hashlib
    seed = int(hashlib.md5(b"sealed").hexdigest(), 16)
    cols = ["#ffd15c", "#ff7a1a", "#ffe6b0", "#ffffff"]
    for i in range(22):
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        a = (seed % 1000) / 1000 * 2 * math.pi
        seed = (1103515245 * seed + 12345) & 0x7FFFFFFF
        dist = 130 + (seed % 120)
        out.append(circle(cx + math.cos(a) * dist, cy + math.sin(a) * dist * 0.9,
                          2 + (seed % 4), fill=cols[i % len(cols)], opacity=0.8))

    out.append(text(cx, 690, "6 cards inside", 14, SUBTLE, weight=600, anchor="middle"))
    g = defs.linear([("0%", ELEMENT[ele][1], "1"), ("100%", ELEMENT[ele][2], "1")], x1=0, y1=0, x2=1, y2=0)
    out.append(rrect(cx - 116, 712, 232, 46, 23, grad=g))
    out.append(text(cx, 741, "Tap to tear it open", 16, "#ffffff", weight=800, anchor="middle"))
    return "".join(out)


def screen_pack_summary(defs):
    """The post-pack summary: some new, some duplicates, keep-or-sell in reach."""
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", BG1, "1"), ("100%", BG0, "1")]))]
    m = 16
    cx = SCREEN_W / 2
    out.append(text(cx, 92, "Pack Opened", 24, TEXT, weight=900, anchor="middle"))
    out.append(text(cx, 118, "3 new \u00b7 3 duplicates", 13, SUBTLE, weight=600, anchor="middle"))

    gap = 12
    col_w = (SCREEN_W - 2 * m - 2 * gap) / 3
    y0 = 150
    pulls = [("S1-011", True), ("S1-024", False), ("S1-003", True),
             ("S1-007", False), ("S1-031", True), ("S1-018", False)]
    for idx, (cid, is_new) in enumerate(pulls):
        row, col = divmod(idx, 3)
        x = m + (col_w + gap) * col
        yy = y0 + (col_w * 1.4 + 30) * row
        out.append(full_card(defs, x, yy, col_w, cid, foil=(cid == "S1-003")))
        chip_w = col_w * 0.66
        ty = yy + col_w * 1.4 + 8
        if is_new:
            g = defs.linear([("0%", "#5be08a", "1"), ("100%", "#2c9c5c", "1")], x1=0, y1=0, x2=1, y2=0)
            out.append(rrect(x + (col_w - chip_w) / 2, ty, chip_w, 18, 9, grad=g))
            out.append(text(x + col_w / 2, ty + 13, "NEW", 11, "#06301b", weight=900, anchor="middle"))
        else:
            out.append(rrect(x + (col_w - chip_w) / 2, ty, chip_w, 18, 9, fill=BG0, stroke=STROKE, sw=1))
            out.append(text(x + col_w / 2, ty + 13, "DUPLICATE", 9.5, SUBTLE, weight=800, anchor="middle"))

    # keep-or-sell action bar
    by = 702
    out.append(text(m, by - 14, "Duplicates on the buylist", 12, SUBTLE, weight=600))
    out.append(text(SCREEN_W - m, by - 14, "+$4.10", 13, MONEY, weight=800, anchor="end"))
    bw = (SCREEN_W - 2 * m - 12) / 2
    out.append(rrect(m, by, bw, 52, 14, fill=PANEL_HI, stroke=STROKE, sw=1))
    out.append(text(m + bw / 2, by + 31, "Keep all", 15, TEXT, weight=800, anchor="middle"))
    g = defs.linear([("0%", MONEY, "1"), ("100%", "#2c9c5c", "1")], x1=0, y1=0, x2=1, y2=0)
    out.append(rrect(m + bw + 12, by, bw, 52, 14, grad=g))
    out.append(text(m + bw + 12 + bw / 2, by + 23, "Sell 3 duplicates", 14, "#06301b", weight=800, anchor="middle"))
    out.append(text(m + bw + 12 + bw / 2, by + 41, "+$4.10", 12, "#06301b", weight=800, anchor="middle"))
    return "".join(out)


def screen_evolution(defs):
    """A completed three-stage evolution line and its cash bonus."""
    ele = "fire"
    line_ids = ["S1-001", "S1-002", "S1-003"]
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", "#1a1208", "1"), ("100%", BG0, "1")]))]
    glow = defs.radial([("0%", ELEMENT[ele][2], "0.35"), ("100%", ELEMENT[ele][2], "0")], cy=0.34, r=0.7)
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, grad=glow))
    cx = SCREEN_W / 2

    out.append(text(cx, 118, "EVOLUTION LINE", 14, ELEMENT[ele][0], weight=900, anchor="middle", tracking=3))
    out.append(text(cx, 152, "Line Complete!", 27, TEXT, weight=900, anchor="middle"))

    # three cards, arrows between them
    m = 16
    cw = (SCREEN_W - 2 * m - 2 * 22) / 3
    cy = 200
    xs = [m + (cw + 22) * i for i in range(3)]
    for i, cid in enumerate(line_ids):
        out.append(full_card(defs, xs[i], cy, cw, cid, foil=(i == 2)))
        out.append(text(xs[i] + cw / 2, cy + cw * 1.4 + 20, "Stage %d" % (i + 1), 11,
                        SUBTLE, weight=700, anchor="middle"))
    arrow_y = cy + cw * 1.4 / 2 + 6
    for i in range(2):
        out.append(text(xs[i] + cw + 11, arrow_y, "\u2192", 22, ELEMENT[ele][0], weight=900, anchor="middle"))

    # bonus payout panel
    by = 428
    out.append(panel(defs, m, by, SCREEN_W - 2 * m, 150))
    out.append(text(cx, by + 40, "Evolution bonus", 15, TEXT, weight=800, anchor="middle"))
    out.append(text(cx, by + 96, "+$25.00", 46, MONEY, weight=900, anchor="middle"))
    out.append(text(cx, by + 128, "Emberpup \u2192 Cinderhound \u2192 Pyrewolf", 12, SUBTLE, weight=600, anchor="middle"))

    g = defs.linear([("0%", ELEMENT[ele][1], "1"), ("100%", ELEMENT[ele][2], "1")], x1=0, y1=0, x2=1, y2=0)
    out.append(rrect(m, 622, SCREEN_W - 2 * m, 50, 14, grad=g))
    out.append(text(cx, 653, "Keep collecting", 16, "#ffffff", weight=800, anchor="middle"))
    return "".join(out)


def screen_set_complete(defs):
    """A full set finished — 50/50 — and the completion bonus it pays out."""
    set_no = 1
    ele = SET_ELEMENT[set_no]
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", _mix(ELEMENT[ele][3], BG0, 0.35), "1"), ("100%", BG0, "1")]))]
    glow = defs.radial([("0%", ELEMENT[ele][1], "0.40"), ("100%", ELEMENT[ele][1], "0")], cy=0.12, r=0.72)
    out.append(rrect(0, 0, SCREEN_W, 520, 0, grad=glow))
    cx = SCREEN_W / 2
    m = 16

    out.append(text(cx, 122, "\U0001F3C6", 58, "#ffffff", anchor="middle"))
    out.append(text(cx, 164, "SET COMPLETE", 14, "#ffd54a", weight=900, anchor="middle", tracking=3))
    out.append(text(cx, 198, SET_NAME[set_no], 30, "#ffffff", weight=900, anchor="middle"))
    out.append(text(cx, 224, "Every card in the set is yours.", 13, SUBTLE, weight=500, anchor="middle"))

    out.append(progress(defs, m, 244, SCREEN_W - 2 * m, 1.0, ELEMENT[ele][1], h=10))
    out.append(text(cx, 278, "50 / 50 collected", 13, MONEY, weight=800, anchor="middle", family=MONO))

    by = 302
    out.append(panel(defs, m, by, SCREEN_W - 2 * m, 116))
    out.append(text(cx, by + 36, "SET COMPLETION BONUS", 12, SUBTLE, weight=900, anchor="middle", tracking=2))
    out.append(text(cx, by + 90, "+$500.00", 44, MONEY, weight=900, anchor="middle"))

    # a strip of the set's showcase cards
    sy = 448
    ids = ["S1-048", "S1-049", "S1-050"]
    sw = (SCREEN_W - 2 * m - 2 * 14) / 3
    for i, cid in enumerate(ids):
        out.append(full_card(defs, m + (sw + 14) * i, sy, sw, cid, foil=(i == 2)))

    g = defs.linear([("0%", ELEMENT[ele][1], "1"), ("100%", ELEMENT[ele][2], "1")], x1=0, y1=0, x2=1, y2=0)
    out.append(rrect(m, 724, SCREEN_W - 2 * m, 50, 14, grad=g))
    out.append(text(cx, 755, "On to the next set", 16, "#ffffff", weight=800, anchor="middle"))
    return "".join(out)


def screen_run_failed(defs):
    """The run's over: broke, with nothing left to sell — but the stats stand."""
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", "#1a0e0e", "1"), ("100%", BG0, "1")]))]
    glow = defs.radial([("0%", "#e01f1f", "0.26"), ("100%", "#e01f1f", "0")], cy=0.2, r=0.72)
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, grad=glow))
    cx = SCREEN_W / 2
    m = 16

    out.append(text(cx, 150, "\U0001F4B8", 60, "#ffffff", anchor="middle"))
    out.append(text(cx, 198, "TAPPED OUT", 14, "#ff6b6b", weight=900, anchor="middle", tracking=3))
    out.append(text(cx, 234, "You went broke.", 27, "#ffffff", weight=900, anchor="middle"))
    out.append(text(cx, 262, "No cash left, and nothing to sell.", 13, SUBTLE, weight=500, anchor="middle"))

    tw = (SCREEN_W - 2 * m - 24) / 3
    out.append(stat_tile(m, 292, tw, "$0.00", "Wallet", "#ff6b6b"))
    out.append(stat_tile(m + tw + 12, 292, tw, "63", "Packs"))
    out.append(stat_tile(m + 2 * (tw + 12), 292, tw, "58", "Unique"))
    out.append(stat_tile(m, 370, tw, "12", "Rares", "#3b82f6"))
    out.append(stat_tile(m + tw + 12, 370, tw, "2", "Ultras", "#b06cf7"))
    out.append(stat_tile(m + 2 * (tw + 12), 370, tw, "PSA 9", "Best Grade", "#ffd54a"))

    out.append(text(cx, 476, "YOUR BEST PULL", 12, SUBTLE, weight=900, anchor="middle", tracking=2))
    cw = 150
    out.append(full_card(defs, cx - cw / 2, 490, cw, "S1-050", foil=True))

    g = defs.linear([("0%", "#ff7a1a", "1"), ("100%", "#e01f1f", "1")], x1=0, y1=0, x2=1, y2=0)
    out.append(rrect(m, 760, SCREEN_W - 2 * m, 52, 14, grad=g))
    out.append(text(cx, 792, "Try again", 16, "#ffffff", weight=800, anchor="middle"))
    return "".join(out)


def screen_challenge(defs):
    """The hook: an epic collage of overlapping card art from every set."""
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", "#160b26", "1"), ("55%", BG0, "1"), ("100%", "#05070c", "1")]))]
    cx = SCREEN_W / 2

    # a fan of ultra cards, one from each of the five sets, overlapping —
    # drawn back-to-front so the set-1 hero lands on top.
    fan = [
        ("S3-050", cx - 122, 452, 148, -24),
        ("S4-050", cx + 122, 452, 148, 24),
        ("S2-050", cx - 72, 408, 166, -11),
        ("S5-050", cx + 72, 408, 166, 11),
        ("S1-050", cx, 380, 188, 0),
    ]
    for cid, ccx, ccy, w, ang in fan:
        out.append(placed_card(defs, ccx, ccy, w, cid, angle=ang, foil=True))

    # darken the edges and the lower third so the challenge text reads cleanly
    vg = defs.radial([("0%", "#000000", "0"), ("100%", "#000000", "0.5")], r=0.78)
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, grad=vg))
    fade = defs.linear([("0%", "#05070c", "0"), ("55%", "#05070c", "0.86"), ("100%", "#05070c", "1")])
    out.append(rrect(0, 556, SCREEN_W, SCREEN_H - 556, 0, grad=fade))

    out.append(text(cx, 120, "THE CHALLENGE", 14, "#c6a3ff", weight=900, anchor="middle", tracking=5))
    out.append(text(cx, 640, "Acquire", 35, "#ffffff", weight=900, anchor="middle"))
    out.append(text(cx, 680, "them all.", 35, "#ffffff", weight=900, anchor="middle"))
    out.append(text(cx, 714, "All 250 Sprytes. All five sets. One binder.", 14, "#d9b3ff",
                    weight=600, anchor="middle"))

    g = defs.linear([("0%", "#b06cf7", "1"), ("100%", "#6d5cf7", "1")], x1=0, y1=0, x2=1, y2=0)
    out.append(rrect(cx - 122, 740, 244, 52, 26, grad=g))
    out.append(text(cx, 772, "Start Collecting", 16, "#ffffff", weight=800, anchor="middle"))
    return "".join(out)


# id, screen fn, caption, subtitle, background-accent element. The numeric
# prefixes fix the App Store upload order; the list is exactly ten scenes, one
# per screenshot slot.
SCENES = [
    ("01_pack_sealed", screen_pack_sealed, "Crack open a fresh pack.",
     "Every booster is six cards \u2014 and maybe the hit you're chasing.", "fire"),
    ("02_rare_hit", screen_reveal, "Every pull is a thrill.",
     "Flip cards one by one and chase rares, foils and ultras.", "water"),
    ("03_home_progress", screen_shop, "Start with $100. Rip packs.",
     "Buy across five sets and watch your binder fill in \u2014 without going broke.", "fire"),
    ("04_pack_summary", screen_pack_summary, "Keep it \u2014 or cash it in.",
     "Sell the duplicates on the buylist to fund your next pack.", "grass"),
    ("05_collection", screen_collection, "Fill in every set.",
     "Hunt down all 50 cards in the first set, then four more.", "fire"),
    ("06_grade", screen_grade, "Grade your best pulls.",
     "Send rares to grading and roll for a jackpot PSA 10.", "shadow"),
    ("07_evolution", screen_evolution, "Complete evolution lines.",
     "Chain a full line together for an instant cash bonus.", "fire"),
    ("08_set_complete", screen_set_complete, "Finish a set for a bonus.",
     "Collect all 50 and bank a big set-completion payout.", "fire"),
    ("09_run_failed", screen_run_failed, "Don't go broke.",
     "Run out of cash with nothing left to sell and the run is over.", "fire"),
    ("10_challenge", screen_challenge, "Do you have what it takes?",
     "The whole set is waiting \u2014 every rare, every foil, every line.", "shadow"),
]


# ----------------------------------------------------------------- composition

def device(defs, W, H, screen_svg, caption, subtitle, accent):
    """Compose a scene: gradient bg + caption + a floating phone showing the screen."""
    out = []
    # background gradient + glow
    bg = defs.linear([("0%", _mix(accent, BG0, 0.55), "1"), ("55%", BG0, "1"), ("100%", "#05070c", "1")])
    out.append(rrect(0, 0, W, H, 0, grad=bg))
    gl = defs.radial([("0%", accent, "0.30"), ("60%", accent, "0")], cy=0.32, r=0.75)
    out.append(rrect(0, 0, W, H, 0, grad=gl))
    # faint sparkles
    s = 0x2545F491 ^ (W * 7)
    for _ in range(40):
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        x = s % W
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        y = s % H
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        r = 1 + s % 2
        out.append(circle(x, y, r, fill="#ffffff", opacity=0.06))

    # caption
    cx = W / 2
    cap_size = W * 0.062
    lines = wrap(caption, 22)
    cap_y = H * 0.075
    for i, ln in enumerate(lines):
        out.append(text(cx, cap_y + i * cap_size * 1.12, ln, cap_size, "#ffffff", weight=900, anchor="middle"))
    sub_y = cap_y + len(lines) * cap_size * 1.12 + W * 0.012
    sub_lines = wrap(subtitle, 46)
    for i, ln in enumerate(sub_lines):
        out.append(text(cx, sub_y + i * (W * 0.032), ln, W * 0.028, accent, weight=600, anchor="middle", opacity=0.95))
    caption_bottom = sub_y + len(sub_lines) * (W * 0.032)

    # device geometry — fit the phone into the space left below the caption so it
    # never overflows. This matters on the squarer iPad canvas, where fitting by
    # width alone would run the tall phone off the bottom. Fit by width AND
    # height, then centre it in the leftover area.
    bezel_ratio = 0.026
    height_factor = (1 - 2 * bezel_ratio) * (SCREEN_H / SCREEN_W) + 2 * bezel_ratio
    top = caption_bottom + H * 0.03
    bottom_margin = H * 0.045
    avail_h = H - top - bottom_margin
    dev_w = min(W * 0.78, avail_h / height_factor)
    bezel = dev_w * bezel_ratio
    scr_w = dev_w - 2 * bezel
    scr_h = scr_w * (SCREEN_H / SCREEN_W)
    dev_h = scr_h + 2 * bezel
    dev_x = (W - dev_w) / 2
    dev_y = top + (avail_h - dev_h) / 2
    dev_r = dev_w * 0.11
    scr_r = dev_r - bezel

    # shadow + body
    out.append(rrect(dev_x, dev_y + 18, dev_w, dev_h, dev_r, fill="#000000", opacity=0.35))
    out.append(rrect(dev_x, dev_y, dev_w, dev_h, dev_r, fill="#05070b", stroke="#2b3345", sw=bezel * 0.5))

    # screen: scale the 393x852 screen group into the screen rect
    scr_x, scr_y = dev_x + bezel, dev_y + bezel
    clip = defs.clip_rrect(scr_x, scr_y, scr_w, scr_h, scr_r)
    k = scr_w / SCREEN_W
    out.append('<g clip-path="url(#%s)"><g transform="translate(%.2f,%.2f) scale(%.4f)">%s</g></g>' % (
        clip, scr_x, scr_y, k, screen_svg))

    # dynamic island + screen glare
    isl_w, isl_h = dev_w * 0.30, dev_w * 0.085
    out.append(rrect(cx - isl_w / 2, scr_y + bezel * 0.7, isl_w, isl_h, isl_h / 2, fill="#000000"))
    glare = defs.linear([("0%", "#ffffff", "0.10"), ("40%", "#ffffff", "0.02"), ("100%", "#ffffff", "0")], x1=0, y1=0, x2=1, y2=1)
    out.append('<g clip-path="url(#%s)">%s</g>' % (clip, rrect(scr_x, scr_y, scr_w, scr_h * 0.5, 0, grad=glare)))
    return "".join(out)


def _hex(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    ra, ga, ba = _hex(a)
    rb, gb, bb = _hex(b)
    return "#%02x%02x%02x" % (int(ra + (rb - ra) * t), int(ga + (gb - ga) * t), int(ba + (bb - ba) * t))


def render(scene_id, fn, caption, subtitle, accent_elem, W, H):
    defs = Defs()
    screen = fn(defs)
    accent = ELEMENT[accent_elem][2]
    body = device(defs, W, H, screen, caption, subtitle, accent)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
           'width="%d" height="%d" viewBox="0 0 %d %d">%s%s</svg>') % (
        W, H, W, H, defs.render(), body)
    out_png = os.path.join(OUT_DIR, "%s_%dx%d.png" % (scene_id, W, H))
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
        tmp = f.name
    subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", out_png, tmp], check=True)
    os.unlink(tmp)
    return out_png


def main():
    if "--list" in sys.argv:
        print("Scenes:")
        for sid, _fn, cap, _sub, _accent in SCENES:
            print("  %-16s %s" % (sid, cap))
        print("Sizes:", ", ".join("%dx%d" % s for s in SIZES))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Rendering %d scenes x %d sizes -> %s" % (len(SCENES), len(SIZES), OUT_DIR))
    for sid, fn, cap, sub, accent_elem in SCENES:
        for (W, H) in SIZES:
            p = render(sid, fn, cap, sub, accent_elem, W, H)
            print("  %s" % os.path.relpath(p, ROOT))
    print("Done.")


if __name__ == "__main__":
    main()
