---
name: build
description: "Cut a production or isolated test build of Trading Up: bump the selected app's CURRENT_PROJECT_VERSION using its local archives, commit/push and open a PR, merge it, then create a code-signed .xcarchive in Xcode's Organizer location. /build defaults to production; /build test uses TradingUpTest. Use when the user runs /build or asks to cut, produce, or release a new build or archive."
user-invocable: true
---

# /build — cut a new build

Run the full release-build workflow for **Trading Up**. Perform the steps below **in order**,
stopping and reporting back if any step fails. Plain `/build` (or `/build production`)
selects production; **`/build test`** selects the separate TestFlight app. If the requested
environment is unclear, ask before making changes.

| Environment | Scheme | App configurations to bump | Expected bundle ID |
| --- | --- | --- | --- |
| production | `TradingUp` | `Debug`, `Release` | `com.callmegreg.tradingup` |
| test | `TradingUpTest` | `Debug-Test`, `Release-Test` | `com.callmegreg.tradingup.test` |

Set these variables for the selected environment. Shell calls do not share variables;
carry the resolved values forward explicitly in later calls.

```sh
BUILD_ENVIRONMENT=production  # Set to test for /build test.
case "$BUILD_ENVIRONMENT" in
  production)
    SCHEME=TradingUp
    CONFIGURATION=Release
    EXPECTED_BUNDLE_ID=com.callmegreg.tradingup
    ;;
  test)
    SCHEME=TradingUpTest
    CONFIGURATION=Release-Test
    EXPECTED_BUNDLE_ID=com.callmegreg.tradingup.test
    ;;
  *) echo "Unknown build environment: $BUILD_ENVIRONMENT" >&2; exit 1 ;;
esac
```

Use the existing app-managed session branch/worktree, not the primary checkout. Never
force a test scheme to `Release`: that would select the production identity. This
workflow creates an archive, **not an upload**. TestFlight setup is documented in
`docs/APP_STORE.md#separate-test-app-testflight`.

## Prerequisites (verify, do not assume)

- macOS with Xcode installed and a valid signing identity for team `ACPF4NWF99`
  (the target uses `CODE_SIGN_STYLE = Automatic`). The project file has no
  `DEVELOPMENT_TEAM`, so Step 5 passes it to `xcodebuild` explicitly.
- `gh` is installed and authenticated (`gh auth status`).
- Always put Homebrew on `PATH` first: `export PATH="/opt/homebrew/bin:$PATH"`.
- The working tree is clean. If there are uncommitted changes, stop and ask the user how to
  proceed.

## Step 1 — Check the base and compute the selected app's next build number

Fetch the latest remote `main` so the bump includes current work:

```sh
git fetch origin main
git merge-base --is-ancestor origin/main HEAD
```

If this session is behind `main` or contains unrelated commits, stop and ask how to
proceed rather than resetting it or creating a raw git branch.

Do **not** just add 1 to the value in the project file — if that value is behind the builds
you've actually archived, incrementing it reuses a build number. Instead, derive the next
build number from the **highest `CFBundleVersion` across the `.xcarchive`s already in Xcode's
Organizer**, filtered to this app's bundle identifier so unrelated apps (e.g. the old
`com.callmegreg.xpwaste` archives) don't count:

```sh
ARCHIVES_DIR="$HOME/Library/Developer/Xcode/Archives"

# Resolve the selected app configuration, not the first identifier/version in the file.
SETTINGS=$(xcodebuild -project TradingUp.xcodeproj -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" -showBuildSettings -json)
BUNDLE_ID=$(printf '%s\n' "$SETTINGS" | python3 -c \
  'import json,sys; print(next(x["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"] for x in json.load(sys.stdin) if x["target"] == "TradingUp"))')
CURRENT=$(printf '%s\n' "$SETTINGS" | python3 -c \
  'import json,sys; print(next(x["buildSettings"]["CURRENT_PROJECT_VERSION"] for x in json.load(sys.stdin) if x["target"] == "TradingUp"))')
[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] || {
  echo "Wrong app identity: $BUNDLE_ID (expected $EXPECTED_BUNDLE_ID)" >&2
  exit 1
}

# Highest build number among local archives for that bundle id (0 if none exist yet).
HIGHEST=$(find "$ARCHIVES_DIR" -maxdepth 3 -path '*.xcarchive/Info.plist' 2>/dev/null \
  | while IFS= read -r plist; do
      bid=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleIdentifier" "$plist" 2>/dev/null)
      [ "$bid" = "$BUNDLE_ID" ] || continue
      /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$plist" 2>/dev/null
    done | grep -E '^[0-9]+$' | sort -n | tail -1)
HIGHEST=${HIGHEST:-0}

# Never go backwards when the project is ahead of the local archive history.
BASE=$CURRENT
if [ "$HIGHEST" -gt "$BASE" ]; then BASE=$HIGHEST; fi
NEW=$((BASE + 1))
echo "$BUILD_ENVIRONMENT ($BUNDLE_ID): project $CURRENT, highest archive $HIGHEST -> $NEW"
```

