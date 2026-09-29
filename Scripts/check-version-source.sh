#!/usr/bin/env bash
# The app's version has one home: Config/Version.xcconfig. A MARKETING_VERSION
# or CURRENT_PROJECT_VERSION in project.yml would silently override it, and the
# number that ships would no longer be the one Scripts/set-version.sh wrote.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

status=0
file="Config/Version.xcconfig"
if grep -nE '^[[:space:]]*(MARKETING_VERSION|CURRENT_PROJECT_VERSION):' project.yml; then
  kamome_fail "project.yml sets the version — it belongs in $file only"
  status=1
fi
grep -q '^#include "Version.xcconfig"' Config/Base.xcconfig \
  || { kamome_fail "Config/Base.xcconfig no longer includes Version.xcconfig"; status=1; }
grep -qE '^MARKETING_VERSION = [0-9]+(\.[0-9]+){0,2}$' "$file" \
  || { kamome_fail "$file: MARKETING_VERSION missing or not N[.N[.N]]"; status=1; }
grep -q 'name: Build number = commit count' project.yml \
  || { kamome_fail "project.yml lost the phase that stamps the build number"; status=1; }

[ "$status" -eq 0 ] && kamome_ok "version: one source, $file ($(sed -n 's/^MARKETING_VERSION = //p' "$file")); build number = commit count"
exit "$status"
