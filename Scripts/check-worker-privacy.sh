#!/usr/bin/env bash
# The routing Worker's no-log properties, asserted instead of remembered
# (`Docs/release-readiness.md` S4).
#
# `/v1/routing` is GET-only, so a trip's real coordinates travel in the URL —
# the most-logged part of an HTTP request. A proxy that logs makes §0 worse
# while appearing to make it better, which is why three settings are
# load-bearing and all three were prose until now:
#
#   1. `[observability] enabled = false` — Workers Logs record request URLs.
#      Cloudflare's default is ON, so leaving this out is not a neutral omission.
#   2. `preview_urls = false` — each versioned deploy would otherwise get a
#      permanent public hostname running the same code with the same key
#      binding (measured 2026-08-27: a preview host answered a keyless
#      `GET /v1/routing` with 200 and a route body).
#   3. No `console.*` in the handler — the Worker writing its own request line
#      would defeat 1.
#
# ⚠️ **What this gate does NOT establish**, and no repository gate can: what
# Cloudflare retains at the account level (Logpush, zone analytics), and whether
# anyone has run `wrangler tail` against production. Those live in an account
# this repository cannot see. `Deploy/worker/README.md` carries them, and
# `HANDOFF.md` carries the residue.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

toml="Deploy/worker/wrangler.toml"
src="Deploy/worker/src"

# Comments are stripped first, so a setting *discussed* in a comment can never
# satisfy this gate — that file explains all three at length.
settings=$(awk '
  { sub(/#.*/, "") }
  /^[[:space:]]*\[/ { section = $0; gsub(/[][[:space:]]/, "", section); next }
  /=/ {
    key = $0; sub(/=.*/, "", key); gsub(/[[:space:]"]/, "", key)
    value = $0; sub(/.*=/, "", value); gsub(/[[:space:]"]/, "", value)
    print section "|" key "|" value
  }
' "$toml")

require_setting() {
  local section="$1" key="$2" want="$3" what="$4"
  local got
  got=$(printf '%s\n' "$settings" | awk -F'|' -v s="$section" -v k="$key" '$1 == s && $2 == k { print $3 }')
  if [ "$got" = "$want" ]; then
    kamome_ok "$what"
    return 0
  fi
  if [ -z "$got" ]; then
    kamome_fail "$toml does not set ${key} — Cloudflare's default is not the safe one"
  else
    kamome_fail "$toml has ${key} = ${got}, must be ${want} — $what"
  fi
  return 1
}

status=0
require_setting observability enabled false \
  "Worker logging is off in the deployed config: [observability] enabled = false" || status=1
require_setting "" preview_urls false \
  "Worker preview URLs are off: preview_urls = false" || status=1

if calls=$(grep -rn 'console\.' "$src"); then
  kamome_fail "the Worker writes its own log lines, and a request line here is a trip's coordinates:"
  printf '%s\n' "$calls" | while IFS= read -r line; do kamome_info "$line"; done
  status=1
else
  kamome_ok "no console.* call in $src/ ($(find "$src" -name '*.js' | wc -l | tr -d ' ') file)"
fi

exit $status
