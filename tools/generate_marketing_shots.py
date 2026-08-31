#!/usr/bin/env python3
"""Curated App Store marketing panels built from the real captured screenshots.

Where `tools/generate_screenshots.py` re-draws a curated set of Classic-mode
screens from scratch in SVG and wraps each in a floating phone frame, this tool
takes the *actual* screenshots captured by `tools/capture_screenshots.sh` and
composes them into the same marketing language — bold headline + call-to-action
subtitle over the app's gradient — but **frameless**: no phone bezel and no iOS
status bar (the "9:41" overlay is cropped off), so each panel reads as a clean,
designed image rather than a raw device grab.

It exists because the from-scratch generator predates Gauntlet Mode and the
Binder and only covers Classic Mode. Sourcing the real screens is the faithful
way to show the two new pillars (Gauntlet, Binder) alongside Classic in one
curated ten-slot set, at both App Store sizes.

Source: docs/screenshots/appstore/<device>/*-<slug>.png — the gitignored capture
output. Run the capture first (it is the same prerequisite publish_screenshots.sh
has):

  DERIVED_DATA=build/screenshots-dd tools/capture_screenshots.sh \
      "iPhone 11 Pro Max" "iPad Pro 13-inch (M5)"
  python3 tools/generate_marketing_shots.py

Output: docs/screenshots/marketing/<NN>_<slug>_<w>x<h>.png — 10 scenes x 2 sizes.
Rendered with rsvg-convert (librsvg — `brew install librsvg`), which emits RGB
(no alpha channel), exactly what App Store Connect requires.
"""
import glob
import os
import struct
import subprocess
import sys
import tempfile

# Reuse the exact palette, typography, gradient and SVG helpers the from-scratch
# generator already defines, so the two marketing sets stay visually identical.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import generate_screenshots as gs  # noqa: E402

ROOT = gs.ROOT
SRC_ROOT = os.path.join(ROOT, "docs", "screenshots", "appstore")
OUT_DIR = os.path.join(ROOT, "docs", "screenshots", "marketing")

# App Store size -> (capture source folder, iOS status-bar height in px to crop).
# The status bar is the only "overlay" on these otherwise-clean app screens:
# iPhone 11 Pro Max is @3x (44pt -> 132px); iPad Pro 13" is @2x (~28pt -> 64px).
DEVICE = {
    (1242, 2688): ("iphone-11-pro-max", 132),
    (2064, 2752): ("ipad-pro-13-inch-m5", 64),
}
SIZES = [(1242, 2688), (2064, 2752)]

