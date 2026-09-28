#!/usr/bin/env bash
# A suite that loses tests does not go red (CHARTER.md §4, "Tests").
#
# On 2026-08-16 an accidental deletion was caught only because the count fell
# from 13 to 11. Both suites were green with the tests missing. This makes the
# count a signal instead of an observation somebody has to remember to make.
#
# Until 2026-09-28 the count was compared with a committed baseline file that
# every test-adding PR had to edit. Parallel PRs collided on it: #110 merged its
# own branch's number over the 12 tests #106/#108/#109 had added, and `main`
# went red with nothing wrong (ADR 2026-09-28). So the reference is now git
# itself — the count at the merge base with main — and nothing has to be edited
# to ADD a test.
#
# REMOVING one is still deliberate: each removed test needs a commit in the
# branch carrying a trailer
#
#     Test-Removed: <testName> — <the proof it cannot fail>
#
# and the count may fall by at most the number of such trailers.
#
# The reference is origin/main (override with KAMOME_BASE_REF). On main itself,
# where HEAD is the reference, it is the first parent — the main this merge
# landed on. A reference that cannot be resolved is a FAILURE, never a skip: a
# shallow clone must fetch history (CI uses fetch-depth: 0).
set -uo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

pattern='^[[:space:]]*(@MainActor[[:space:]]+)?func[[:space:]]+test[A-Za-z0-9_]*\('

base_ref="${KAMOME_BASE_REF:-origin/main}"
if ! git rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
  kamome_fail "test count has no reference: $base_ref does not resolve"
  kamome_info "Run 'git fetch origin main' (or set KAMOME_BASE_REF). A shallow clone needs fetch-depth: 0."
  exit 1
fi

head=$(git rev-parse HEAD)
base=$(git merge-base HEAD "$base_ref" 2>/dev/null || true)
if [ -z "$base" ]; then
  kamome_fail "test count has no reference: HEAD shares no history with $base_ref (shallow clone?)"
  exit 1
fi
if [ "$base" = "$head" ]; then
  # On the reference itself: compare with the main this commit landed on.
  if ! base=$(git rev-parse --verify --quiet "HEAD^1"); then
    kamome_ok "test count is $(grep -rhoE "$pattern" Tests | wc -l | tr -d '[:space:]') (root commit, nothing to compare)"
    exit 0
  fi
fi

# The working tree, not HEAD, so an uncommitted deletion is caught before commit.
actual=$(grep -rhoE "$pattern" Tests | wc -l | tr -d '[:space:]')
reference=$(git grep -hoE "$pattern" "$base" -- Tests | wc -l | tr -d '[:space:]')
removals=$(git log --format=%B "$base..HEAD" | grep -cE '^Test-Removed: ' || true)

short=$(git rev-parse --short "$base")
if [ "$actual" -ge "$reference" ]; then
  kamome_ok "test count is $actual ($reference at $short, the merge base)"
  exit 0
fi

lost=$((reference - actual))
if [ "$lost" -le "$removals" ]; then
  kamome_ok "test count is $actual, $lost fewer than $short — covered by $removals Test-Removed trailer(s)"
  exit 0
fi

kamome_fail "test count FELL from $reference (at $short) to $actual — $lost test(s) disappeared, $removals declared"
kamome_info "CLAUDE.md rule 3: a test is removed only with proof it cannot fail."
kamome_info "If the removal is deliberate and proven, commit it with a trailer per test:"
kamome_info "    Test-Removed: <testName> — <proof>"
exit 1
