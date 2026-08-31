#!/usr/bin/env bash
# No routing key is committed, by either path.
#
# Config/Secrets.xcconfig is gitignored and must never be tracked. A key-shaped
# value in any tracked xcconfig is the same failure by a different route.
# RoutingKeyTests catches this during local development; this catches the commit.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

if git ls-files --error-unmatch Config/Secrets.xcconfig >/dev/null 2>&1; then
  kamome_fail "Config/Secrets.xcconfig is tracked — it must be gitignored"
  exit 1
fi

# A real Geoapify key is 32 hex characters. The placeholder and the empty
# default are both shorter and non-hex, so they pass.
if git grep -lP 'KAMOME_ROUTING_API_KEY\s*=\s*[0-9a-f]{32,}' -- '*.xcconfig' ':!*.example' >/dev/null 2>&1; then
  kamome_fail "a tracked xcconfig contains a key-shaped value"
  git grep -lP 'KAMOME_ROUTING_API_KEY\s*=\s*[0-9a-f]{32,}' -- '*.xcconfig' ':!*.example' >&2
  exit 1
fi

kamome_ok "no routing key is tracked"
