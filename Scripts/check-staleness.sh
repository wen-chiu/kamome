#!/usr/bin/env bash
# Docs/current-state.md's "Last synced" line, checked instead of remembered.
#
# The line must name the NEWEST decision. When an ADR lands, the snapshot it
# changes is updated in the same PR — that is the whole protocol.
#
# Until 2026-09-28 the line also had to name the newest merged PR (one behind
# allowed). That half made every PR edit the same line, which is exactly the
# conflict parallel sessions kept hitting, and the line grew into a changelog
# nobody read (ADR 2026-09-28). The merge history is `git log --merges`; the
# open work is GitHub Issues. Only the decision half survives, because a
# snapshot that has not absorbed the newest decision is genuinely stale.
#
# Decisions live in two places: Docs/decisions.md (frozen 2026-09-28) and one
# file per ADR in Docs/adr/YYYY-MM-DD-<slug>.md. The newest is the later date;
# on a tie between files, any file of that date counts as newest.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

state="Docs/current-state.md"

claim=$(tr '\n' ' ' < "$state" | grep -oE 'Last synced: [0-9]{4}-[0-9]{2}-[0-9]{2} against ADR \*\*[^*]+\*\*' | head -1)
if [ -z "$claim" ]; then
  kamome_fail "$state has no parsable \"Last synced\" line"
  kamome_info 'Expected: Last synced: <date> against ADR **<YYYY-MM-DD[ (x)] or YYYY-MM-DD-slug>**'
  exit 1
fi
claimed=$(printf '%s' "$claim" | sed -E 's/.*against ADR \*\*([^*]+)\*\*.*/\1/')
claimed_date=${claimed:0:10}

ledger_newest=$(grep -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}( \([a-z]\))?' Docs/decisions.md | tail -1 | sed 's/^## //')
newest="$ledger_newest"
adr_newest=""
if ls Docs/adr/[0-9]*.md >/dev/null 2>&1; then
  adr_newest=$(ls Docs/adr/[0-9]*.md | sed 's#Docs/adr/##; s#\.md$##' | sort | tail -1)
  if [[ "${adr_newest:0:10}" > "${ledger_newest:0:10}" ]] || [[ "${adr_newest:0:10}" == "${ledger_newest:0:10}" ]]; then
    newest="$adr_newest"
  fi
fi

if [ "$claimed" = "$newest" ]; then
  kamome_ok "current-state is synced to the newest ADR ($newest)"
  exit 0
fi
# Several ADR files on the newest date: naming any one of them is synced.
if [ -n "$adr_newest" ] && [ "$claimed_date" = "${newest:0:10}" ] && [ -f "Docs/adr/$claimed.md" ]; then
  kamome_ok "current-state is synced to the newest ADR date ($claimed)"
  exit 0
fi

kamome_fail "current-state names ADR \"$claimed\"; the newest is \"$newest\""
kamome_info "The newest decision wins. Re-read it, update what it changes in $state,"
kamome_info "THEN set the line. Bumping only the name is the failure this check exists to catch."
exit 1
