#!/usr/bin/env bash
# A suite that loses tests does not go red (Arch.md, "Tests").
#
# On 2026-08-16 an accidental deletion was caught only because the count fell
# from 13 to 11. Both suites were green with the tests missing and every other
# signal said the change was fine. This makes the count a signal instead of an
# observation somebody has to remember to make.
#
# Counted statically from the source, so it runs without a simulator and gives
# the same answer everywhere. Adding tests is a deliberate two-line change:
# write the test, then raise the baseline in the same commit.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

baseline_file="Scripts/test-count.baseline"
baseline=$(grep -vE '^\s*(#|$)' "$baseline_file" | head -1 | tr -d '[:space:]')

actual=$(grep -rhoE '^[[:space:]]*(@MainActor[[:space:]]+)?func[[:space:]]+test[A-Za-z0-9_]*\(' Tests \
  | wc -l | tr -d '[:space:]')

if [ "$actual" -eq "$baseline" ]; then
  kamome_ok "test count is $actual, matching the baseline"
  exit 0
fi

if [ "$actual" -lt "$baseline" ]; then
  kamome_fail "test count FELL from $baseline to $actual — $((baseline - actual)) test(s) disappeared"
  kamome_info "CLAUDE.md rule 3: a test is removed only with proof it cannot fail."
  kamome_info "If the removal is deliberate and proven, lower $baseline_file in the same commit."
else
  kamome_fail "test count rose from $baseline to $actual — the baseline was not updated"
  kamome_info "Raise $baseline_file to $actual in the same commit that adds the test(s)."
fi
exit 1
