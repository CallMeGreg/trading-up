---
name: build
description: "Handle Trading Up's per-PR release workflow: bump the shared production/test build in each PR, then after merge create matching signed Organizer archives and upload only the test app to TestFlight. /build, /build production, and /build test all use this paired workflow. Use when opening or merging a PR, running /build, or producing or uploading builds."
user-invocable: true
---

# /build — cut a matched release pair

Run the full release-build workflow for **Trading Up**. Perform the steps below **in order**,
stopping and reporting back if any step fails. **Always create production and test
archives as a pair**, from the same source commit and with the same version/build
number. `/build`, `/build production`, and `/build test` are aliases for this paired
workflow. Do not run the workflow twice and increment once per environment.

Every PR includes its own shared build bump, including documentation-only PRs.
When preparing a PR, complete Steps 1-3 without merging unless requested. When
merging a PR, verify its bump is still above the latest base and prior releases,
then complete Steps 4-6. If the PR is already merged, verify its source/build and
resume at Step 5; do not create an extra bump or PR. Reuse successful artifacts
and upload receipts when resuming an interrupted release.

| Environment | Scheme | Archive configuration | Expected bundle ID |
| --- | --- | --- | --- |
| production | `TradingUp` | `Release` | `com.callmegreg.tradingup` |
| test | `TradingUpTest` | `Release-Test` | `com.callmegreg.tradingup.test` |

Keep `MARKETING_VERSION` unchanged unless the user explicitly requests a version
change; it must agree across all four app configurations. Shell calls do not share
variables; carry resolved values forward explicitly in later calls.

Use the existing app-managed session branch/worktree, not the primary checkout. Never
force a test scheme to `Release`: that would select the production identity.
After each merge, keep both archives locally and upload **only the test app** to
TestFlight. Never upload production or submit either app for public release
unless explicitly requested. TestFlight setup is documented in
`docs/APP_STORE.md#separate-test-app-testflight`.

## Prerequisites (verify, do not assume)

- macOS with Xcode installed and a valid signing identity for team `ACPF4NWF99`
  (the target uses `CODE_SIGN_STYLE = Automatic`). The project file has no
  `DEVELOPMENT_TEAM`, so Step 5 passes it to `xcodebuild` explicitly.
- `gh` is installed and authenticated (`gh auth status`).
- Xcode has App Store Connect access to the existing **Trading Up Test** record,
  with permission to sign and upload. Do not print credentials, create an account,
  or change access permissions to work around a missing grant; report the blocker.
- Always put Homebrew on `PATH` first: `export PATH="/opt/homebrew/bin:$PATH"`.
- Inspect the working tree. Include current-task changes when the user has asked to
  release them; do not discard or commit unrelated edits. If their ownership or release
  intent is unclear, stop and ask. The tree must be clean before archiving.

## Step 1 — Check the base and compute the next shared build number

Fetch the latest remote `main` so the bump includes current work:

```sh
git fetch origin main
git merge-base --is-ancestor origin/main HEAD
```

If this session is behind `main` or contains unrelated commits, stop and ask how to
proceed rather than resetting it or creating a raw git branch.

Use one more than the **highest build number across both apps' project settings
and local Organizer archives**. This carries forward the higher production sequence
without ever reusing a number from either app. Ignore archives for unrelated bundle IDs.
Validate both resolved identities before choosing the number:

```sh
python3 - <<'PY'
import json
from pathlib import Path
import plistlib
import subprocess

variants = (
    ("TradingUp", "Release", "com.callmegreg.tradingup"),
    ("TradingUpTest", "Release-Test", "com.callmegreg.tradingup.test"),
)
builds = []
versions = set()
for scheme, configuration, bundle_id in variants:
    result = subprocess.run(
        ["xcodebuild", "-project", "TradingUp.xcodeproj", "-scheme", scheme,
         "-configuration", configuration, "-showBuildSettings", "-json"],
        check=True, capture_output=True, text=True,
    )
    settings = next(item["buildSettings"] for item in json.loads(result.stdout)
                    if item["target"] == "TradingUp")
    if settings["PRODUCT_BUNDLE_IDENTIFIER"] != bundle_id:
        raise SystemExit(f"Wrong identity for {scheme}")
    builds.append(int(settings["CURRENT_PROJECT_VERSION"]))
    versions.add(settings["MARKETING_VERSION"])
    print(f"{scheme}: project build {builds[-1]}")
if len(versions) != 1:
    raise SystemExit(f"Production/test marketing versions disagree: {versions}")

root = Path.home() / "Library/Developer/Xcode/Archives"
bundle_ids = {variant[2] for variant in variants}
highest = {bundle_id: 0 for bundle_id in bundle_ids}
for info in root.glob("*/*.xcarchive/Info.plist"):
    with info.open("rb") as stream:
        properties = plistlib.load(stream).get("ApplicationProperties", {})
    bundle_id = properties.get("CFBundleIdentifier")
    if bundle_id in bundle_ids:
        highest[bundle_id] = max(highest[bundle_id], int(properties["CFBundleVersion"]))
print(f"Highest archived builds: {highest}")
print(f"Version: {next(iter(versions))}; next SHARED build: {max(builds + list(highest.values())) + 1}")
PY
```

