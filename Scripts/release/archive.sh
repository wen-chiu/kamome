#!/usr/bin/env bash
#
#   Scripts/release/archive.sh             archive → ./check.sh --release → export .ipa
#   Scripts/release/archive.sh --upload    …then upload to App Store Connect (TestFlight)
#   Scripts/release/archive.sh --upload patch     also choose the version: major, minor,
#                                                 patch, or 1.4.2 (none = ask, with a suggestion)
#
# One command from a clean `main` to a signed build, no Xcode UI. Signing is
# automatic with the team in project.yml (override: KAMOME_TEAM_ID=XXXXXXXXXX);
# `-allowProvisioningUpdates` lets xcodebuild fetch or renew certificates and
# profiles through the Apple ID signed in to Xcode (Settings → Accounts) — the
# same thing Organizer does, so nothing to configure beyond that.
#
# Version: Config/Version.xcconfig. Choosing a different one here bumps the file,
# commits "Version X" on main and pushes it (before an upload), so there is no
# separate set-version / commit / PR step; a tag vX marks an uploaded version.
# Build number: the
# commit count, stamped by the build — which is why the tree must be clean (the
# number would name code that was never committed) and why an upload must come
# from `main` (a branch counts higher than the main it later merges into, and
# App Store Connect refuses a number that goes backwards).
#
# The archive lands where Organizer shows it; the .ipa and logs next to it in
# build/release/. The routing key is read from ~/.kamome/routing.env for the
# release gate alone and never reaches the build (ADR 2026-09-12).
set -euo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")/../.."

upload=0; choice=""
for arg in "$@"; do
  case "$arg" in
    --upload) upload=1 ;;
    -h | --help) sed -n '3,6p' "$0" | sed 's/^# //'; exit 0 ;;
    -*) sed -n '3,6p' "$0" | sed 's/^# //'; exit 2 ;;
    *) choice="$arg" ;;
  esac
done

team=${KAMOME_TEAM_ID:-$(sed -n 's/^ *DEVELOPMENT_TEAM: *//p' project.yml | head -1)}
[ -n "$team" ] || { kamome_fail "no DEVELOPMENT_TEAM in project.yml and no KAMOME_TEAM_ID"; exit 1; }

if [ -n "$(git status --porcelain)" ]; then
  kamome_fail "uncommitted changes — the build number is the commit count and would name code that is not in any commit"
  git status --short >&2
  exit 1
fi
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$upload" -eq 1 ] && [ "$branch" != "main" ]; then
  kamome_fail "upload from '$branch' — uploads come from main only (a branch's commit count can run ahead of main's)"
  exit 1
fi
[ "$(git rev-parse --is-shallow-repository)" = "false" ] \
  || { kamome_fail "shallow clone — run: git fetch --unshallow"; exit 1; }

current=$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
if [ -z "$choice" ] && [ -t 0 ]; then
  # Suggest: a version already tagged as uploaded needs a new one; otherwise keep it.
  if git rev-parse -q --verify "refs/tags/v$current" > /dev/null; then
    suggest=patch; hint="v$current is already uploaded"
  else
    suggest=keep; hint="v$current not uploaded yet"
  fi
  n_patch=$(Scripts/set-version.sh --dry patch)
  n_minor=$(Scripts/set-version.sh --dry minor)
  n_major=$(Scripts/set-version.sh --dry major)
  printf 'Version is %s (%s). Suggested: %s.\n' "$current" "$hint" "$suggest"
  printf '  [Enter] %s   patch → %s   minor → %s   major → %s   or type a version: ' \
    "$([ "$suggest" = keep ] && echo "keep $current" || echo "$suggest")" "$n_patch" "$n_minor" "$n_major"
  read -r choice
  choice=${choice:-$suggest}
fi
[ "$choice" = keep ] && choice=""

if [ -n "$choice" ]; then
  [ "$branch" = "main" ] || { kamome_fail "choosing a version commits to main — you are on '$branch'"; exit 1; }
  git fetch -q origin main
  [ "$(git rev-list --count HEAD..origin/main)" = 0 ] || { kamome_fail "main is behind origin — run: git pull"; exit 1; }
  Scripts/set-version.sh "$choice"
  version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
  git commit -qam "Version $version"
  # The push waits for --upload so an export-only run leaves nothing published.
fi
if [ "$upload" -eq 1 ]; then
  git fetch -q origin main
  [ "$(git rev-list --count origin/main..HEAD)" = 0 ] || git push -q origin main
fi

version=$(sed -n 's/^MARKETING_VERSION = //p' Config/Version.xcconfig)
build=$(git rev-list --count HEAD)
name="Kamome $version ($build)"
archive="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/$name.xcarchive"
out="build/release/$version-$build"
mkdir -p "$out"
kamome_info "$name — team $team, branch $branch, $(git rev-parse --short HEAD)"

stage() { printf '\n\033[1m%s\033[0m\n' "$*"; }
# The build log goes to a file; on failure only its errors are shown.
run_logged() {
  local log="$1"; shift
  if ! env -u KAMOME_ROUTING_API_KEY "$@" > "$log" 2>&1; then
    grep -E "error:|\*\* .* FAILED \*\*" "$log" | head -20 >&2
    kamome_fail "failed — full log: $log"
    exit 1
  fi
}

stage "Archive"
xcodegen generate --quiet
run_logged "$out/archive.log" xcodebuild archive \
  -scheme Kamome -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$team" CODE_SIGN_STYLE=Automatic
stamped=$(plutil -extract CFBundleVersion raw "$archive/Products/Applications/Kamome.app/Info.plist")
[ "$stamped" = "$build" ] || { kamome_fail "archive carries build $stamped, expected $build"; exit 1; }
kamome_ok "$archive"

stage "Checks — ./check.sh --release"
key=$(sed -n 's/^GEOAPIFY_API_KEY=//p' "$HOME/.kamome/routing.env" 2>/dev/null || true)
[ -n "$key" ] || { kamome_fail "no GEOAPIFY_API_KEY in ~/.kamome/routing.env — the archive key scan cannot run"; exit 1; }
KAMOME_ROUTING_API_KEY="$key" ./check.sh --release "$archive" > "$out/check.log" 2>&1 || {
  grep -E "FAIL|failed" "$out/check.log" | head -20 >&2
  kamome_fail "release checks failed — full log: $out/check.log. Nothing exported."
  exit 1
}
kamome_ok "all checks passed, including the release gates on the archive"

stage "Export"
destination=export; [ "$upload" -eq 1 ] && destination=upload
cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
run_logged "$out/export.log" xcodebuild -exportArchive \
  -archivePath "$archive" -exportPath "$out" \
  -exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates

if [ "$upload" -eq 1 ]; then
  git tag -f "v$version" > /dev/null && git push -q -f origin "v$version"
  kamome_ok "$name uploaded to App Store Connect — TestFlight lists it once processing finishes"
else
  kamome_ok "$out/Kamome.ipa — not uploaded. To upload: Scripts/release/archive.sh --upload (from main)"
fi
