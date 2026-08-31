#!/usr/bin/env bash
# §0 — location data never leaves the device by default.
#
# Two halves of §0 are mechanically checkable, and this checks those two. It
# does NOT decide whether a coordinate is real or synthetic: DemoSeeder ships
# invented Western Australia coordinates and committed fixtures ship invented
# trips, so a coordinate-shaped literal is not by itself a violation. What is
# checkable is where real data is allowed to live, and what the log may say.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

status=0

# 1. The two gitignored locations for real data must hold nothing tracked.
#    Tests/Fixtures/trips/local/ takes real trip dumps; Docs/tests/ takes raw
#    device-test artifacts. A file tracked under either is real location data
#    committed to the repository.
tracked=$(git ls-files -- 'Tests/Fixtures/trips/local/' 'Docs/tests/' || true)
if [ -n "$tracked" ]; then
  kamome_fail "real-data locations must stay untracked, but these are committed:"
  echo "$tracked" >&2
  status=1
else
  kamome_ok "Tests/Fixtures/trips/local/ and Docs/tests/ hold nothing tracked"
fi

# 2. KamomeLog may name which stop failed, never where it is. Checked over a
#    three-line window so a call broken across lines is still seen. Comment
#    lines are stripped first — the boundary is discussed in comments on
#    purpose, and discussing it is not logging it.
leaks=$(grep -rn --include='*.swift' -A2 'KamomeLog\.' App Core UI 2>/dev/null \
  | grep -vE '^[^:]+[-:][0-9]+[-:][[:space:]]*//' \
  | grep -iE '\.(latitude|longitude)\b|\bcoordinate[s]?\b' || true)
if [ -n "$leaks" ]; then
  kamome_fail "a KamomeLog call appears to carry coordinates:"
  echo "$leaks" >&2
  status=1
else
  kamome_ok "no KamomeLog call carries coordinates"
fi

exit $status
