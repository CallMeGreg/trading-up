#!/usr/bin/env python3
"""App Store marketing screenshots for Trading Up — deterministic, no simulator.

Recreates the app's real screens in SVG using the exact palette, metrics and card
layout from the SwiftUI source (Theme.swift / CardView.swift), embeds the real
generated card art, wraps each screen in a floating device frame with a marketing
caption, and renders everything to PNG at official App Store pixel sizes with
`rsvg-convert` (from librsvg — `brew install librsvg`).

Because it's driven by `data/cards.json` and the checked-in card-art PNGs, the whole
screenshot set regenerates on any machine with just `python3` + `rsvg-convert`, and
stays in sync with the game's real content and styling.

Usage:
  python3 tools/generate_screenshots.py           # render every scene at every size
  python3 tools/generate_screenshots.py --list     # list scenes and output sizes

Output: docs/screenshots/<scene>_<w>x<h>.png
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

# Official App Store portrait sizes (px). 6.9"/6.7" and 6.5" iPhone.
SIZES = [(1290, 2796), (1242, 2688)]

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


# ------------------------------------------------------------- shared UI pieces

def big_button(defs, x, y, w, title, subtitle, colors, icon_box=True):
    h = 52
    g = defs.linear([("0%", colors[0], "1"), ("100%", colors[1], "1")], x1=0, y1=0, x2=1, y2=0)
    out = [rrect(x, y, w, h, 14, grad=g)]
    tx = x + 44
    if icon_box:
        out.append(rrect(x + 14, y + 16, 20, 20, 4, fill="#ffffff", opacity=0.92))
    out.append(text(tx, y + 24, title, 15, "#ffffff", weight=700))
    out.append(text(tx, y + 40, subtitle, 11, "#ffffff", weight=500, opacity=0.85))
    return "".join(out)


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

    # sigil: ring + six spokes, mirroring SigilView
    cx, cy = x + w / 2, top + crimp + fh * 0.42
    rad = w * 0.30
    out.append(circle(cx, cy, rad * 0.78, stroke="#ffffff", sw=1.1, opacity=0.30 * op))
    for i in range(6):
        a = i / 6.0 * 2 * math.pi - math.pi / 2
        out.append(circle(cx + math.cos(a) * rad, cy + math.sin(a) * rad, w * 0.05,
                          fill=pal[0], opacity=0.85 * op))
        out.append(line(cx, cy, cx + math.cos(a) * rad, cy + math.sin(a) * rad,
                        pal[0], 1.4, opacity=0.55 * op))
    out.append(circle(cx, cy, w * 0.09, fill=pal[0], opacity=0.9 * op))

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
    ele = "fire"
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0, fill=BG0)]
    glow = defs.radial([("0%", ELEMENT[ele][2], "0.40"), ("100%", ELEMENT[ele][2], "0")], r=0.7)
    out.append(rrect(0, 0, SCREEN_W, SCREEN_H, 0, grad=glow))

    # progress dots (6 cards, all revealed)
    dots = ["common", "common", "common", "uncommon", "uncommon", "ultra"]
    dw = 16
    total = len(dots) * dw
    x0 = (SCREEN_W - total) / 2
    for i, r in enumerate(dots):
        out.append(circle(x0 + i * dw + dw / 2, 96, 4.5, fill=RARITY_ACCENT[r]))

    # rotating glow burst behind hero card
    cx, cy = SCREEN_W / 2, 400
    burst = defs.radial([("0%", "#ff8ad6", "0.55"), ("70%", "#ff8ad6", "0")], r=0.5)
    out.append(circle(cx, cy, 230, grad=burst))
    for i in range(16):
        a = i / 16 * 2 * math.pi
        x2 = cx + math.cos(a) * 250
        y2 = cy + math.sin(a) * 250
        out.append(line(cx, cy, x2, y2, "#ffd54a", 6, opacity=0.10))

    # hero card: foil ultra
    cw = 230
    out.append(full_card(defs, cx - cw / 2, cy - cw * 0.7, cw, "S1-050", foil=True))

    # sparkle particles
    import hashlib
    seed = int(hashlib.md5(b"S1-050").hexdigest(), 16)
    cols = ["#ffd54a", "#ff8ad6", "#b06cf7", "#ffffff"]
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
    out.append(text(cx, 690, "ULTRA RARE", 15, "#b06cf7", weight=900, anchor="middle", tracking=1))
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


def screen_win(defs):
    out = [rrect(0, 0, SCREEN_W, SCREEN_H, 0,
                 grad=defs.linear([("0%", "#1a1030", "1"), ("100%", BG0, "1")]))]
    glow = defs.radial([("0%", "#b06cf7", "0.40"), ("100%", "#b06cf7", "0")], cy=0.12, r=0.7)
    out.append(rrect(0, 0, SCREEN_W, 500, 0, grad=glow))
    cx = SCREEN_W / 2
    out.append(text(cx, 130, "\U0001F3C6", 76, "#ffffff", anchor="middle"))
    out.append(text(cx, 178, "MASTER COLLECTOR", 14, "#ffd54a", weight=900, anchor="middle", tracking=3))
    out.append(text(cx, 210, "You collected all 250!", 26, "#ffffff", weight=900, anchor="middle"))
    out.append(text(cx, 236, "Every Spryte across all five sets is yours.", 13, SUBTLE, weight=500, anchor="middle"))
    m = 16
    tw = (SCREEN_W - 2 * m - 24) / 3
    out.append(stat_tile(m, 268, tw, "$3.1k", "Net Worth", MONEY))
    out.append(stat_tile(m + tw + 12, 268, tw, "142", "Packs"))
    out.append(stat_tile(m + 2 * (tw + 12), 268, tw, "9", "Boxes"))
    out.append(stat_tile(m, 346, tw, "88", "Foils", "#ff8ad6"))
    out.append(stat_tile(m + tw + 12, 346, tw, "31", "Ultras", "#b06cf7"))
    out.append(stat_tile(m + 2 * (tw + 12), 346, tw, "PSA 10", "Best Grade", "#ffd54a"))
    # complete sets panel
    y = 440
    out.append(panel(defs, m, y, SCREEN_W - 2 * m, 210))
    out.append(text(m + 16, y + 26, "COMPLETE SETS", 12, SUBTLE, weight=900))
    for i in range(5):
        ry = y + 44 + i * 30
        out.append(text(m + 16, ry + 10, SET_NAME[i + 1], 12, TEXT, weight=600))
        out.append(progress(defs, m + 120, ry, 150, 1.0, ELEMENT[SET_ELEMENT[i + 1]][1], h=7))
        out.append(text(SCREEN_W - m - 16, ry + 9, "50/50", 11, MONEY, weight=700, anchor="end", family=MONO))
    out.append(big_button(defs, m, 668, SCREEN_W - 2 * m, "Play Again", "Start a fresh collection",
                          ["#b06cf7", "#6d5cf7"]))
    return "".join(out)


SCENES = [
    ("01_reveal", screen_reveal, "Every pull is a thrill.", "Rip packs and reveal cards one by one \u2014 chase foils and ultra rares."),
    ("02_shop", screen_shop, "Start with $100. Rip packs.", "Buy packs across five sets \u2014 without going broke."),
    ("03_collection", screen_collection, "Collect all 250 Sprytes.", "Five sets, 250 original creatures, foils and dupes to hunt down."),
    ("04_grade", screen_grade, "Grade your best pulls.", "Send rares to grading and roll for a jackpot PSA 10."),
    ("05_win", screen_win, "Build the ultimate collection.", "Complete evolution lines and full sets for big cash bonuses."),
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
    for i, ln in enumerate(wrap(subtitle, 46)):
        out.append(text(cx, sub_y + i * (W * 0.032), ln, W * 0.028, accent, weight=600, anchor="middle", opacity=0.95))

    # device geometry
    dev_w = W * 0.78
    bezel = dev_w * 0.026
    scr_w = dev_w - 2 * bezel
    scr_h = scr_w * (SCREEN_H / SCREEN_W)
    dev_h = scr_h + 2 * bezel
    dev_x = (W - dev_w) / 2
    dev_y = H - dev_h - H * 0.045
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


def render(scene_id, fn, caption, subtitle, W, H):
    defs = Defs()
    screen = fn(defs)
    accent = ELEMENT[{"01_reveal": "fire", "02_shop": "fire", "03_collection": "fire",
                      "04_grade": "shadow", "05_win": "shadow"}[scene_id]][2]
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
        for sid, _, cap, _sub in SCENES:
            print("  %-14s %s" % (sid, cap))
        print("Sizes:", ", ".join("%dx%d" % s for s in SIZES))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Rendering %d scenes x %d sizes -> %s" % (len(SCENES), len(SIZES), OUT_DIR))
    for sid, fn, cap, sub in SCENES:
        for (W, H) in SIZES:
            p = render(sid, fn, cap, sub, W, H)
            print("  %s" % os.path.relpath(p, ROOT))
    print("Done.")


if __name__ == "__main__":
    main()
