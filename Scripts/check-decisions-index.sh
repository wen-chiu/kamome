#!/usr/bin/env bash
# Docs/decisions-index.md has one row per ADR.
#
# The index is what makes a 141 KB append-only ledger usable without reading it
# whole. An index that silently falls behind the ledger is worse than none: it
# reads as complete while hiding the newest decision, which is precisely the one
# that wins.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

adrs=$(grep -c '^## ' Docs/decisions.md)
rows=$(grep -cE '^\| [0-9]+ \| ' Docs/decisions-index.md)

if [ "$adrs" -eq "$rows" ]; then
  kamome_ok "decisions-index.md covers all $adrs ledger entries"
  exit 0
fi

kamome_fail "Docs/decisions.md has $adrs entries; Docs/decisions-index.md has $rows rows"
kamome_info "Add a row for every new ADR in the same commit that writes it."
exit 1
