#!/usr/bin/env bash
#
# Capture App Store marketing screenshots by actually playing the game.
#
# Boots a simulator, wipes the app so the save really is fresh, runs the
# TradingUpUITests playthrough (buy packs, rip them, sell dupes, grade a rare,
# browse the collection), then seeds a completed collection and runs a second
# short pass for the late-game screens. Every frame is a real device screenshot
# at native resolution.
#
#   tools/capture_screenshots.sh                       # both passes, both sizes
#   tools/capture_screenshots.sh "iPhone 17 Pro Max"   # just one device
#   tools/capture_screenshots.sh --only endgame        # refresh shots 25-29 only
#
# --only takes `playthrough` (shots 01-24), `endgame` (25-29) or `all`. Use it
# when a change only touches part of the game so the rest of the set — and its
# place in git history — is left alone.
#
# Output: docs/screenshots/appstore/<slug>/NN-name.png
#
# Required App Store Connect sizes (the app ships TARGETED_DEVICE_FAMILY "1,2",
# so iPad screenshots are required too):
#   iPhone 6.9"  1320x2868  — iPhone 17 Pro Max / 16 Pro Max
#   iPhone 6.5"  1242x2688  — iPhone 11 Pro Max / XS Max
#   iPad 13"     2064x2752  — iPad Pro 13-inch (M4 or later)
#
# The 6.5" slot is its own upload in App Store Connect and rejects a 6.9" image,
# so it gets its own capture rather than a resize of the 6.9" set.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=TradingUp.xcodeproj
SCHEME=TradingUpScreenshots
BUNDLE_ID=com.callmegreg.tradingup
DERIVED=${DERIVED_DATA:-build/screenshots-dd}
OUT_ROOT=docs/screenshots/appstore
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

ONLY=all
DEVICES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY=${2:-}; shift 2 ;;
    --only=*) ONLY=${1#*=}; shift ;;
    *) DEVICES+=("$1"); shift ;;
  esac
done
case "$ONLY" in
  all|playthrough|endgame) ;;
  *) echo "--only must be all, playthrough or endgame (got '$ONLY')" >&2; exit 2 ;;
esac
if [ ${#DEVICES[@]} -eq 0 ]; then
  DEVICES=("iPhone 17 Pro Max" "iPhone 11 Pro Max" "iPad Pro 13-inch (M5)")
fi

slugify() { echo "$1" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9.-'; }

udid_for() {
  local name=$1 udid devicetype runtime
  udid=$(xcrun simctl list devices available -j \
    | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)['devices']
for runtime, devices in sorted(data.items(), reverse=True):
    for d in devices:
        if d['name'] == name and d.get('isAvailable'):
            print(d['udid']); sys.exit(0)
" "$name")
  if [ -n "$udid" ]; then
    echo "$udid"
    return 0
  fi
  # Xcode doesn't ship a simulator for every size the App Store still asks for
  # — the 6.5" iPhone has to be created — so make one from its device type
  # rather than making the operator do it by hand.
  devicetype=$(xcrun simctl list devicetypes -j | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
for dt in json.load(sys.stdin)['devicetypes']:
    if dt['name'] == name:
        print(dt['identifier']); sys.exit(0)
sys.exit('no simulator device type named ' + name)
" "$name")
  runtime=$(xcrun simctl list runtimes -j | /usr/bin/python3 -c "
import json, sys
ios = [r for r in json.load(sys.stdin)['runtimes']
       if r.get('isAvailable') and r.get('platform') == 'iOS']
if not ios:
    sys.exit('no available iOS simulator runtime')
ios.sort(key=lambda r: [int(p) for p in r['version'].split('.')])
print(ios[-1]['identifier'])
")
  echo "    creating simulator: $name" >&2
  xcrun simctl create "$name" "$devicetype" "$runtime"
}

export_shots() {   # export_shots <xcresult> <destination-dir>
  local result=$1 dest=$2 staging="$WORK/export"
  rm -rf "$staging"
  xcrun xcresulttool export attachments --path "$result" --output-path "$staging" >/dev/null
  mkdir -p "$dest"
  /usr/bin/python3 - "$staging" "$dest" <<'PY'
import json, os, re, shutil, sys
staging, dest = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(staging, "manifest.json")))
count = 0
for test in manifest:
    for att in test.get("attachments", []):
        name = re.sub(r"_\d+_[0-9A-F-]{36}\.png$", ".png", att["suggestedHumanReadableName"])
        if not name.endswith(".png"):
            continue
        shutil.copy(os.path.join(staging, att["exportedFileName"]), os.path.join(dest, name))
        count += 1
print(f"  exported {count} screenshots -> {dest}")
PY
}

seed_completed_save() {   # seed_completed_save <udid>
  local container
  container=$(xcrun simctl get_app_container "$1" "$BUNDLE_ID" data)
  mkdir -p "$container/Documents"
  /usr/bin/python3 tools/seed_save.py "$container/Documents/tradingup_save.json"
}

for device in "${DEVICES[@]}"; do
  slug=$(slugify "$device")
  udid=$(udid_for "$device")
  dest="$OUT_ROOT/$slug"
  result="$WORK/$slug.xcresult"

  echo "==> $device ($udid)"
  # A partial refresh keeps the shots it isn't re-taking.
  [ "$ONLY" = all ] && rm -rf "$dest"

  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  # A fresh install with no Documents folder is what "fresh save" means here.
  if [ "$ONLY" != endgame ]; then
    xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi
  xcrun simctl status_bar "$udid" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --dataNetwork wifi \
    --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true

  xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
    -quiet

  if [ "$ONLY" != endgame ]; then
    echo "--> playthrough from a fresh save"
    xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
      -only-testing:TradingUpUITests/ScreenshotTests/testPlaythroughCapturesAppStoreScreenshots \
      -resultBundlePath "$result" -quiet
    export_shots "$result" "$dest"
  else
    # The playthrough normally installs the app; on its own the endgame pass
    # needs a container to seed, so install the build we just made.
    xcrun simctl install "$udid" \
      "$DERIVED/Build/Products/Debug-iphonesimulator/TradingUp.app" >/dev/null
  fi

  if [ "$ONLY" != playthrough ]; then
    echo "--> endgame showcase from a seeded completed collection"
    seed_completed_save "$udid"
    rm -rf "$result-endgame"
    xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
      -only-testing:TradingUpUITests/ScreenshotTests/testEndgameShowcaseScreenshots \
      -resultBundlePath "$result-endgame" -quiet
    export_shots "$result-endgame" "$dest"
  fi

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
  /usr/bin/python3 tools/check_screenshots.py "$dest"
done

echo
echo "Done. Upload from $OUT_ROOT/ — App Store Connect takes up to 10 per size."
