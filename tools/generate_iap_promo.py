#!/usr/bin/env python3
"""Generate the App Store promotional image for the "Full Collection" IAP.

App Store Connect shows a single 1024x1024 image to represent an in-app
purchase (promoted IAP on the product page, offer-code redemption, win-back
offers). It is displayed in every region, so this art carries no localizable
marketing copy — it says "unlock everything" purely visually: a fan of the five
set signature legendaries, one per element (Emberfall fire -> Umbral Reach
shadow), drawn with the exact same art engine that draws the cards in-game, so
the promo can never drift from the real artwork.

Reuses `tools/generate_art.py` for every creature and scene, the same way
`tools/generate_icon.py` reuses it for the app icon. Stdlib-only Python 3 plus
`rsvg-convert` from librsvg (`brew install librsvg`) — no Pillow, no pip.

    python3 tools/generate_iap_promo.py

Writes: docs/app-store/iap-full-unlock-1024.png

Apple's requirements for this image, all enforced below before it is written:
JPG or PNG, 1024x1024, 72 dpi, RGB, flattened (no alpha), no rounded corners.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import generate_art as art  # noqa: E402
from pngutil import PNG  # noqa: E402

OUT_SIZE = 1024
DPI = 72
# 72 dpi expressed as pixels-per-metre for the PNG pHYs chunk (72 / 0.0254).
PPM = round(DPI / 0.0254)
DARKEST = "#080a10"  # corner colour, and what the PNG is flattened onto

# One signature ultra legendary per set, in set order. Their elements span the
# whole spectrum, which is what reads as "every set is here".
HEROES = ["Ignarok", "Abyssos", "Sylvareth", "Fulguros", "Nyxaros"]

# Card geometry, in the 1024 canvas' own units.
CW, CH, PAD, RAD = 300.0, 420.0, 16.0, 22.0
AWIN_W = CW - 2 * PAD                     # art window width
AWIN_H = AWIN_W * art.VB_H / art.VB_W     # keep the 216:150 aspect (no squash)

# The hand is fanned about a pivot below the canvas, like cards held in a hand.
PIVOT = (512.0, 1016.0)
LIFT = 732.0
ANGLES = [-22.0, -11.0, 0.0, 11.0, 22.0]

BY_NAME = {c["name"]: c for c in art.CARDS}


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def hero_card(card, idx, is_front):
    """One trading-card group drawn at the origin. Every card shows its art
    window plus an always-visible set badge on its exposed top-left corner; the
    front (top) card additionally carries the full nameplate, so the fan reads
    as one hero and its four set-mates instead of four cards with clipped text.
    Set/element accents come straight from the art engine."""
    ele = art.ELE[card["element"]]
    glow = ele["glow"]
    pal = ele["pal"]
    setno = card["set"]
    setname = art.SETSTYLE[setno]["name"]
    uid = f"promo{idx}"

    # Art window: the real in-game defs + scene + creature, scaled to fit.
    inner = art.art_inner(card)
    art_w, art_h = AWIN_W, AWIN_H

    s = []
    # Card body: element-tinted border over a dark panel.
    s.append(f'''<defs>
      <linearGradient id="bord{uid}" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0%" stop-color="{pal[0]}"/>
        <stop offset="55%" stop-color="{pal[1]}"/>
        <stop offset="100%" stop-color="{pal[2]}"/>
      </linearGradient>
      <linearGradient id="face{uid}" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0%" stop-color="#141b28"/>
        <stop offset="100%" stop-color="#0c111b"/>
      </linearGradient>
      <clipPath id="awin{uid}">
        <rect x="{PAD}" y="{PAD}" width="{art_w}" height="{art_h}" rx="10"/>
      </clipPath>
    </defs>''')
    s.append(f'<rect x="-4" y="-4" width="{CW + 8}" height="{CH + 8}" rx="{RAD + 3}" '
             f'fill="url(#bord{uid})"/>')
    s.append(f'<rect x="0" y="0" width="{CW}" height="{CH}" rx="{RAD}" fill="url(#face{uid})"/>')

    # Art window.
    s.append(f'<g clip-path="url(#awin{uid})">'
             f'<svg x="{PAD}" y="{PAD}" width="{art_w}" height="{art_h}" '
             f'viewBox="0 0 {art.VB_W} {art.VB_H}" preserveAspectRatio="xMidYMid slice">'
             f'{inner}</svg></g>')
    s.append(f'<rect x="{PAD}" y="{PAD}" width="{art_w}" height="{art_h}" rx="10" '
             f'fill="none" stroke="#00000055" stroke-width="1.5"/>')

    # Set badge, on the exposed top-left corner of every card in the fan.
    bx, by = PAD + 20, PAD + 20
    s.append(f'<circle cx="{bx}" cy="{by}" r="18" fill="{glow}" stroke="#0b0e14" stroke-width="2.5"/>')
    s.append(f'<text x="{bx}" y="{by + 7}" text-anchor="middle" '
             f'font-family="Helvetica,Arial,sans-serif" font-size="22" font-weight="800" '
             f'fill="#10151f">{setno}</text>')

    if is_front:
        tx = PAD + 6
        # Creature name.
        s.append(f'<text x="{tx}" y="{PAD + art_h + 48}" font-family="Helvetica,Arial,sans-serif" '
                 f'font-size="30" font-weight="700" fill="{glow}">{esc(card["name"])}</text>')
        # Set line.
        s.append(f'<text x="{tx}" y="{PAD + art_h + 74}" font-family="Helvetica,Arial,sans-serif" '
                 f'font-size="14" letter-spacing="2" font-weight="600" fill="#8a94a6">'
                 f'SET {setno} \u00b7 {esc(setname).upper()}</text>')

        # Legendary gem + label, bottom-left; collector number bottom-right.
        gy = CH - 30
        s.append(f'''<defs><linearGradient id="gem{uid}" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0%" stop-color="#ffd54a"/>
            <stop offset="55%" stop-color="#ff8ad6"/>
            <stop offset="100%" stop-color="#b06cf7"/>
          </linearGradient></defs>''')
        gx = tx + 8
        s.append(f'<path d="M {gx} {gy - 10} L {gx + 9} {gy} L {gx} {gy + 10} L {gx - 9} {gy} Z" '
                 f'fill="url(#gem{uid})" stroke="#00000055" stroke-width="1"/>')
        s.append(f'<text x="{gx + 18}" y="{gy + 5}" font-family="Helvetica,Arial,sans-serif" '
                 f'font-size="15" letter-spacing="2.5" font-weight="700" fill="#ffd54a">LEGENDARY</text>')
        s.append(f'<text x="{CW - PAD - 6}" y="{gy + 5}" text-anchor="end" '
                 f'font-family="Helvetica,Arial,sans-serif" font-size="15" font-weight="600" '
                 f'fill="#7a8497">No.{card["number"]:03d}</text>')

    body = "".join(s)
    a = ANGLES[idx]
    transform = (f'translate({PIVOT[0]},{PIVOT[1]}) rotate({a}) '
                 f'translate({-CW / 2},{-LIFT})')
    return f'<g transform="{transform}" filter="url(#cardshadow)">{body}</g>'


def background():
    random.seed(1024)
    stars = []
    for _ in range(90):
        x, y = random.uniform(0, OUT_SIZE), random.uniform(0, OUT_SIZE * 0.72)
        r = random.uniform(0.6, 2.4)
        o = random.uniform(0.15, 0.85)
        stars.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r:.2f}" fill="#ffffff" opacity="{o:.2f}"/>')
    starstr = "".join(stars)

    # Faint, wider back-fan of element-tinted card silhouettes: implies the full
    # 250-card deck sitting behind the five heroes.
    backs = []
    back_angles = [-40, -30, -20, 20, 30, 40]
    glows = [art.ELE[art.SETS[(i) % 5]["element"]]["glow"] for i in range(6)]
    for j, a in enumerate(back_angles):
        g = glows[j]
        t = (f'translate({PIVOT[0]},{PIVOT[1] + 8}) rotate({a}) '
             f'translate({-CW * 0.42},{-LIFT + 26})')
        backs.append(
            f'<g transform="{t}" opacity="0.30">'
            f'<rect x="0" y="0" width="{CW * 0.84:.0f}" height="{CH * 0.9:.0f}" rx="20" '
            f'fill="#0f1420" stroke="{g}" stroke-width="2"/>'
            f'<rect x="{CW * 0.30:.0f}" y="{CH * 0.34:.0f}" width="{CW * 0.24:.0f}" '
            f'height="{CW * 0.24:.0f}" rx="6" transform="rotate(45 {CW*0.42:.0f} {CH*0.45:.0f})" '
            f'fill="none" stroke="{g}" stroke-width="2" opacity="0.7"/></g>')
    backstr = "".join(backs)

    return f'''
  <defs>
    <radialGradient id="sky" cx="50%" cy="30%" r="85%">
      <stop offset="0%" stop-color="#1b2440"/>
      <stop offset="42%" stop-color="#111a30"/>
      <stop offset="100%" stop-color="{DARKEST}"/>
    </radialGradient>
    <radialGradient id="violet" cx="50%" cy="6%" r="60%">
      <stop offset="0%" stop-color="#7a4fd0" stop-opacity="0.55"/>
      <stop offset="100%" stop-color="#7a4fd0" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="warm" cx="50%" cy="70%" r="55%">
      <stop offset="0%" stop-color="#ff9a3c" stop-opacity="0.42"/>
      <stop offset="55%" stop-color="#ff6a1a" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#ff6a1a" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="vig" cx="50%" cy="46%" r="72%">
      <stop offset="52%" stop-color="{DARKEST}" stop-opacity="0"/>
      <stop offset="100%" stop-color="{DARKEST}" stop-opacity="0.85"/>
    </radialGradient>
    <filter id="cardshadow" x="-30%" y="-30%" width="160%" height="160%">
      <feDropShadow dx="0" dy="10" stdDeviation="16" flood-color="#000000" flood-opacity="0.55"/>
    </filter>
  </defs>
  <rect width="{OUT_SIZE}" height="{OUT_SIZE}" fill="url(#sky)"/>
  <rect width="{OUT_SIZE}" height="{OUT_SIZE}" fill="url(#violet)"/>
  {starstr}
  <rect width="{OUT_SIZE}" height="{OUT_SIZE}" fill="url(#warm)"/>
  {backstr}'''


def wordmark():
    """Small, universal brand mark. The app's own name is not region-specific."""
    return (f'<text x="{OUT_SIZE/2}" y="86" text-anchor="middle" '
            f'font-family="Helvetica,Arial,sans-serif" font-size="46" font-weight="800" '
            f'letter-spacing="6" fill="#eef3fb">TRADING UP</text>')


