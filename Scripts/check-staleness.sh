#!/usr/bin/env bash
# Docs/current-state.md's "Last synced" line, checked instead of remembered.
#
# The protocol was strengthened twice (2026-08-28, 2026-08-30) and failed again
# on 2026-09-01, when the line read "PR #26" while `main` carried #28. Adding a
# third clause to a rule a human has to remember would have been the same move a
# third time, so it is a check now.
#
# ⚠️ **READ THIS BEFORE "FIXING" A FAILURE BY BUMPING THE NUMBER.**
#
# The line can never name the PR that contains it — that PR is not merged when
# the line is written. So on `main` this line is ALWAYS exactly one PR behind,
# and that is correct, not stale. Every governance PR in the history shows it:
# #20 named #16, #27 named #26, #29 named #28.
#
# That is why this runs on the BRANCH, before the merge, where the rule is
# exactly satisfiable: `gh pr list --state merged` does not yet include the PR
# being checked, so the newest merged PR is precisely what the line should name.
# Evaluated retroactively on `main` it would be unsatisfiable, and a check that
# cannot pass gets disabled — which is how this rule would have failed a fourth
# time.
#
# Two behind is a real failure, and it is the one that actually happened: PR #28
# changed the ledger without re-syncing the line.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

state="Docs/current-state.md"
failures=0

# The claim, parsed out of a line that wraps.
claim=$(tr '\n' ' ' < "$state" | grep -oE 'Last synced: [0-9]{4}-[0-9]{2}-[0-9]{2} against decisions\.md \*\*[^*]+\*\* and `main` at +\*\*PR #[0-9]+\*\*' | head -1)
if [ -z "$claim" ]; then
  kamome_fail "$state has no parsable \"Last synced\" line"
  kamome_info 'Expected: Last synced: <date> against decisions.md **<date>** and `main` at **PR #<n>**'
  exit 1
fi
claimed_adr=$(printf '%s' "$claim" | grep -oE 'decisions\.md \*\*[^*]+\*\*' | sed 's/decisions.md \*\*//; s/\*\*//')
claimed_pr=$(printf '%s' "$claim"  | grep -oE 'PR #[0-9]+' | tr -d 'PR #')

# Half 1 — the ledger. Offline, deterministic, always enforced.
newest_adr=$(grep -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2}( \([a-z]\))?' Docs/decisions.md | tail -1 | sed 's/^## //')
if [ "$claimed_adr" = "$newest_adr" ]; then
  kamome_ok "current-state is synced to the newest ADR ($newest_adr)"
else
  kamome_fail "current-state names ADR \"$claimed_adr\"; the newest is \"$newest_adr\""
  kamome_info "Docs/decisions.md wins on decisions. Re-read it, then update the line."
  failures=$((failures + 1))
fi

# Half 2 — the merge history. Needs the network and an authenticated gh.
if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  kamome_info "PR HALF DID NOT RUN — gh is missing or unauthenticated."
  kamome_info "This is a gap, not a pass: run ./check.sh where gh works before merging."
  exit $((failures > 0 ? 1 : 0))
fi

newest_pr=$(gh pr list --state merged --limit 1 --json number --jq '.[0].number' 2>/dev/null)
if [ -z "$newest_pr" ]; then
  kamome_info "PR HALF DID NOT RUN — gh could not list merged pull requests."
  exit $((failures > 0 ? 1 : 0))
fi

if [ "$claimed_pr" -eq "$newest_pr" ]; then
  kamome_ok "current-state is synced to the newest merged PR (#$newest_pr)"
elif [ "$claimed_pr" -gt "$newest_pr" ]; then
  # Naming an unmerged PR is a different mistake, and a worse one: it reads as
  # synced while pointing at something that may never land.
  kamome_fail "current-state names PR #$claimed_pr, which is not merged (newest is #$newest_pr)"
  failures=$((failures + 1))
else
  kamome_fail "current-state names PR #$claimed_pr; #$newest_pr has merged since"
  kamome_info "Re-read HANDOFF.md and Docs/decisions.md, update Active work and"
  kamome_info "Blockers to match, THEN set the line to #$newest_pr. Bumping only the"
  kamome_info "number is the failure this check exists to catch."
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] && exit 0
exit 1
