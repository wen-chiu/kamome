#!/usr/bin/env bash
#
#   Scripts/release/check-archive.sh <path to .ipa or .xcarchive>
#
# The routing key must not be inside the thing that ships.
#
# Scripts/check-secrets.sh greps TRACKED SOURCE. That closes exit 1 of three
# (Docs/pre-launch.md) and says nothing about exit 3, the artifact — and exit 3
# is measured, not assumed: on 2026-08-20 two built bundles carried a plaintext
# 32-hex key in Kamome.app/Info.plist, read out with stock PlistBuddy. FairPlay
# encrypts the executable, NOT resources, so extraction from a shipped build is
# `unzip` then `plutil -p`. Three commands, no disassembly.
#
# Until 2026-09-02 the answer to that was a prose instruction to remember to
# check by hand, at the moment of highest pressure. This is that instruction as
# a command whose output is the evidence.
#
# No key is needed to run this, and none should be put in the environment for it
# (ADR 2026-10-02, "the release scan needs no key"). It used to demand the real
# key for a byte-for-byte scan, which meant a release check whose own procedure
# exported the secret into a shell — and then asked for the secret to be
# rotated. The scan below matches the key's SHAPE instead, and reaches the
# executables: a Geoapify key is 32 lowercase hex characters (VERIFIED: the two
# bundles above carried exactly that), so a key string compiled into a binary is
# found whether or not this script knows it.
#
# What that gives up: a key of another shape would pass. INFERRED that a
# rotated Geoapify key keeps the shape; the cheapest way to settle it is to look
# at the new key when it is issued.
set -uo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")/../.."

artifact="${1:-}"
if [ -z "$artifact" ] || [ ! -e "$artifact" ]; then
  kamome_fail "usage: Scripts/release/check-archive.sh <path to .ipa or .xcarchive>"
  kamome_info "Check the ARTIFACT, never the source — that is the whole point of this gate."
  exit 1
fi

root="$artifact"
tmp=""
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT
case "$artifact" in
  *.ipa)
    tmp=$(mktemp -d) || exit 1
    unzip -q "$artifact" -d "$tmp" || { kamome_fail "could not unzip $artifact"; exit 1; }
    root="$tmp"
    ;;
esac

failures=0

# 1. A key-shaped string in any executable inside the app — the main binary and
#    every framework's. A 32-hex run bounded by non-hex bytes, so a SHA-1 or a
#    UUID without dashes is not read as a key; a compiled C string is NUL-bounded,
#    which is non-hex. Only Mach-O files: measured on a built archive, the
#    shipped executables carry none, the dSYM (which is not shipped) carries
#    thousands, and a framework's compiled asset catalog carries a few — none of
#    them credentials, all of them noise a gate cannot be allowed to make.
hexrun='(^|[^0-9a-fA-F])[0-9a-f]{32}([^0-9a-fA-F]|$)'
scanned=0
binhits=""
while IFS= read -r f; do
  [ "$(file -b --mime-type "$f" 2>/dev/null)" = "application/x-mach-binary" ] || continue
  scanned=$((scanned + 1))
  if LC_ALL=C grep -qaE "$hexrun" "$f" 2>/dev/null; then
    binhits="${binhits}${f}"$'\n'
  fi
done < <(find "$root" -path '*.app/*' -type f 2>/dev/null)
if [ "$scanned" -eq 0 ]; then
  kamome_fail "no executable found inside a .app in the artifact — nothing was scanned"
  kamome_info "A scan that measured nothing is not a pass. Is this an app archive?"
  failures=$((failures + 1))
elif [ -n "$binhits" ]; then
  kamome_fail "a key-shaped (32-hex) string is INSIDE an executable:"
  printf '%s' "$binhits" | sed "s|^$root|  |" | while read -r f; do kamome_info "$f"; done
  kamome_info "Adjudicate it — a hash is fine, a credential is not. If it is the routing key,"
  kamome_info "this build is burned: do not upload it, and find what put the key in the build."
  failures=$((failures + 1))
else
  kamome_ok "no key-shaped string in any of $scanned executables"
fi

# 2. The Info.plist field the app used to read, structurally. Since ADR 2026-09-12
#    no build input defines it, so it must be ABSENT: present-but-empty means the
#    mapping came back, one machine-local secrets file away from carrying a key.
plists=$(find "$root" -name Info.plist -path '*.app/*' 2>/dev/null || true)
if [ -z "$plists" ]; then
  kamome_fail "no Kamome.app/Info.plist found inside the artifact — is this an app archive?"
  failures=$((failures + 1))