Local archives cannot reveal uploads from another Mac. If either app has a higher
known build in App Store Connect, use a number above it too. Record the resolved
shared number as `NEW` and the unchanged marketing version as `VERSION`.
An existing PR's valid bump is reused, not incremented on each push or on merge.
Before merging, compare it with the latest base and other releases again; if
another PR has consumed the number, update this PR to the next shared number
and let its checks run again.

## Step 2 — Set `CURRENT_PROJECT_VERSION` to the new build number

Use `apply_patch` to set **all four app-target configurations** (`Debug`, `Release`,
`Debug-Test`, `Release-Test`) to `$NEW` in `TradingUp.xcodeproj/project.pbxproj`.
Follow the `TradingUp` target's
`buildConfigurationList` to identify them; the project, unit-test, and UI-test targets
also have configurations with those names. Leave all XCTest/UI-test version numbers
untouched. Keep `MARKETING_VERSION` equal to `$VERSION` in all four app configurations.

**Never do a global replacement by numeric value.** App and automated-test target
build numbers can coincide.

Verify exactly the four intended build-number lines changed and all app versions agree:

```sh
python3 -B -m unittest discover -s tools -p test_app_identity.py
git --no-pager diff
```

## Step 3 — Commit, push, and open a PR

Commit the version file and any current-task changes the user asked to release;
stage explicit paths, never unrelated work. Push the branch and open one PR against `main`:

```sh
git add TradingUp.xcodeproj/project.pbxproj
git commit -m "Bump production and test builds to $NEW

Co-authored-by: Copilot App <223556219+Copilot@users.noreply.github.com>"
git push -u origin HEAD
```

Use the `create_pull_request` tool to open a new PR, or `update_pull_request` to
update the current PR rather than opening a second release PR. Include both environments, their
bundle IDs and schemes, the unchanged marketing version, and the shared build number.
Describe any current-task changes included in the release.

## Step 4 — Merge the PR

Wait for the current head's required checks and reviews, then squash-merge the PR.
Use `--match-head-commit` with the reviewed head SHA to avoid merging concurrent
changes accidentally:

```sh
gh pr merge --squash --match-head-commit "$PR_HEAD"
```

If branch protection blocks an immediate merge:
- Enable auto-merge and wait for required checks to pass before continuing:
  `gh pr merge --squash --auto`, then check `gh pr view --json state,mergedAt`
  until it reports `MERGED`.
- Only use `--admin` to bypass checks if the user has permission and asks for it.

Do not start the archive until the PR is actually merged.

## Step 5 — Create both code-signed archives in Xcode's Organizer location

The version bump is already committed on the current branch (and now merged), so archive from the
current clean working tree — do **not** `git switch main`, which fails in a linked worktree
when `main` is checked out in the primary checkout. Confirm its source tree matches the
merged PR. Archive **Release and Release-Test** without changing source between them,
straight into the Xcode Organizer
archives directory (`~/Library/Developer/Xcode/Archives/<date>/`) so it appears in
**Xcode → Window → Organizer**.

Read the PR's `mergeCommit.oid`, fetch it, and compare trees before archiving:

```sh
git fetch origin main
git diff --exit-code "$MERGE_COMMIT" HEAD
```

If the trees differ, do not archive stale branch contents. Integrate the merged
source in this worktree first, without discarding unrelated edits. Resolve `NEW`
and `VERSION` from the merged app configurations, not from an increment command.