def promo_svg():
    heroes = "".join(hero_card(BY_NAME[n], i, i == len(HEROES) - 1)
                     for i, n in enumerate(HEROES))
    vignette = f'<rect width="{OUT_SIZE}" height="{OUT_SIZE}" fill="url(#vig)"/>'
    body = background() + heroes + vignette + wordmark()
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {OUT_SIZE} {OUT_SIZE}" '
            f'width="{OUT_SIZE}" height="{OUT_SIZE}">{body}</svg>')


def set_dpi(path, ppm):
    """Rewrite the PNG with a pHYs chunk declaring `ppm` pixels/metre on both
    axes, so the file reports exactly 72 dpi. Pure stdlib chunk surgery."""
    with open(path, "rb") as fh:
        data = fh.read()
    sig, rest = data[:8], data[8:]
    out = bytearray(sig)
    phys = struct.pack(">IIB", ppm, ppm, 1)  # x ppu, y ppu, unit = metre
    inserted = False
    off = 0
    while off < len(rest):
        (length,) = struct.unpack(">I", rest[off:off + 4])
        kind = rest[off + 4:off + 8]
        chunk = rest[off:off + 12 + length]
        if kind == b"pHYs":       # drop any existing pHYs, we write our own
            off += 12 + length
            continue
        out += chunk
        if kind == b"IHDR" and not inserted:
            crc = zlib.crc32(b"pHYs" + phys) & 0xFFFFFFFF
            out += struct.pack(">I", len(phys)) + b"pHYs" + phys + struct.pack(">I", crc)
            inserted = True
        off += 12 + length
    with open(path, "wb") as fh:
        fh.write(out)