else
  bad=0
  while read -r plist; do
    if /usr/libexec/PlistBuddy -c "Print :KamomeRoutingAPIKey" "$plist" >/dev/null 2>&1; then
      value=$(/usr/libexec/PlistBuddy -c "Print :KamomeRoutingAPIKey" "$plist" 2>/dev/null || true)
      kamome_fail "KamomeRoutingAPIKey is defined in ${plist#"$root"} (${#value} chars)"
      bad=1
    fi
  done <<< "$plists"
  if [ "$bad" -eq 0 ]; then
    kamome_ok "no bundled Info.plist defines KamomeRoutingAPIKey"
  else
    kamome_info "No build input may map it (ADR 2026-09-12) — was this archive built from older source?"
    failures=$((failures + 1))
  fi
fi

# 3. The shipped config, not the source one — check-routing-endpoint.sh reads the
#    repository, which a working-tree edit or a stale build would diverge from.
config=$(find "$root" -name TrackingConfig.json 2>/dev/null | head -1)
if [ -z "$config" ]; then
  kamome_fail "TrackingConfig.json is not bundled in the artifact"
  failures=$((failures + 1))
else
  url=$(/usr/bin/env python3 -c \
    'import json,sys; print(json.load(open(sys.argv[1]))["matching"]["base_url"])' "$config" 2>/dev/null || echo "?")
  case "$url" in
    https://*) kamome_ok "the shipped matching.base_url is \"$url\"" ;;
    "")        kamome_fail "the shipped matching.base_url is \"\" — routing is off, or the Worker was never wired"
               kamome_info "Docs/release-readiness.md S5: the per-day budget counter lands with or before this flip."
               failures=$((failures + 1)) ;;
    *)         kamome_fail "the shipped matching.base_url is not distributable: \"$url\""
               failures=$((failures + 1)) ;;
  esac
fi

# 4. A key-shaped string where a key would actually land. Text resources only —
#    a 32-hex run inside a Mach-O or a PNG is noise, and a noisy gate gets ignored.
shaped=$(find "$root" \( -name '*.plist' -o -name '*.json' -o -name '*.strings' -o -name '*.xcconfig' \) \
  -exec grep -lE '[0-9a-f]{32}' {} + 2>/dev/null || true)
if [ -n "$shaped" ]; then
  kamome_fail "a key-shaped (32-hex) string is in a bundled text resource:"
  printf '%s\n' "$shaped" | sed "s|^$root|  |" | while read -r f; do kamome_info "$f"; done
  kamome_info "Adjudicate each — a hash is fine, a credential is not."
  failures=$((failures + 1))
else
  kamome_ok "no key-shaped string in any bundled plist, json, strings or xcconfig"
fi

# 5. The local-network permission is Debug-only (ADR 2026-09-12 (b)). The release
#    guard in AppConfig.loadOrDie makes a LAN endpoint impossible outside Debug,
#    so in a shipped plist the purpose string is untrue to a reviewer and the ATS
#    exemption buys nothing. A Debug-only build phase adds both; this is the check
#    that it stayed Debug-only in the thing that ships.
if [ -n "$plists" ]; then
  lan=0
  while read -r plist; do
    for entry in NSAppTransportSecurity:NSAllowsLocalNetworking NSLocalNetworkUsageDescription; do
      if /usr/libexec/PlistBuddy -c "Print :$entry" "$plist" >/dev/null 2>&1; then
        kamome_fail "$entry is set in ${plist#"$root"} — the local-network permission is Debug-only"
        lan=1
      fi
    done
  done <<< "$plists"
  if [ "$lan" -eq 0 ]; then
    kamome_ok "no bundled Info.plist carries the local-network permission"
  else
    kamome_info "Was this built from the Debug configuration? project.yml, \"Debug only: local-network permission\"."
    failures=$((failures + 1))
  fi
fi

# 6. The map-region side-load is a testing feature (arch review 2026-09-24). With
#    it on, the Documents folder is open in Finder and a .pmtiles file dropped
#    there overrides OpenFreeMap in the film. KAMOME_SIDELOAD_REGIONS=YES is how a
#    testing build is made on purpose; this is the check that such a build is
#    never the one submitted.
if [ -n "$plists" ]; then
  sideload=0
  while read -r plist; do
    for entry in UIFileSharingEnabled LSSupportsOpeningDocumentsInPlace; do
      if /usr/libexec/PlistBuddy -c "Print :$entry" "$plist" >/dev/null 2>&1; then
        kamome_fail "$entry is set in ${plist#"$root"} — the map-region side-load is a testing switch"
        sideload=1
      fi
    done
  done <<< "$plists"
  if [ "$sideload" -eq 0 ]; then
    kamome_ok "no bundled Info.plist opens the side-load folder"
  else
    kamome_info "Was this archived with KAMOME_SIDELOAD_REGIONS=YES? project.yml, \"Switch: side-loaded map regions\"."
    failures=$((failures + 1))
  fi
fi

[ "$failures" -eq 0 ] && exit 0
exit 1
