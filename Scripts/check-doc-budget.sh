#!/usr/bin/env bash
# The documents a session must read at start stay small enough to be read.
#
# This is the rule that discipline could not hold. HANDOFF.md was trimmed from
# 1,961 to ~915 lines by hand and was back over 1,400 within days. A budget
# that is not enforced is not a budget.
#
# Over budget does not mean "delete": move the detail to a topic document under
# Docs/ and leave a pointer, or move a closed section to Docs/_archive/.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

status=0

budget() {
  local file="$1" limit="$2" purpose="$3"
  local lines
  lines=$(wc -l < "$file" | tr -d '[:space:]')
  if [ "$lines" -gt "$limit" ]; then
    kamome_fail "$file is $lines lines, over its $limit-line budget ($purpose)"
    status=1
  else
    kamome_ok "$file is $lines/$limit lines"
  fi
}

budget CLAUDE.md  80  "read at the start of every session"
budget HANDOFF.md 300 "read at the start of every session"

# One charter is read per session, so these do not add up — but each is a whole
# session's governing document and has to fit in working memory. 180 is where
# Arch.md and DESIGNER.md actually sit; it is a working charter's size.
budget Arch.md     180 "the engineering charter"
budget DESIGNER.md 180 "the visual charter"

# PO.md is the outlier at 481 lines — it grew the way HANDOFF.md grew, by
# carrying its stories inline. This is a ratchet at today's size with no
# headroom: it cannot grow, and the next addition has to trim something first.
# Slimming it is a pending owner decision, not this script's call.
budget PO.md       481 "the product-owner charter — ratchet, see above"

exit $status
