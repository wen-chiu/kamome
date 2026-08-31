#!/usr/bin/env bash
# The documents a session must read at start stay small enough to be read.
#
# Measured in BYTES, not lines. Line counts are what these files were already
# gaming: Arch.md's three longest lines were 519, 339 and 334 characters, so a
# line budget rewarded unwrapping rather than cutting. Bytes are roughly
# proportional to what a session actually spends reading.
#
# One charter is read per session, so the charters do not add up — but each is a
# whole session's governing document and has to fit in working memory.
#
# Over budget never means delete: move the detail into a Docs/ topic document
# and leave a pointer, or move a closed section to Docs/_archive/.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

status=0

budget() {
  local file="$1" limit="$2" purpose="$3"
  local size
  size=$(wc -c < "$file" | tr -d '[:space:]')
  if [ "$size" -gt "$limit" ]; then
    kamome_fail "$file is $size bytes, over its $limit-byte budget ($purpose)"
    status=1
  else
    kamome_ok "$(printf '%-12s %6d / %6d bytes' "$file" "$size" "$limit")"
  fi
}

budget CLAUDE.md    5500 "read at the start of every session"
# Raised 14,000 → 16,000 once, on 2026-08-31, when a second engineering
# session's findings landed on main and the index legitimately gained five live
# items. Two entries were merged into one first (saving 383 bytes); the rest is
# content, and navigation is only 12% of the file. This is a ceiling on what a
# session reads, not an allowance to fill — the next time it binds, the answer
# is to archive a closed item, not to raise it again.
budget HANDOFF.md  16000 "read at the start of every session"
budget Arch.md     10000 "the engineering charter"
budget PO.md       12000 "the product-owner charter"
budget DESIGNER.md  9000 "the visual charter"

exit $status
