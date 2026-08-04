#!/usr/bin/env python3
"""Generate the Trading Up app icon.

The icon is Emberpup — card 001, the first Spryte anyone pulls — drawn with the
exact same code that draws the card art, so the icon and the game can never
drift apart. `tools/generate_art.py` owns the creature; this file only builds a
square Emberfall backdrop around it and renders the result.

The creature's bounding box is measured from a throwaway render rather than
hard-coded, so tweaking the artwork can't silently push the pup off-centre or
crop its tail.

Needs `rsvg-convert` from librsvg (`brew install librsvg`) — the same dependency
`generate_art.py` already has. No Pillow, no other third-party packages.

    python3 tools/generate_icon.py
    python3 tools/check_icon.py     # verify it's submittable

Writes: TradingUp/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import generate_art as art  # noqa: E402
from pngutil import PNG  # noqa: E402

STAR = "Emberpup"
ELEMENT = "fire"
UID = "icon"
VB = 216.0           # square canvas, same unit scale as the card art
OUT_SIZE = 1024
DARKEST = "#140402"  # colour at the corners, and what the PNG is flattened onto

# How much of the canvas the creature spans, and where its centre sits. The pup
# is a wide side profile, so width is the binding dimension.
FILL = 0.63
CENTRE = (0.500, 0.495)


def creature_svg():
    e = art.ELE[ELEMENT]
    role = art.ROLES[STAR]
    ctx = art.Ctx(UID, e, role["set"], art.vary(STAR), STAR)
    body = art.creature(ctx, role)
    return art.defs(ctx) + body


def measure(inner, supersample=4):
    """Bounding box of `inner`, in card-art units, read off its alpha channel."""
    w, h = art.VB_W, art.VB_H
    with tempfile.TemporaryDirectory() as tmp:
        svg, png = os.path.join(tmp, "m.svg"), os.path.join(tmp, "m.png")
        with open(svg, "w") as fh:
            fh.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}">{inner}</svg>')
        subprocess.run(["rsvg-convert", "-w", str(w * supersample), "-h", str(h * supersample),
                        svg, "-o", png], check=True)
        img = PNG(png)
        if img.color_type != 6:
            raise SystemExit("expected RGBA from rsvg-convert while measuring the creature")
        xs, ys = [], []
        for y, row in enumerate(img._decoded()):
            lit = [x for x in range(img.width) if row[x * 4 + 3] > 8]
            if lit:
                ys.append(y)
                xs += [lit[0], lit[-1]]
    if not xs:
        raise SystemExit("nothing rendered while measuring the creature")
    return (min(xs) / supersample, min(ys) / supersample,
            max(xs) / supersample, max(ys) / supersample)


def backdrop():
    """Emberfall reduced to what still reads at 40 points: a warm core to lift
    the pup off the background, and the glow of lava out of frame below him."""
    embers = "".join(
        f'<circle cx="{x}" cy="{y}" r="{r}" fill="#ffcf6a" opacity="{o}"/>'
        for x, y, r, o in [(30, 44, 2.7, .70), (184, 38, 2.3, .62), (52, 20, 1.7, .48),
                           (198, 92, 2.2, .48), (22, 102, 1.7, .42), (150, 18, 1.5, .40)])
    return f"""
  <defs>
    <radialGradient id="sky{UID}" cx="50%" cy="41%" r="76%">
      <stop offset="0%" stop-color="#8f2f12"/>
      <stop offset="42%" stop-color="#431006"/>
      <stop offset="100%" stop-color="{DARKEST}"/>
    </radialGradient>
    <radialGradient id="floor{UID}" cx="50%" cy="100%" r="62%">
      <stop offset="0%" stop-color="#ffbe52" stop-opacity=".95"/>
      <stop offset="45%" stop-color="#ff6a1a" stop-opacity=".55"/>
      <stop offset="100%" stop-color="#ff6a1a" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="spot{UID}" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="#ffd15c" stop-opacity=".42"/>
      <stop offset="100%" stop-color="#ffd15c" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="vig{UID}" cx="50%" cy="46%" r="72%">
      <stop offset="55%" stop-color="{DARKEST}" stop-opacity="0"/>
      <stop offset="100%" stop-color="{DARKEST}" stop-opacity=".55"/>
    </radialGradient>
  </defs>
  <rect width="{VB}" height="{VB}" fill="url(#sky{UID})"/>
  {embers}
  <ellipse cx="{CENTRE[0] * VB:.0f}" cy="{CENTRE[1] * VB:.0f}" rx="96" ry="66" fill="url(#spot{UID})"/>
  <rect x="0" y="158" width="{VB}" height="58" fill="url(#floor{UID})"/>
  <rect width="{VB}" height="{VB}" fill="url(#vig{UID})"/>"""


def icon_svg():
    inner = creature_svg()
    x0, y0, x1, y1 = measure(inner)
    scale = FILL * VB / (x1 - x0)
    tx = CENTRE[0] * VB - (x0 + x1) / 2 * scale
    ty = CENTRE[1] * VB - (y0 + y1) / 2 * scale
    body = backdrop() + f'<g transform="translate({tx:.3f},{ty:.3f}) scale({scale:.5f})">{inner}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {VB:.0f} {VB:.0f}" '
            f'width="{OUT_SIZE}" height="{OUT_SIZE}">{body}</svg>')


def main():
    out_dir = os.path.join(ROOT, "TradingUp", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "icon-1024.png")

    with tempfile.TemporaryDirectory() as tmp:
        svg = os.path.join(tmp, "icon.svg")
        with open(svg, "w") as fh:
            fh.write(icon_svg())
        # -b flattens onto an opaque colour, which is what keeps the PNG at
        # colour type 2. App Store Connect rejects a marketing icon with alpha.
        subprocess.run(["rsvg-convert", "-w", str(OUT_SIZE), "-h", str(OUT_SIZE),
                        "-b", DARKEST, svg, "-o", out], check=True)

    img = PNG(out)
    if img.has_alpha:
        raise SystemExit(f"{out} has an alpha channel — App Store Connect will reject it")
    print(f"wrote {out} ({img.width}x{img.height}, colour type {img.color_type})")


if __name__ == "__main__":
    main()