```sh
export PATH="/opt/homebrew/bin:$PATH"
set -euo pipefail

DEVELOPMENT_TEAM="ACPF4NWF99"
ARCHIVE_ROOT="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
mkdir -p "$ARCHIVE_ROOT"
STAMP=$(date +%Y-%m-%d\ %H.%M.%S)
SOURCE_COMMIT=$(git rev-parse HEAD)
[ -z "$(git status --porcelain)" ]

for SCHEME in TradingUp TradingUpTest; do
  case "$SCHEME" in
    TradingUp)
      CONFIGURATION=Release
      EXPECTED_BUNDLE_ID=com.callmegreg.tradingup
      ;;
    TradingUpTest)
      CONFIGURATION=Release-Test
      EXPECTED_BUNDLE_ID=com.callmegreg.tradingup.test
      ;;
  esac
  ARCHIVE_PATH="$ARCHIVE_ROOT/$SCHEME $STAMP.xcarchive"
  xcodebuild -project TradingUp.xcodeproj -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" archive
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$ARCHIVE_PATH/Info.plist")" = "$EXPECTED_BUNDLE_ID" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE_PATH/Info.plist")" = "$NEW" ]
  [ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE_PATH/Info.plist")" = "$VERSION" ]
  codesign --verify --deep --strict "$ARCHIVE_PATH/Products/Applications/TradingUp.app"
  [ "$(git rev-parse HEAD)" = "$SOURCE_COMMIT" ]
  [ -z "$(git status --porcelain)" ]
  printf '%s (%s): %s (%s) at %s\n' "$SCHEME" "$EXPECTED_BUNDLE_ID" "$VERSION" "$NEW" "$ARCHIVE_PATH"
done
```

**Important:** this must be a real signed archive — do **not** pass `CODE_SIGNING_ALLOWED=NO`.
Because the project file carries no `DEVELOPMENT_TEAM`, you **must** pass
`DEVELOPMENT_TEAM=ACPF4NWF99` on the `xcodebuild` line as shown; omitting it makes the archive
fail with *"Signing requires a development team."* With the team supplied, `CODE_SIGN_STYLE =
Automatic` plus `-allowProvisioningUpdates` lets Xcode resolve the signing certificate and
provisioning profile.

If one archive fails, the release pair is incomplete. Retry only the failed archive
from the same unchanged commit and shared version/build; do not bump again or overwrite
the successful archive. If source changes are needed, start a new shared release number
and create both archives again.

## Step 6 — Upload the test archive to TestFlight

Use only the verified `TradingUpTest` archive from Step 5. Set `TEST_ARCHIVE` to
its exact path and `EXPORT_PATH` to a new session-artifact directory. Recheck the
identity and committed version/build immediately before upload:

```sh
set -euo pipefail
[ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleIdentifier' "$TEST_ARCHIVE/Info.plist")" = "com.callmegreg.tradingup.test" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$TEST_ARCHIVE/Info.plist")" = "$NEW" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$TEST_ARCHIVE/Info.plist")" = "$VERSION" ]
xcodebuild -exportArchive -archivePath "$TEST_ARCHIVE" \
  -exportOptionsPlist tools/TestFlightExportOptions.plist \
  -exportPath "$EXPORT_PATH" -allowProvisioningUpdates
```

The export options use automatic distribution signing and Xcode's authenticated
Apple account, upload to App Store Connect for **internal TestFlight only**, and
disable Xcode's automatic build-number management so the uploaded build stays
identical to the committed pair. `tools/ExportOptions.plist` remains the separate
local-export configuration; do not substitute a production archive.

Require a successful upload result from Apple, not just a successful archive or
local IPA export. Preserve the upload log/receipt. If processing status is
available, confirm the matching version/build on the test app's TestFlight tab;
otherwise report **uploaded, awaiting processing**, not ready for testers.
Do not create testing groups, invite testers, or submit Beta App Review as part
of this workflow; existing internal automatic-distribution settings apply.
If signing, authentication, app setup, or upload fails, report the exact blocker
and resume that step with the same verified archive. Check for an accepted upload
before retrying an ambiguous network failure to avoid duplicate submissions.

Report the common version/build, both archive paths and bundle IDs, and the test
upload outcome. The production archive stays in Organizer, unuploaded.
