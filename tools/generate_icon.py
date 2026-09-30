#!/usr/bin/env python3
"""Generate the text-free World Orbit app icon and matching website icon.

Render the five home-screen SetEmblem scenes directly from SetArt.swift, then
compose their glowing discs around a central sparkle. Reusing the app's drawing
code keeps the icon aligned with the home screen without a second set of scenes.

Needs macOS with Xcode and rsvg-convert (brew install librsvg). Python is
stdlib-only; the small Swift renderer uses Apple's SwiftUI and AppKit.

    python3 tools/generate_icon.py
    python3 tools/check_icon.py

Writes:
    TradingUp/Assets.xcassets/AppIcon.appiconset/icon-1024.png
    site/icon.png
"""
import base64
import math
from pathlib import Path
import shutil
import subprocess
import tempfile

from pngutil import PNG

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
VB = 256
OUT_SIZE = 1024
DARKEST = "#070c17"
COLORS = ("#ff8a32", "#42baff", "#75df6c", "#ffd747", "#b285ff")
ORBIT_RADIUS = 72
BADGE_RADIUS = 33


def render_emblems(directory):
    renderer = directory / "render-set-emblems"
    subprocess.run(
        ["xcrun", "swiftc", "-parse-as-library",
         str(ROOT / "TradingUp/Views/SetArt.swift"),
         str(HERE / "render_set_emblems.swift"), "-o", str(renderer)],
        check=True,
    )
    subprocess.run([str(renderer), str(directory)], check=True)
    return [(directory / f"set-{i}.png").read_bytes() for i in range(1, 6)]


def sparkle(x, y, size, color, opacity=1):
    return (
        f'<path d="M{x} {y-size} Q{x+size*.16} {y-size*.16} {x+size} {y} '
        f'Q{x+size*.16} {y+size*.16} {x} {y+size} '
        f'Q{x-size*.16} {y+size*.16} {x-size} {y} '
        f'Q{x-size*.16} {y-size*.16} {x} {y-size}Z" '
        f'fill="{color}" opacity="{opacity}"/>'
    )


def icon_svg(emblems):
    if len(emblems) != len(COLORS):
        raise ValueError("The World Orbit icon requires exactly five set emblems.")

    definitions = [
        '<radialGradient id="sky" cx="48%" cy="36%" r="85%">'
        '<stop stop-color="#213657"/><stop offset=".5" stop-color="#101b31"/>'
        f'<stop offset="1" stop-color="{DARKEST}"/></radialGradient>',
        '<filter id="shadow" x="-50%" y="-50%" width="200%" height="200%">'
        '<feDropShadow dx="0" dy="7" stdDeviation="7" flood-color="#00040d" '
        'flood-opacity=".65"/></filter>',
        '<filter id="scene" x="-10%" y="-10%" width="120%" height="120%">'
        '<feColorMatrix type="saturate" values="1.12"/>'
        '<feComponentTransfer><feFuncR type="linear" slope="1.14"/>'
        '<feFuncG type="linear" slope="1.14"/><feFuncB type="linear" slope="1.14"/>'
        '</feComponentTransfer></filter>',
    ]
    for i, color in enumerate(COLORS):
        definitions += [
            f'<radialGradient id="aura-{i}"><stop stop-color="{color}" stop-opacity=".5"/>'
            f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></radialGradient>',
            f'<linearGradient id="rim-{i}" x1="0" y1="0" x2="1" y2="1">'
            f'<stop stop-color="{color}"/><stop offset=".5" stop-color="#e8f5ff" '
            f'stop-opacity=".75"/><stop offset="1" stop-color="{color}" '
            'stop-opacity=".6"/></linearGradient>',
        ]

    body = [
        f'<rect width="{VB}" height="{VB}" fill="url(#sky)"/>',
        '<circle cx="128" cy="124" r="106" fill="url(#aura-4)" opacity=".18"/>',
        f'<circle cx="128" cy="128" r="{ORBIT_RADIUS}" fill="none" stroke="#799ccb" '
        'stroke-width="1" opacity=".22"/>',
        '<circle cx="128" cy="128" r="39" fill="url(#aura-1)" opacity=".5"/>',
        sparkle(128, 128, 14, "#c1ddff"),
        sparkle(159, 149, 3.5, "#acbded", .65),
        sparkle(102, 104, 2.5, "#acbded", .6),
    ]
    for i, emblem in enumerate(emblems):
        angle = math.radians(-90 + i * 72)
        x = 128 + math.cos(angle) * ORBIT_RADIUS
        y = 128 + math.sin(angle) * ORBIT_RADIUS
        radius = BADGE_RADIUS
        definitions.append(
            f'<clipPath id="badge-{i}"><circle cx="{x}" cy="{y}" r="{radius-1}"/></clipPath>'
        )
        encoded = base64.b64encode(emblem).decode("ascii")
        body += [
            f'<circle cx="{x}" cy="{y}" r="{radius*1.8}" fill="url(#aura-{i})" opacity=".62"/>',
            f'<circle cx="{x}" cy="{y}" r="{radius}" fill="#0c1730" filter="url(#shadow)"/>',
            f'<g clip-path="url(#badge-{i})" filter="url(#scene)">'
            f'<image x="{x-radius}" y="{y-radius}" width="{radius*2}" height="{radius*2}" '
            f'href="data:image/png;base64,{encoded}"/></g>',
            f'<circle cx="{x}" cy="{y}" r="{radius-1}" fill="none" '
            f'stroke="url(#rim-{i})" stroke-width="1.9"/>',
        ]
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{OUT_SIZE}" height="{OUT_SIZE}" '
        f'viewBox="0 0 {VB} {VB}"><title>World orbit</title><defs>'
        + "".join(definitions) + '</defs>' + "".join(body) + '</svg>'
    )


def main():
    app_icon = ROOT / "TradingUp/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    site_icon = ROOT / "site/icon.png"
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        svg = directory / "icon.svg"
        png = directory / "icon.png"
        svg.write_text(icon_svg(render_emblems(directory)))
        subprocess.run(
            ["rsvg-convert", "-w", str(OUT_SIZE), "-h", str(OUT_SIZE),
             "-b", DARKEST, str(svg), "-o", str(png)],
            check=True,
        )
        image = PNG(png)
        if (image.width, image.height) != (OUT_SIZE, OUT_SIZE) or image.bit_depth != 8 or image.has_alpha:
            raise SystemExit("The generated icon must be an opaque, 8-bit, 1024x1024 PNG.")
        for output in (app_icon, site_icon):
            output.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(png, output)
            print(f"wrote {output.relative_to(ROOT)} ({image.width}x{image.height}, colour type {image.color_type})")


if __name__ == "__main__":
    main()