def main():
    out_dir = os.path.join(ROOT, "docs", "app-store")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "iap-full-unlock-1024.png")

    with tempfile.TemporaryDirectory() as tmp:
        svg = os.path.join(tmp, "promo.svg")
        with open(svg, "w") as fh:
            fh.write(promo_svg())
        # -b flattens onto an opaque colour so the PNG has no alpha channel.
        subprocess.run(["rsvg-convert", "-w", str(OUT_SIZE), "-h", str(OUT_SIZE),
                        "-b", DARKEST, svg, "-o", out], check=True)

    set_dpi(out, PPM)

    img = PNG(out)
    problems = []
    if (img.width, img.height) != (OUT_SIZE, OUT_SIZE):
        problems.append(f"must be {OUT_SIZE}x{OUT_SIZE}, got {img.width}x{img.height}")
    if img.has_alpha:
        problems.append("has an alpha channel — must be flattened RGB")
    if img.color_type != 2:
        problems.append(f"must be RGB (colour type 2), got colour type {img.color_type}")
    if img.bit_depth != 8:
        problems.append(f"must be 8-bit, got {img.bit_depth}")
    if problems:
        raise SystemExit("promo image invalid:\n  - " + "\n  - ".join(problems))

    print(f"wrote {out} ({img.width}x{img.height}, colour type {img.color_type}, "
          f"no alpha, {DPI} dpi)")


if __name__ == "__main__":
    main()
