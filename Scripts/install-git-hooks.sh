#!/usr/bin/env bash
# One-time, per clone: point git at the tracked hooks in Scripts/git-hooks/.
# The setting lives in the shared .git/config, so it covers every worktree.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."
existing=$(git config --get core.hooksPath || true)
if [ -n "$existing" ] && [ "$existing" != "Scripts/git-hooks" ]; then
  kamome_fail "core.hooksPath is already '$existing' — not overwriting it"
  exit 1
fi
git config core.hooksPath Scripts/git-hooks
kamome_ok "git hooks installed: Kamome.xcodeproj regenerates after checkout, merge, pull and rebase"
