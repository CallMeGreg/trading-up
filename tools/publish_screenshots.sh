#!/usr/bin/env bash
#
# Publish the five real screenshots the README and the website embed.
#
# tools/capture_screenshots.sh plays the game in a Simulator and dumps a full
# set of native-resolution device screenshots into
# docs/screenshots/appstore/<device>/. Those are gitignored build output — ~65 MB
# a capture. This script picks the five frames that tell the game's loop, shrinks
# them, and writes the two small copies that *are* checked in:
#
#   docs/screenshots/app/NN-<scene>.png   621x1344 PNG  <- README.md
#   site/screenshots/<scene>.webp         480x1039 WebP <- site/index.html
#
# Both come from the same capture, so the README and the website can never drift
# apart, and neither can drift from the app: every pixel is the real thing.
#
#   tools/capture_screenshots.sh "iPhone 11 Pro Max"   # shoot the game
#   tools/publish_screenshots.sh                       # publish five of them
#
# Pass a different capture directory as the first argument to publish from
# another device. Requires cwebp (`brew install webp`); sips ships with macOS.
set -euo pipefail

cd "$(dirname "$0")/.."

SRC=${1:-docs/screenshots/appstore/iphone-11-pro-max}
PNG_DIR=docs/screenshots/app
WEBP_DIR=site/screenshots
PNG_HEIGHT=1344     # half of the 6.5" capture's 2688, so it stays pixel-exact
WEBP_WIDTH=480      # ~4x the ~100px the site's five-across strip renders at
WEBP_QUALITY=80

# scene:pattern — the pattern matches the capture's descriptive suffix rather
# than its number, so re-ordering the playthrough doesn't silently republish the
# wrong screen. Order is the game's loop: buy, rip, decide, grade, collect.
SCENES=(
  "01-shop:shop-after-a-few-packs"
  "02-rip-packs:pack-reveal-rare-hit"
  "03-keep-or-sell:pack-summary-evolution-bonus"
  "04-grade:grading-gem-mint"
  "05-collect:collection-locked-silhouettes"
)

if ! command -v cwebp >/dev/null 2>&1; then
  echo "cwebp not found — install it with: brew install webp" >&2
  exit 1
fi
if [ ! -d "$SRC" ]; then
  echo "no capture at $SRC — run tools/capture_screenshots.sh first" >&2
  exit 1
fi

mkdir -p "$PNG_DIR" "$WEBP_DIR"

for entry in "${SCENES[@]}"; do
  scene=${entry%%:*}
  pattern=${entry#*:}

  # Newest first: a partial re-capture (--only playthrough|endgame) leaves the
  # other pass's frames in place, and those can carry a stale number prefix, so
  # matching on mtime rather than name order publishes what was just shot.
  src=$(ls -t "$SRC"/*"$pattern".png 2>/dev/null | head -1)
  if [ -z "$src" ]; then
    echo "no capture matching '*$pattern.png' in $SRC" >&2
    exit 1
  fi

  sips -Z "$PNG_HEIGHT" "$src" --out "$PNG_DIR/$scene.png" >/dev/null
  cwebp -quiet -q "$WEBP_QUALITY" -resize "$WEBP_WIDTH" 0 "$src" \
    -o "$WEBP_DIR/${scene#*-}.webp"

  printf '  %-14s <- %s\n' "$scene" "$(basename "$src")"
done

echo
echo "Published ${#SCENES[@]} screenshots -> $PNG_DIR and $WEBP_DIR"
