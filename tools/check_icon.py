#!/usr/bin/env python3
"""Check the 1024x1024 App Store icon against Apple's submission rules.

App Store Connect rejects a marketing icon that carries an alpha channel, and
the Human Interface Guidelines ask for a full-bleed square — iOS applies the
rounded-corner mask itself, so baking one in leaves visible dark wedges once the
system mask is applied on top.

    python3 tools/check_icon.py

Exits non-zero if anything would be rejected. See:
https://developer.apple.com/design/human-interface-guidelines/app-icons
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngutil import PNG  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON = os.path.join(REPO, "TradingUp", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

failures = []


def check(ok, message):
    print(f"  {'✓' if ok else '✗ FAIL:'} {message}")
    if not ok:
        failures.append(message)


def main():
    print("== App Store icon ==")
    if not os.path.exists(ICON):
        sys.exit(f"missing {ICON}")

    icon = PNG(ICON)
    check(icon.width == 1024 and icon.height == 1024,
          f"1024x1024 (got {icon.width}x{icon.height})")
    check(not icon.has_alpha, "no alpha channel (colour type 2 = RGB, no tRNS)")
    check(icon.bit_depth == 8, f"8 bits per channel (got {icon.bit_depth})")

    # A baked-in rounded mask leaves the extreme corner a flat, uniform block
    # that doesn't match the artwork bleeding up to it. Sample the very corner
    # against a pixel a little way in along the diagonal: on a full-bleed icon
    # they belong to the same background and stay close.
    inset = 40
    corners = {
        "top-left": ((0, 0), (inset, inset)),
        "top-right": ((icon.width - 1, 0), (icon.width - 1 - inset, inset)),
        "bottom-left": ((0, icon.height - 1), (inset, icon.height - 1 - inset)),
        "bottom-right": ((icon.width - 1, icon.height - 1),
                         (icon.width - 1 - inset, icon.height - 1 - inset)),
    }
    for name, (corner, inner) in corners.items():
        edge = icon.pixel(*corner)
        near = icon.pixel(*inner)
        delta = max(abs(a - b) for a, b in zip(edge, near))
        check(delta <= 24,
              f"{name} corner is full-bleed, not masked (rgb{edge} vs rgb{near}, Δ{delta})")

    print()
    if failures:
        print(f"{len(failures)} problem(s) — fix before uploading.")
        return 1
    print("Icon is ready to upload.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