Local archives cannot reveal uploads from another Mac. If App Store Connect has a higher
build for this app, use a number above it too. Never borrow the other environment's counter.

## Step 2 — Set `CURRENT_PROJECT_VERSION` to the new build number

Use `apply_patch` to set **only the selected environment's two app-target configurations**
to `$NEW` in `TradingUp.xcodeproj/project.pbxproj`. Follow the `TradingUp` target's
`buildConfigurationList` to identify them; the project, unit-test, and UI-test targets
also have configurations with those names. Leave the other app environment and all
XCTest/UI-test version numbers untouched.

**Never do a global replacement by numeric value.** The test app initially shares build
number 1 with the automated-test targets, and production/test counters can coincide later.

Verify exactly the two intended build-number lines changed:

```sh
python3 -B -m unittest discover -s tools -p test_app_identity.py
git --no-pager diff
```

## Step 3 — Commit, push, and open a PR

Commit only the version file, push the branch, and open a PR against `main`:

```sh
git add TradingUp.xcodeproj/project.pbxproj
git commit -m "Bump $BUILD_ENVIRONMENT build number to $NEW

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
git push -u origin HEAD
```

Use the `create_pull_request` tool to open the PR. Include the environment, bundle ID,
scheme, and new build number in its title/body; explain that the other app is unchanged.

## Step 4 — Merge the PR

Squash-merge the PR:

```sh
gh pr merge --squash
```

If branch protection blocks an immediate merge:
- Enable auto-merge and wait for required checks to pass before continuing:
  `gh pr merge --squash --auto`, then check `gh pr view --json state,mergedAt`
  until it reports `MERGED`.
- Only use `--admin` to bypass checks if the user has permission and asks for it.

Do not start the archive until the PR is actually merged.

## Step 5 — Create a code-signed `.xcarchive` in Xcode's Organizer location

The version bump is already committed on the current branch (and now merged), so archive from the
current working tree — do **not** `git switch main`, which fails in a linked worktree when `main`
is checked out in the primary checkout. Archive the selected **Release / Release-Test**
configuration straight into the Xcode Organizer
archives directory (`~/Library/Developer/Xcode/Archives/<date>/`) so it appears in
**Xcode → Window → Organizer**.

```sh
export PATH="/opt/homebrew/bin:$PATH"

# The app target uses CODE_SIGN_STYLE = Automatic but the project file has NO
# DEVELOPMENT_TEAM set (Xcode's UI normally supplies it). From the command line that
# absence surfaces as "Signing requires a development team" and the archive fails, so
# pass the team explicitly. This is still a real signed archive — DEVELOPMENT_TEAM is
# an override, not a bypass.
DEVELOPMENT_TEAM="ACPF4NWF99"

ARCHIVE_ROOT="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$ARCHIVE_ROOT"
ARCHIVE_PATH="$ARCHIVE_ROOT/$SCHEME $(date +%Y-%m-%d\ %H.%M.%S).xcarchive"

xcodebuild -project TradingUp.xcodeproj -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  archive
```

**Important:** this must be a real signed archive — do **not** pass `CODE_SIGNING_ALLOWED=NO`.
Because the project file carries no `DEVELOPMENT_TEAM`, you **must** pass
`DEVELOPMENT_TEAM=ACPF4NWF99` on the `xcodebuild` line as shown; omitting it makes the archive
fail with *"Signing requires a development team."* With the team supplied, `CODE_SIGN_STYLE =
Automatic` plus `-allowProvisioningUpdates` lets Xcode resolve the signing certificate and
provisioning profile.

Confirm the archive landed in the Organizer location with the intended identity and build:

```sh
ls -la "$ARCHIVE_PATH"
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleIdentifier" "$ARCHIVE_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE_PATH/Info.plist"
```

The printed `CFBundleIdentifier` must equal `$EXPECTED_BUNDLE_ID` and `CFBundleVersion`
must equal `$NEW`; if either differs, stop and investigate before distributing.

Then report the environment, bundle ID, final build number, and archive path. The archive is now listed under
**Xcode → Window → Organizer → Archives** for that date, ready to distribute.
