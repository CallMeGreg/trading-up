---
name: build
description: "Cut a new build of Trading Up: branch from main, increment CURRENT_PROJECT_VERSION in TradingUp.xcodeproj/project.pbxproj, commit/push and open a PR, merge it, then create a code-signed .xcarchive in Xcode's Organizer location. Use when the user runs /build or asks to cut, produce, or release a new build or archive."
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

## Step 1 — Open a new branch from `main`

Branch from the latest remote `main` so the bump lands on top of current work:

```sh
git fetch origin main
```

Read the current build number and compute the next one, then create the branch:

```sh
CURRENT=$(grep -E 'CURRENT_PROJECT_VERSION' TradingUp.xcodeproj/project.pbxproj | grep -oE '[0-9]+' | head -1)
NEW=$((CURRENT + 1))
echo "Bumping build $CURRENT -> $NEW"
git switch --create "bump-build-$NEW" origin/main
```

## Step 2 — Increment `CURRENT_PROJECT_VERSION`

Increment the integer by 1 in `TradingUp.xcodeproj/project.pbxproj`. It stores the value as
`= N;` and has **two** occurrences (Debug + Release configs) — update all of them.

```sh
# TradingUp.xcodeproj/project.pbxproj  (e.g.  CURRENT_PROJECT_VERSION = 1;  ->  2;)
sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\1$NEW;/g" TradingUp.xcodeproj/project.pbxproj
```

Verify the file now shows the new value and nothing else changed:

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
  --body "Automated build bump: \`CURRENT_PROJECT_VERSION\` $CURRENT → $NEW in \`TradingUp.xcodeproj/project.pbxproj\`."
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

Confirm the archive landed in the Organizer location:

```sh
ls -la "$ARCHIVE_PATH"
```

Then report the final build number and the archive path. The archive is now listed under
**Xcode → Window → Organizer → Archives** for that date, ready to distribute.
