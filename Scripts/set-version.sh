#!/usr/bin/env bash
#
#   Scripts/set-version.sh minor      0.1   → 0.2
#   Scripts/set-version.sh patch      0.2   → 0.2.1
#   Scripts/set-version.sh major      0.2.1 → 1.0
#   Scripts/set-version.sh 1.4.2      exactly this
#   Scripts/set-version.sh            show the version and the build number the next build gets
#
# Writes Config/Version.xcconfig, the only place the version lives. No
# `xcodegen generate` needed: Xcode reads the xcconfig on the next build. The
# build number needs nothing — every build stamps the commit count.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

file="Config/Version.xcconfig"
current=$(sed -n 's/^MARKETING_VERSION = //p' "$file")
IFS=. read -r major minor patch <<< "$current"
minor=${minor:-0}; patch=${patch:-0}

dry=0; [ "${1:-}" = "--dry" ] && { dry=1; shift; }
case "${1:-}" in
  "")
    kamome_info "version $current, next build $(git rev-list --count HEAD) (commit count of HEAD)"
    exit 0 ;;
  -h | --help) sed -n '3,7p' "$0" | sed 's/^# //'; exit 0 ;;
  major) version="$((major + 1)).0" ;;
  minor) version="$major.$((minor + 1))" ;;
  patch) version="$major.$minor.$((patch + 1))" ;;
  *)     version="$1" ;;
esac

# App Store Connect: up to three period-separated integers.
if ! [[ "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
  kamome_fail "'$version' is not a version App Store Connect accepts — use major, minor, patch, or e.g. 1.0.3"
  exit 1
fi

if [ "${dry:-0}" = 1 ]; then echo "$version"; exit 0; fi
sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $version/" "$file"
kamome_ok "version $current → $version in $file (next build $(git rev-list --count HEAD))"