# order, slug, caption (headline), subtitle (CTA), accent element, and optional
# extra crop (top, bottom) to trim dead space. Each crop is *source* px, either a
# single int (same trim on every device) or a {(W, H): px} dict when the iPhone
# and iPad captures lay the screen out differently and need different trims.
# Ten slots ordered as a flow: the general pack-rip hook, then Classic Mode
# specifics, then Gauntlet Mode, then the permanent Binder, and finally a closing
# "do you have what it takes?" challenge. Each accent stays tied to its screen's
# dominant colour, and no two adjacent scenes repeat one.
EM = "\u2014"
SCENES = [
    # General — the universal hook
    ("01", "pack-reveal-rare-hit", "Every pull is a thrill.",
     "Rip a fresh pack card by card and chase rares, foils and ultras.",
     "water", 0, 0),
    # Classic Mode specifics
    ("02", "pack-summary-new-and-dupes", "Keep it %s or cash it in." % EM,
     "Keep every pull or sell your duplicates on the buylist to fund the next pack.",
     "grass", 0, 0),
    ("03", "grading-gem-mint", "Grade your best pulls.",
     "Send a card in and roll for a jackpot PSA 10 %s a five-times payday." % EM,
     "shadow", 0, 0),
    ("04", "win-master-collector", "Collect them all.",
     "Complete every set in Classic Mode and become a Master Collector.",
     "fire", 0, 0),
    # Gauntlet Mode specifics
    ("05", "gauntlet-run-building", "Run the Gauntlet.",
     "Pick a Trainer and push your Showcase past a rising Aura goal, rip after rip.",
     "shadow", 0, 0),
    ("06", "gauntlet-trainer-select", "Seven Trainers, seven playstyles.",
     "Each has a five-skill graph: rip more, grade sharper, hoard bigger.",
     "water", 0, 0),
    ("07", "gauntlet-share-card", "Clear it, claim the prize.",
     "Beat a Gauntlet run and take home a Foil Extended Art card.",
     "shadow", 0, 0),
    # Binder details
    ("08", "binder-emberfall", "Your best pulls, kept forever.",
     "The Binder saves the top copy of every Spryte, across every run.",
     "fire", 0, 0),
    ("09", "binder-umbral-reach", "Five sets. 250 Sprytes.",
     "Chase every creature across five worlds, Emberfall to Umbral Reach.",
     "shadow", 0, 0),
    # Closing challenge — the "do you have what it takes?" call to action. The
    # tier-select screen has a tall empty band below the cards that sits at a
    # different source row on each device, so the bottom crop is per-device.
    ("10", "gauntlet-tier-select", "Do you have what it takes?",
     "Clear Easy to unlock Medium, then conquer Hard.",
     "electric", 0, {(1242, 2688): 1410, (2064, 2752): 1600}),
]


def _crop_px(val, W, H):
    """extra_top / extra_bottom may be a single source-px int (same trim on every
    device) or a {(W, H): px} dict when the two captures need different trims."""
    if isinstance(val, dict):
        return val.get((W, H), 0)
    return val


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def find_src(folder, slug):
    matches = sorted(glob.glob(os.path.join(SRC_ROOT, folder, "*-%s.png" % slug)))
    if not matches:
        raise SystemExit(
            "missing source screenshot: %s/*-%s.png\n"
            "run tools/capture_screenshots.sh first (see this file's docstring)."
            % (os.path.join("docs/screenshots/appstore", folder), slug))
    return matches[0]


