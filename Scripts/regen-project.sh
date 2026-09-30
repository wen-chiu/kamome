#!/usr/bin/env bash
# Regenerates Kamome.xcodeproj from project.yml. Run by the git hooks in
# Scripts/git-hooks/ after every checkout, merge, pull and rebase, so the project
# Xcode opens always matches the branch — no more remembering `xcodegen generate`
# after `main` moves. Takes ~0.2 s. Never fails the git operation that ran it.
cd "$(dirname "$0")/.." || exit 0
if ! command -v xcodegen >/dev/null 2>&1; then
  printf 'kamome: xcodegen not installed (brew install xcodegen) — Kamome.xcodeproj NOT regenerated\n' >&2
  exit 0
fi
if xcodegen generate --quiet; then
  printf 'kamome: Kamome.xcodeproj regenerated from project.yml\n'
else
  printf 'kamome: xcodegen generate FAILED — Kamome.xcodeproj is stale\n' >&2
fi
exit 0
