---
name: build
description: "Cut a new build of Trading Up: branch from main, set CURRENT_PROJECT_VERSION in TradingUp.xcodeproj/project.pbxproj to the next build number derived from the highest local .xcarchive, commit/push and open a PR, merge it, then create a code-signed .xcarchive in Xcode's Organizer location. Use when the user runs /build or asks to cut, produce, or release a new build or archive."
user-invocable: true
---

# /build — cut a new build

Run the full release-build workflow for **Trading Up**. Perform the steps below **in order**,
stopping and reporting back if any step fails. This command takes no arguments.

It uses the `shell` tool to run `git`, `gh`, and `xcodebuild`; approve those tool
calls when prompted.

## Prerequisites (verify, do not assume)

- macOS with Xcode installed and a valid signing identity for team `ACPF4NWF99`
  (the target uses `CODE_SIGN_STYLE = Automatic`).
- `gh` is installed and authenticated (`gh auth status`).
- Always put Homebrew on `PATH` first: `export PATH="/opt/homebrew/bin:$PATH"`.
- The working tree is clean. If there are uncommitted changes, stop and ask the user how to
  proceed.

## Step 1 — Open a new branch from `main` and compute the next build number

Branch from the latest remote `main` so the bump lands on top of current work:

```sh
git fetch origin main
```

Do **not** just add 1 to the value in the project file — if that value is behind the builds
you've actually archived, incrementing it reuses a build number. Instead, derive the next
build number from the **highest `CFBundleVersion` across the `.xcarchive`s already in Xcode's
Organizer**, filtered to this app's bundle identifier so unrelated apps (e.g. the old
`com.callmegreg.xpwaste` archives) don't count:

```sh
ARCHIVES_DIR="$HOME/Library/Developer/Xcode/Archives"

# App bundle id straight from the project (excludes the .tests / .uitests targets).
BUNDLE_ID=$(grep -E 'PRODUCT_BUNDLE_IDENTIFIER' TradingUp.xcodeproj/project.pbxproj \
  | sed -E 's/.*= (.*);/\1/' | grep -vE '\.(tests|uitests)$' | head -1)

# Highest build number among local archives for that bundle id (0 if none exist yet).
HIGHEST=$(find "$ARCHIVES_DIR" -maxdepth 3 -path '*.xcarchive/Info.plist' 2>/dev/null \
  | while IFS= read -r plist; do
      bid=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleIdentifier" "$plist" 2>/dev/null)
      [ "$bid" = "$BUNDLE_ID" ] || continue
      /usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$plist" 2>/dev/null
    done | grep -E '^[0-9]+$' | sort -n | tail -1)
HIGHEST=${HIGHEST:-0}

# The app target's current build number in the project — the value to replace in Step 2,
# and the fallback basis when no local archives exist yet.
CURRENT=$(grep -E 'CURRENT_PROJECT_VERSION' TradingUp.xcodeproj/project.pbxproj | grep -oE '[0-9]+' | head -1)

if [ "$HIGHEST" -gt 0 ]; then
  NEW=$((HIGHEST + 1))
  echo "Highest local archive for $BUNDLE_ID is build $HIGHEST; next build -> $NEW"
else
  NEW=$((CURRENT + 1))
  echo "No local archives for $BUNDLE_ID; falling back to project build $CURRENT -> $NEW"
fi
```

Then create the branch:

```sh
git switch --create "bump-build-$NEW" origin/main
```

> If `$NEW` equals `$CURRENT` (a previous run already committed this bump but its archive
> didn't complete), Steps 2–4 have nothing to change — skip straight to Step 5 and re-archive
> build `$NEW`.

## Step 2 — Set `CURRENT_PROJECT_VERSION` to the new build number

Set the **app target's** build number to `$NEW` in `TradingUp.xcodeproj/project.pbxproj`. The
file stores it as `= N;`. The app target's Debug + Release configs share one value
(`$CURRENT`); the `.tests` / `.uitests` targets keep their own, unrelated
`CURRENT_PROJECT_VERSION` — leave those alone. Matching on the app's current value updates
only the app's two configs:

```sh
# Replaces only the app target's `CURRENT_PROJECT_VERSION = $CURRENT;` (both configs).
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )$CURRENT;/\1$NEW;/g" TradingUp.xcodeproj/project.pbxproj
```

Verify exactly the two app-target lines changed and the test targets were untouched:

```sh
grep -n 'CURRENT_PROJECT_VERSION' TradingUp.xcodeproj/project.pbxproj
git --no-pager diff
```

## Step 3 — Commit, push, and open a PR

Commit only the version file, push the branch, and open a PR against `main`:

```sh
git add TradingUp.xcodeproj/project.pbxproj
git commit -m "Bump build number to $NEW

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
git push -u origin "bump-build-$NEW"

gh pr create --base main --head "bump-build-$NEW" \
  --title "Bump build number to $NEW" \
  --body "Automated build bump to \`$NEW\` — the next build after the highest local \`.xcarchive\`. Sets the app target's \`CURRENT_PROJECT_VERSION\` in \`TradingUp.xcodeproj/project.pbxproj\`."
```

## Step 4 — Merge the PR

Squash-merge and delete the branch:

```sh
gh pr merge --squash --delete-branch
```

If branch protection blocks an immediate merge:
- Enable auto-merge and wait for required checks to pass before continuing:
  `gh pr merge --squash --auto --delete-branch`, then poll `gh pr view --json state,mergedAt`
  until it reports `MERGED`.
- Only use `--admin` to bypass checks if the user has permission and asks for it.

Do not start the archive until the PR is actually merged.

## Step 5 — Create a code-signed `.xcarchive` in Xcode's Organizer location

The version bump is already committed on the current branch (and now merged), so archive from the
current working tree — do **not** `git switch main`, which fails in a linked worktree when `main`
is checked out in the primary checkout. Archive **Release** straight into the Xcode Organizer
archives directory (`~/Library/Developer/Xcode/Archives/<date>/`) so it appears in
**Xcode → Window → Organizer**.

```sh
export PATH="/opt/homebrew/bin:$PATH"

ARCHIVE_ROOT="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$ARCHIVE_ROOT"
ARCHIVE_PATH="$ARCHIVE_ROOT/TradingUp $(date +%Y-%m-%d\ %H.%M).xcarchive"

xcodebuild -project TradingUp.xcodeproj -scheme TradingUp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive
```

**Important:** this must be a real signed archive — do **not** pass `CODE_SIGNING_ALLOWED=NO`.
Automatic signing with team `ACPF4NWF99` and `-allowProvisioningUpdates` lets Xcode resolve the
signing certificate and provisioning profile.

Confirm the archive landed in the Organizer location and carries build `$NEW`:

```sh
ls -la "$ARCHIVE_PATH"
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE_PATH/Info.plist"
```

The printed `CFBundleVersion` must equal `$NEW`; if it doesn't, the wrong build number was
archived — stop and investigate before distributing.

Then report the final build number and the archive path. The archive is now listed under
**Xcode → Window → Organizer → Archives** for that date, ready to distribute.
