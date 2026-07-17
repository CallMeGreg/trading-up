#!/usr/bin/env python3
"""Generate the Trading Up app icon: the procedural "sigil" emblem (fire palette)
on an ember gradient. Mirrors the sigil algorithm in design/mockups/cards.js and
TradingUp/Views/SigilView.swift so the icon matches the in-game card art.

Run with a Python that has Pillow installed:
    python3 tools/generate_icon.py
Writes: TradingUp/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import math
import os
from PIL import Image, ImageDraw

FIRE = ["#ffd15c", "#ff7a1a", "#e01f1f", "#5c1004"]
SEED = "Trading Up Emberfall"
SS = 2048          # supersample canvas; downscaled to 1024 for anti-aliasing
OUT_SIZE = 1024


def hex_rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def hash_str(s):
    h = 2166136261
    for ch in s:
        h ^= (ord(ch) & 0xFFFF)
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def make_rnd(seed):
    a = hash_str(seed)

    def rnd():
        nonlocal a
        a = (a + 0x6D2B79F5) & 0xFFFFFFFF
        t = ((a ^ (a >> 15)) * (1 | a)) & 0xFFFFFFFF
        t = ((t + (((t ^ (t >> 7)) * (61 | t)) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF
        return ((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
    return rnd


def main():
    pal = [hex_rgb(c) for c in FIRE]
    img = Image.new("RGB", (SS, SS), (0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")

    # Ember radial gradient background (bright core -> dark edge).
    center = (SS / 2, SS * 0.46)
    edge = (20, 6, 3)
    mid = (92, 22, 9)
    core = (168, 60, 20)
    maxr = SS * 0.78
    step = 3
    r = maxr
    while r > 0:
        t = r / maxr                      # 1 at edge, 0 at center
        if t > 0.5:
            col = lerp(mid, edge, (t - 0.5) / 0.5)
        else:
            col = lerp(core, mid, t / 0.5)
        d.ellipse([center[0] - r, center[1] - r, center[0] + r, center[1] + r], fill=col)
        r -= step

    # --- Sigil (same sequence of rnd() calls as the app) ---
    rnd = make_rnd(SEED)
    pad = 0.16
    side = SS * (1 - 2 * pad)
    ox = SS * pad
    oy = SS * pad

    def P(x, y):
        return (ox + x / 100.0 * side, oy + y / 100.0 * side)

    unit = side / 100.0

    arms = 5 + int(rnd() * 4)
    ring_count = 2 + int(rnd() * 3)
    rot = rnd() * 360.0

    def dim(color, f):
        return tuple(int(c * f) for c in color)

    for i in range(ring_count):
        rr = (12.0 + i * (32.0 / ring_count)) * unit
        cx, cy = P(50, 50)
        w = max(2, int((1.0 + rnd() * 1.4) * unit))
        d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=dim(pal[i % 4], 0.75) + (200,), width=w)

    d2r = math.pi / 180.0
    for i in range(arms):
        a = (rot + i * (360.0 / arms)) * d2r
        perp = a + math.pi / 2
        x1 = 50 + math.cos(a) * 13
        y1 = 50 + math.sin(a) * 13
        x2 = 50 + math.cos(a) * (36 + rnd() * 8)
        y2 = 50 + math.sin(a) * (36 + rnd() * 8)
        w = 3.5 + rnd() * 3
        bx1 = x1 + math.cos(perp) * w
        by1 = y1 + math.sin(perp) * w
        bx2 = x1 - math.cos(perp) * w
        by2 = y1 - math.sin(perp) * w
        d.polygon([P(bx1, by1), P(bx2, by2), P(x2, y2)], fill=pal[1] + (235,))
        tr = (1.8 + rnd() * 2) * unit
        tx, ty = P(x2, y2)
        d.ellipse([tx - tr, ty - tr, tx + tr, ty + tr], fill=pal[0] + (255,))

    sides = 3 + int(rnd() * 4)
    pts = []
    for i in range(sides):
        a = (rot + i * (360.0 / sides)) * d2r
        pts.append(P(50 + math.cos(a) * 11, 50 + math.sin(a) * 11))
    d.polygon(pts, fill=pal[2] + (255,), outline=(255, 255, 255, 200))
    cx, cy = P(50, 50)
    dr = 3 * unit
    d.ellipse([cx - dr, cy - dr, cx + dr, cy + dr], fill=(255, 255, 255, 230))

    out_dir = os.path.join(os.path.dirname(__file__), "..",
                           "TradingUp", "Assets.xcassets", "AppIcon.appiconset")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "icon-1024.png")
    img.resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
