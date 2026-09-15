#!/usr/bin/env bash
# No routing key is committed — and since ADR 2026-09-12, none has a way into a
# build either.
#
# Config/Secrets.xcconfig is gitignored and must never be tracked: it may still
# exist, holding a real key, on a machine that built before that ADR. A
# key-shaped value in any tracked xcconfig is the same failure by another route.
#
# The build path is checked on its own, with or without a key in sight: a line
# mapping the key into Info.plist, or an xcconfig including the secrets file,
# puts a real key back into every archive built on a machine that has one —
# exactly the state the config flip was meant to end. RoutingKeyTests holds the
# same line inside the built app; this holds it at the commit, with no Xcode.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

if git ls-files --error-unmatch Config/Secrets.xcconfig >/dev/null 2>&1; then
  kamome_fail "Config/Secrets.xcconfig is tracked — it must be gitignored"
  exit 1
fi

# A real Geoapify key is 32 hex characters. Templates included: there are none
# now, and one that came back holding a key is the same leak.
key_shaped='KAMOME_ROUTING_API_KEY\s*=\s*[0-9a-f]{32,}'
if git grep -lP "$key_shaped" -- '*.xcconfig' '*.xcconfig.*' >/dev/null 2>&1; then
  kamome_fail "a tracked xcconfig contains a key-shaped value"
  git grep -lP "$key_shaped" -- '*.xcconfig' '*.xcconfig.*' >&2
  exit 1
fi

# The build path. Comment lines are skipped (`#` in YAML, `//` in xcconfig) so
# the history can still be explained where it happened.
mapping='^[^#]*(KamomeRoutingAPIKey|KAMOME_ROUTING_API_KEY)'
include='^[[:space:]]*(#include\??[[:space:]]*"[^"]*Secrets\.xcconfig"|[^/]*KAMOME_ROUTING_API_KEY)'
found=$(
  { git grep -nE "$mapping" -- project.yml App/Info.plist || true
    git grep -nE "$include" -- '*.xcconfig' || true; } 2>/dev/null
)
if [ -n "$found" ]; then
  kamome_fail "a build input gives the routing key a way into the app (ADR 2026-09-12):"
  printf '%s\n' "$found" | while read -r line; do kamome_info "$line"; done
  exit 1
fi

kamome_ok "no routing key is tracked, and no build input maps one into the app"
