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

exit $status
