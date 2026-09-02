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
# The strongest check here is the EXACT one: the real key, matched byte for byte
# across every file including binaries. A shape scan alone would be both weaker
# and noisier, so the exact scan is required rather than best-effort — if the key
# cannot be read, this exits non-zero rather than passing with a gap in it.
set -uo pipefail
source "$(dirname "$0")/../lib.sh"
cd "$(dirname "$0")/../.."

artifact="${1:-}"
if [ -z "$artifact" ] || [ ! -e "$artifact" ]; then
  kamome_fail "usage: Scripts/release/check-archive.sh <path to .ipa or .xcarchive>"
  kamome_info "Check the ARTIFACT, never the source — that is the whole point of this gate."
  exit 1
fi

# The key, for the exact scan. Secrets.xcconfig is gitignored and lives on the
# machine that built the archive, which is the machine running this.
key="${KAMOME_ROUTING_API_KEY:-}"
if [ -z "$key" ] && [ -f Config/Secrets.xcconfig ]; then
  key=$(sed -n 's/^[[:space:]]*KAMOME_ROUTING_API_KEY[[:space:]]*=[[:space:]]*//p' Config/Secrets.xcconfig \
        | tr -d '[:space:]' | head -1)
fi
if [ -z "$key" ]; then
  kamome_fail "no routing key available, so the exact scan cannot run"
  kamome_info "Provide it via Config/Secrets.xcconfig or KAMOME_ROUTING_API_KEY."
  kamome_info "A shape scan alone is not this gate — it would pass a key of another shape."
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

# 1. The exact key, every file, binaries included.
hits=$(grep -rlaF "$key" "$root" 2>/dev/null || true)
if [ -n "$hits" ]; then
  kamome_fail "the routing key is INSIDE the artifact:"
  printf '%s\n' "$hits" | sed "s|^$root|  |" | while read -r f; do kamome_info "$f"; done
  kamome_info "Rotate the key (pre-launch.md item 7) — this build is burned."
  failures=$((failures + 1))
else
  kamome_ok "the routing key does not appear anywhere in the artifact"
fi

# 2. The Info.plist field the app reads, structurally.
plists=$(find "$root" -name Info.plist -path '*.app/*' 2>/dev/null || true)
if [ -z "$plists" ]; then
  kamome_fail "no Kamome.app/Info.plist found inside the artifact — is this an app archive?"
  failures=$((failures + 1))
else
  bad=0
  while read -r plist; do
    value=$(/usr/libexec/PlistBuddy -c "Print :KamomeRoutingAPIKey" "$plist" 2>/dev/null || true)
    if [ -n "$value" ]; then
      kamome_fail "KamomeRoutingAPIKey is set in ${plist#"$root"} (${#value} chars)"
      bad=1
    fi
  done <<< "$plists"
  if [ "$bad" -eq 0 ]; then
    kamome_ok "KamomeRoutingAPIKey is absent or empty in every bundled Info.plist"
  else
    kamome_info "The app reads this at App/KamomeApp.swift:69. It must reach the Worker instead."
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

[ "$failures" -eq 0 ] && exit 0
exit 1
