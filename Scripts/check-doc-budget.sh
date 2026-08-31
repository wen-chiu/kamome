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
budget HANDOFF.md  14000 "read at the start of every session"
budget Arch.md     10000 "the engineering charter"
budget PO.md       12000 "the product-owner charter"
budget DESIGNER.md  9000 "the visual charter"

exit $status
