#!/usr/bin/env bash
# Each platform SDK stays in exactly one file.
#
# RecapSnapshotProviding is the renderer boundary (ADR 2026-07-19): MapLibre
# types must never leak past the provider. The same discipline keeps MapKit and
# Photos each behind one file, so a substrate swap stays a one-file change.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

status=0

confine() {
  local sdk="$1" owner="$2"
  local offenders
  offenders=$(grep -rl --include='*.swift' "import ${sdk}\$" App Core UI 2>/dev/null \
    | grep -v "^${owner}\$" || true)
  if [ -n "$offenders" ]; then
    kamome_fail "import ${sdk} outside ${owner}:"
    echo "$offenders" >&2
    status=1
  else
    kamome_ok "import ${sdk} confined to ${owner}"
  fi
}

confine MapLibre App/Services/MapLibreSnapshotProvider.swift

exit $status
