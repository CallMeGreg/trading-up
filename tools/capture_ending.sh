#!/usr/bin/env bash
#
# Screen-record the game's ending for the PR demo.
#
# Boots a simulator, builds the UI-test bundle, then screen-records the
# deterministic EndingFlowTests pass: launch a Season sitting at the Masters
# Invitational (Show 8) with the Quota already cleared, tap "Make the Cut", watch
# the Season Champion celebration take the screen, then drop back into the shop.
#
# The run is deterministic — the test pins the seeded state via the DEBUG-only
# launch hook (TU_TEST_STATE=almost-champion) — so the recording is the same every
# time and takes well under a minute.
#
#   tools/capture_ending.sh                    # iPhone 17 Pro, default output
#   tools/capture_ending.sh "iPhone 17 Pro Max"
#   tools/capture_ending.sh "iPhone 17 Pro" build/ending.mov
#
# Output: an .mov (H.264) at the given path, or build/ending.mov by default.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=TradingUp.xcodeproj
SCHEME=TradingUpScreenshots
DERIVED=${DERIVED_DATA:-build/ending-dd}
DEVICE=${1:-iPhone 17 Pro}
OUT=${2:-build/ending.mov}

mkdir -p "$(dirname "$OUT")"

udid=$(xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)['devices']
for runtime, devices in sorted(data.items(), reverse=True):
    for d in devices:
        if d['name'] == name and d.get('isAvailable'):
            print(d['udid']); sys.exit(0)
sys.exit('no available simulator named ' + name)
" "$DEVICE")

echo "==> $DEVICE ($udid)"
xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true

# A tidy status bar makes for a cleaner recording.
xcrun simctl status_bar "$udid" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --dataNetwork wifi \
  --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true

echo "--> building the UI-test bundle"
xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
  -quiet

echo "--> recording $OUT"
rm -f "$OUT"
xcrun simctl io "$udid" recordVideo --codec h264 --force "$OUT" &
REC_PID=$!
# Give the recorder a beat to spin up before the app launches.
sleep 2

set +e
xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
  -only-testing:TradingUpUITests/EndingFlowTests -quiet
STATUS=$?
set -e

# Let the final frame settle, then stop the recorder cleanly so the .mov is
# finalized (a specific-PID interrupt — no name-based kills).
sleep 1
kill -INT "$REC_PID" 2>/dev/null || true
wait "$REC_PID" 2>/dev/null || true

xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true

if [ $STATUS -ne 0 ]; then
  echo "!! EndingFlowTests failed (exit $STATUS); recording may be incomplete" >&2
  exit $STATUS
fi

echo "Done. Wrote $OUT"
