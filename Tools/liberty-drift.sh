#!/usr/bin/env bash
# Re-fetches upstream Liberty, re-runs the transform and diffs against the
# committed frozen styles. Exits 0 if identical, 1 if they differ.
#
# ENV-GATED — this fetches from tiles.openfreemap.org and must NOT run in
# ./check.sh or CI (the transform depends on someone else's CDN, and CI has
# no business depending on it). Run it on demand to detect upstream drift:
#
#   KAMOME_CHECK_LIBERTY_DRIFT=1 ./Tools/liberty-drift.sh
#
set -euo pipefail

if [ "${KAMOME_CHECK_LIBERTY_DRIFT:-}" != "1" ]; then
  echo "skipped — set KAMOME_CHECK_LIBERTY_DRIFT=1 to run"
  exit 0
fi

cd "$(dirname "$0")/.."
python3 Scripts/freeze-liberty-styles.py --check
