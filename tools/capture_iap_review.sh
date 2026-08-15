#!/usr/bin/env bash
#
# Capture the App Review screenshot for the Full Collection in-app purchase.
#
# App Store Connect wants "a screenshot of the In-App Purchase that clearly
# shows the item or service being offered" — review only, never shown on the
# store. This boots a 6.9" iPhone simulator, wipes the app so the save is fresh,
# runs the single IAPReviewScreenshotTests case (which opens the real paywall
# from a paid, locked set), and exports the one frame. The TradingUpScreenshots
# scheme references TradingUp.storekit, so the live $2.99 price renders too.
#
#   tools/capture_iap_review.sh                      # default: iPhone 17 Pro Max
#   tools/capture_iap_review.sh "iPhone 16 Pro Max"  # any 6.9" device
#
# Output: docs/app-store/iap-review-full-collection.png  (1320x2868, a valid
# 6.9" App Store screenshot spec size), committed alongside the promo image.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT=TradingUp.xcodeproj
SCHEME=TradingUpScreenshots
BUNDLE_ID=com.callmegreg.tradingup
DERIVED=${DERIVED_DATA:-build/screenshots-dd}
DEST=docs/app-store
OUT_NAME=iap-review-full-collection.png
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

DEVICE=${1:-iPhone 17 Pro Max}

udid_for() {   # udid_for <device-name>
  xcrun simctl list devices available -j | /usr/bin/python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)['devices']
for runtime, devices in sorted(data.items(), reverse=True):
    for d in devices:
        if d['name'] == name and d.get('isAvailable'):
            print(d['udid']); sys.exit(0)
sys.exit('no available simulator named ' + name)
" "$1"
}

udid=$(udid_for "$DEVICE")
result="$WORK/iap-review.xcresult"

echo "==> $DEVICE ($udid)"
xcrun simctl boot "$udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
# A fresh install with no Documents folder is what "fresh save" means here, so
# the paywall is reachable (the unlock hasn't been bought).
xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl status_bar "$udid" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --dataNetwork wifi \
  --wifiMode active --wifiBars 3 >/dev/null 2>&1 || true

xcodebuild build-for-testing -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
  -quiet

echo "--> opening the paywall on a fresh save"
xcodebuild test-without-building -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$udid" -derivedDataPath "$DERIVED" \
  -only-testing:TradingUpUITests/IAPReviewScreenshotTests/testCaptureIAPReviewScreenshot \
  -resultBundlePath "$result" -quiet

xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true

# Export the single attachment and copy it to its committed home.
staging="$WORK/export"
xcrun xcresulttool export attachments --path "$result" --output-path "$staging" >/dev/null
mkdir -p "$DEST"
/usr/bin/python3 - "$staging" "$DEST/$OUT_NAME" <<'PY'
import json, os, shutil, sys
staging, dest = sys.argv[1], sys.argv[2]
manifest = json.load(open(os.path.join(staging, "manifest.json")))
for test in manifest:
    for att in test.get("attachments", []):
        if att["suggestedHumanReadableName"].startswith("iap-review-full-collection"):
            shutil.copy(os.path.join(staging, att["exportedFileName"]), dest)
            print("  wrote", dest)
            sys.exit(0)
sys.exit("no iap-review-full-collection attachment found in the result bundle")
PY

# Sanity-check the dimensions against a valid 6.9" App Store spec size.
/usr/bin/python3 - "$DEST/$OUT_NAME" <<'PY'
import struct, sys
path = sys.argv[1]
with open(path, "rb") as f:
    head = f.read(26)
assert head[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
w, h = struct.unpack(">II", head[16:24])
print(f"  {path}: {w}x{h}")
ok = {(1320, 2868), (2868, 1320)}
assert (w, h) in ok, f"unexpected size {w}x{h}; expected a 6.9\" 1320x2868 screenshot"
print("  OK — valid 6.9\" App Store screenshot size")
PY

echo
echo "Done. Upload $DEST/$OUT_NAME to the In-App Purchase's App Review Screenshot slot."
