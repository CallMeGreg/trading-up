#!/usr/bin/env python3
"""Check captured screenshots against App Store Connect's specifications.

    python3 tools/check_screenshots.py docs/screenshots/appstore/<slug>

Verifies every PNG in the folder is one of the accepted portrait sizes for a
required display class, carries no alpha channel, and that the folder holds
enough frames to fill a listing (App Store Connect accepts up to 10 per size).

Spec: https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngutil import PNG  # noqa: E402

# Portrait sizes App Store Connect accepts for the two display classes this app
# has to provide (it ships TARGETED_DEVICE_FAMILY "1,2", so iPad is required).
ACCEPTED = {
    (1320, 2868): 'iPhone 6.9"',
    (1290, 2796): 'iPhone 6.9"',
    (2064, 2752): 'iPad 13"',
    (2048, 2732): 'iPad 13"',
}
MAX_PER_LISTING = 10


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: check_screenshots.py <directory>")
    directory = sys.argv[1]
    names = sorted(n for n in os.listdir(directory) if n.lower().endswith(".png"))
    if not names:
        sys.exit(f"no PNGs in {directory}")

    print(f"== Screenshots: {directory} ==")
    failures = []
    classes = set()

    for name in names:
        shot = PNG(os.path.join(directory, name))
        size = (shot.width, shot.height)
        display = ACCEPTED.get(size)
        problems = []
        if display is None:
            problems.append(f"{size[0]}x{size[1]} is not an accepted size")
        if shot.has_alpha:
            problems.append("has an alpha channel")
        if problems:
            failures.append(f"{name}: {'; '.join(problems)}")
            print(f"  ✗ {name}: {'; '.join(problems)}")
        else:
            classes.add(display)
            print(f"  ✓ {name}  {size[0]}x{size[1]}  {display}")

    print()
    print(f"{len(names)} screenshots, display class: {', '.join(sorted(classes)) or 'none'}")
    if len(names) < MAX_PER_LISTING:
        print(f"note: only {len(names)} captured; a listing can show up to {MAX_PER_LISTING}.")
    if len(classes) > 1:
        failures.append("folder mixes display classes; keep one size per folder")
        print("✗ folder mixes display classes; keep one size per folder")

    if failures:
        print(f"\n{len(failures)} problem(s).")
        return 1
    print("All screenshots meet App Store Connect's specification.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
