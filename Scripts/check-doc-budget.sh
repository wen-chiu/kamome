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
# Raised 14,000 → 16,000 once, on 2026-08-31, and cut to 11,000 on 2026-09-03
# when the closed sections were archived (ADR 2026-09-03). The 2026-08-31 note
# said the next time it binds the answer is to archive a closed item, not to
# raise it again. That is what happened, so the ceiling comes down with it.
# **A budget that only ever goes up is not a budget.**
budget HANDOFF.md  11000 "read at the start of every session"
# Added 2026-09-03. CLAUDE.md rule 1 makes this the first file of every session
# and it was the ONLY unbudgeted one — it had reached 17,531 bytes, larger than
# HANDOFF.md's cap, while claiming to be "an index, not a source of truth".
budget Docs/current-state.md 10000 "read at the start of every session"
budget Arch.md     10000 "the engineering charter"
budget PO.md       12000 "the product-owner charter"
budget DESIGNER.md  9000 "the visual charter"

# The live Docs/ corpus, as one number.
#
# Every per-file budget so far has DISPLACED text rather than retired it: the
# 2026-08-31 HANDOFF trim spilled 12 new Docs/handoff-*.md files in a day, and
# between 2026-07-19 and 2026-09-03 the corpus went 13 → 53 documents with
# nothing ever deleted. A cap on one file cannot see that. This one can.
#
# Docs/decisions.md is excluded on purpose — it is append-only BY DESIGN, it is
# never read whole, and Scripts/check-decisions-index.sh already keeps it usable.
# Docs/_archive/ is excluded because that is where things go to stop being read.
#
# Over budget means ARCHIVE ONE, not raise this number. A new topic document is
# affordable; a new topic document plus every old one is what got us here.
corpus_limit=355000
corpus=$(cat $(ls Docs/*.md | grep -v '^Docs/decisions.md$') | wc -c | tr -d '[:space:]')
if [ "$corpus" -gt "$corpus_limit" ]; then
  kamome_fail "live Docs/ corpus is $corpus bytes, over its $corpus_limit-byte ceiling"
  printf '        Archive a document whose work has closed (Docs/_archive/), do\n' >&2
  printf '        not raise the ceiling. See ADR 2026-09-03.\n' >&2
  status=1
else
  kamome_ok "$(printf '%-12s %6d / %6d bytes' 'live Docs/' "$corpus" "$corpus_limit")"
fi

exit $status