def compose(defs, W, H, src, sb, caption, subtitle, accent, extra_top, extra_bottom):
    """Gradient backdrop + caption + the real screenshot as a frameless card."""
    out = []

    # Background gradient, radial glow and faint sparkles — identical treatment to
    # generate_screenshots.device() so both marketing sets match.
    bg = defs.linear([("0%", gs._mix(accent, gs.BG0, 0.55), "1"),
                      ("55%", gs.BG0, "1"), ("100%", "#05070c", "1")])
    out.append(gs.rrect(0, 0, W, H, 0, grad=bg))
    gl = defs.radial([("0%", accent, "0.30"), ("60%", accent, "0")], cy=0.30, r=0.75)
    out.append(gs.rrect(0, 0, W, H, 0, grad=gl))
    s = 0x2545F491 ^ (W * 7)
    for _ in range(40):
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        x = s % W
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        y = s % H
        s = (1103515245 * s + 12345) & 0x7FFFFFFF
        r = 1 + s % 2
        out.append(gs.circle(x, y, r, fill="#ffffff", opacity=0.06))

    # Caption (headline + CTA subtitle), same metrics as the framed set.
    cx = W / 2
    cap_size = W * 0.062
    lines = gs.wrap(caption, 22)
    cap_y = H * 0.075
    for i, ln in enumerate(lines):
        out.append(gs.text(cx, cap_y + i * cap_size * 1.12, ln, cap_size,
                           "#ffffff", weight=900, anchor="middle"))
    sub_y = cap_y + len(lines) * cap_size * 1.12 + W * 0.012
    sub_lines = gs.wrap(subtitle, 46)
    # `accent` is the element's deep shade (ELEMENT[..][2]) and it also tints the
    # top of the gradient, so drawing the CTA in it reads as low-contrast same-hue
    # text (blue-on-blue, purple-on-purple, red-on-red). Lighten it toward white
    # for the subtitle so the CTA keeps its on-brand hue but stays legible.
    sub_col = gs._mix(accent, "#ffffff", 0.62)
    for i, ln in enumerate(sub_lines):
        out.append(gs.text(cx, sub_y + i * (W * 0.032), ln, W * 0.028,
                           sub_col, weight=600, anchor="middle", opacity=1.0))
    caption_bottom = sub_y + len(sub_lines) * (W * 0.032)

    # Fit the (status-bar-cropped) screenshot into the space under the caption,
    # by width and height, then centre it — same fit logic as the phone frame.
    sw, sh = png_size(src)
    top_src = sb + extra_top
    content_h = sh - top_src - extra_bottom
    aspect = sw / content_h
    top = caption_bottom + H * 0.03
    bottom_margin = H * 0.05
    avail_h = H - top - bottom_margin
    max_w = W * 0.84
    tw = min(max_w, avail_h * aspect)
    th = tw / aspect
    tx = (W - tw) / 2
    ty = top + (avail_h - th) / 2
    rr = tw * 0.055
    k = tw / sw

    # Soft drop shadow so the frameless screen still floats off the gradient.
    blur = defs.blur(tw * 0.03)
    out.append('<g filter="url(#%s)">%s</g>' % (
        blur, gs.rrect(tx, ty + th * 0.02, tw, th, rr, fill="#000000", opacity=0.5)))

    # The screenshot itself: shift it up by the cropped top and clip to the card,
    # dropping the iOS status bar without any pixel editing.
    clip = defs.clip_rrect(tx, ty, tw, th, rr)
    img_y = ty - top_src * k
    img_h = sh * k
    out.append('<g clip-path="url(#%s)"><image x="%.2f" y="%.2f" width="%.2f" '
               'height="%.2f" preserveAspectRatio="none" xlink:href="%s"/></g>' % (
                   clip, tx, img_y, tw, img_h, gs._data_uri(src)))

    # Crisp hairline edge.
    out.append(gs.rrect(tx, ty, tw, th, rr, stroke="#ffffff",
                        sw=max(1.0, W * 0.0016), opacity=0.10))
    return "".join(out)


def render(order, slug, caption, subtitle, accent_elem, extra_top, extra_bottom, W, H):
    folder, sb = DEVICE[(W, H)]
    src = find_src(folder, slug)
    defs = gs.Defs()
    accent = gs.ELEMENT[accent_elem][2]
    et = _crop_px(extra_top, W, H)
    eb = _crop_px(extra_bottom, W, H)
    body = compose(defs, W, H, src, sb, caption, subtitle, accent, et, eb)
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
           'width="%d" height="%d" viewBox="0 0 %d %d">%s%s</svg>') % (
        W, H, W, H, defs.render(), body)
    out_png = os.path.join(OUT_DIR, "%s_%s_%dx%d.png" % (order, slug, W, H))
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
        tmp = f.name
    subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), "-o", out_png, tmp], check=True)
    os.unlink(tmp)
    return out_png


def main():
    if "--list" in sys.argv:
        print("Marketing scenes (frameless, from real captures):")
        for order, slug, cap, _sub, accent, _t, _b in SCENES:
            print("  %s %-24s [%-8s] %s" % (order, slug, accent, cap))
        print("Sizes:", ", ".join("%dx%d" % s for s in SIZES))
        return
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Rendering %d scenes x %d sizes -> %s" % (len(SCENES), len(SIZES), OUT_DIR))
    for order, slug, cap, sub, accent, et, eb in SCENES:
        for (W, H) in SIZES:
            p = render(order, slug, cap, sub, accent, et, eb, W, H)
            print("  %s" % os.path.relpath(p, ROOT))
    print("Done.")


if __name__ == "__main__":
    main()
