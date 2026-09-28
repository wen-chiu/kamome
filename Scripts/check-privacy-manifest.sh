#!/usr/bin/env bash
# Every required-reason API the app's own code calls is declared in
# App/PrivacyInfo.xcprivacy.
#
# App Store Connect refuses an upload whose binary calls a required-reason API
# the manifest does not declare (ITMS-91053). `ProcessInfo.systemUptime` arrived
# on 2026-09-26 (ThermalWatch, MapSubstrateMeter) with no declaration, and
# nothing noticed: the build, the tests and the simulator are all indifferent.
# Found by the release review of 2026-09-28. Scans App/, Core/ and UI/ — the
# sources compiled into the app; GRDB and MapLibre ship their own manifests.
#
# The table maps a source pattern to the category it needs, after Apple's
# "Describing use of required reason API". It is deliberately a superset of
# what the app calls today, so the next call is caught the day it lands.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

manifest=App/PrivacyInfo.xcprivacy
if ! plutil -lint "$manifest" >/dev/null 2>&1; then
  kamome_fail "$manifest is missing or not a valid plist"
  exit 1
fi

declared=$(grep -o 'NSPrivacyAccessedAPICategory[A-Za-z]*' "$manifest" | sort -u)

failed=0
check() {
  local category=$1 pattern=$2
  local hits
  hits=$(git ls-files 'App/*.swift' 'Core/*.swift' 'UI/*.swift' \
    | xargs grep -nE "$pattern" 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*//' || true)
  [ -z "$hits" ] && return 0
  if grep -qx "$category" <<<"$declared"; then
    kamome_ok "$category declared ($(wc -l <<<"$hits" | tr -d ' ') call site(s))"
  else
    kamome_fail "$category is used but not declared in $manifest:"
    while IFS= read -r line; do kamome_info "$line"; done <<<"$hits"
    failed=1
  fi
}

check NSPrivacyAccessedAPICategorySystemBootTime 'systemUptime|mach_absolute_time'
check NSPrivacyAccessedAPICategoryUserDefaults   'UserDefaults|@AppStorage'
check NSPrivacyAccessedAPICategoryFileTimestamp  '\.(creationDate|modificationDate)Key|contentModificationDate|fileModificationDate|FileAttributeKey\.(creationDate|modificationDate)|getattrlist\(|fstatat\('
check NSPrivacyAccessedAPICategoryDiskSpace      'volumeAvailableCapacity|systemFreeSize|systemSize\b|statfs'
check NSPrivacyAccessedAPICategoryActiveKeyboards 'activeInputModes'

exit $failed
