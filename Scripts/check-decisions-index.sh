#!/usr/bin/env bash
# Decisions stay findable.
#
# 1. Docs/decisions.md is FROZEN at 2026-09-28 (ADR of that date, its last
#    entry). It reached 413 KB and 108 entries, and every PR with a decision
#    appended to the same file and the same index — a conflict point for every
#    parallel branch. It is history now: nothing is added to it.
# 2. Docs/decisions-index.md has one row per frozen entry, so the ledger stays
#    usable without reading it whole.
# 3. New decisions are one file each, Docs/adr/YYYY-MM-DD-<slug>.md, with a
#    "# " title and a "Status:" line. The directory listing is the index — no
#    shared file to edit, so two branches never collide on it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

frozen_entries=108
status=0

adrs=$(grep -c '^## ' Docs/decisions.md)
rows=$(grep -cE '^\| [0-9]+ \| ' Docs/decisions-index.md)

if [ "$adrs" -ne "$frozen_entries" ]; then
  kamome_fail "Docs/decisions.md has $adrs entries; it is frozen at $frozen_entries"
  kamome_info "A new decision is a new file in Docs/adr/ (format: Docs/adr/README.md)."
  status=1
elif [ "$adrs" -ne "$rows" ]; then
  kamome_fail "Docs/decisions.md has $adrs entries; Docs/decisions-index.md has $rows rows"
  status=1
else
  kamome_ok "decisions.md frozen at $adrs entries, all indexed"
fi

count=0
for f in Docs/adr/*.md; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  [ "$name" = "README.md" ] && continue
  count=$((count + 1))
  if ! [[ "$name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9-]+\.md$ ]]; then
    kamome_fail "$f: name must be YYYY-MM-DD-<lowercase-slug>.md"
    status=1
  fi
  if ! head -1 "$f" | grep -qE '^# .+'; then
    kamome_fail "$f: first line must be the '# ' title"
    status=1
  fi
  if ! grep -qE '^\*\*Status:\*\* ' "$f"; then
    kamome_fail "$f: needs a '**Status:** ' line (Decided / Draft / Superseded by …)"
    status=1
  fi
done
[ "$status" -eq 0 ] && kamome_ok "Docs/adr/ holds $count ADR file(s), each well-formed"

exit $status
