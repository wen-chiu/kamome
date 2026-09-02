#!/usr/bin/env bash
# A config key that looks live and controls nothing (CLAUDE.md rule 7).
#
# "No magic numbers — every tunable lives in Config/TrackingConfig.json" makes
# that file the place people go to change behaviour. A key whose last consumer
# was deleted keeps decoding, keeps being passed through the copy-constructors,
# keeps being asserted by a decode test, and does nothing. Somebody then tunes
# it and reasons about the result.
#
# This has happened three times, and the third was found by accident:
# route_waypoint_radius_m (2026-08-20), keyframe_interval_frames (2026-09-01),
# and total_duration_max_s — which nothing had named until 2026-09-02, while
# film duration was an open design question and that key is the first thing
# anyone would have reached for.
#
# Two things must NOT count as a consumer, because both fooled the first attempt
# at this query on 2026-09-02:
#   - a comment. keyframe_interval_frames' only mention in the render path is a
#     past-tense comment in RecapRenderLoop.
#   - decode plumbing. Core/ConfigLoader/ holds the CodingKey, the stored
#     property, the initializer parameter and six copy-constructor pass-throughs.
#     All eleven mentions of keyframeIntervalFrames are of that kind.
# So: a consumer is a non-comment mention outside Core/ConfigLoader/.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(dirname "$0")/.."

baseline_file="Scripts/dead-config.baseline"

actual=$(/usr/bin/env python3 - <<'PY'
import json, os, re

cfg = json.load(open("Config/TrackingConfig.json"))

def leaves(node, prefix=""):
    for key, value in node.items():
        if isinstance(value, dict):
            yield from leaves(value, prefix + key + ".")
        else:
            yield prefix + key

code = []
for root, _, files in os.walk("."):
    if root.startswith("./.git") or "/ConfigLoader" in root:
        continue
    if not re.match(r"^\./(App|UI|Core)(/|$)", root):
        continue
    for name in files:
        if not name.endswith(".swift"):
            continue
        text = open(os.path.join(root, name), encoding="utf-8", errors="ignore").read()
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)          # block comments
        for line in text.split("\n"):
            line = re.sub(r"(?<!:)//.*$", "", line)                # line comments, sparing https://
            if line.strip():
                code.append(line)
blob = "\n".join(code)

for key in leaves(cfg):
    leaf = key.split(".")[-1]
    camel = re.sub(r"_(.)", lambda m: m.group(1).upper(), leaf)
    if camel not in blob and leaf not in blob:
        print(key)
PY
)

expected=$(grep -vE '^\s*(#|$)' "$baseline_file" | sed 's/[[:space:]]*$//' | sort)
actual=$(printf '%s' "$actual" | grep -v '^$' | sort || true)

if [ "$actual" = "$expected" ]; then
  count=$(printf '%s' "$expected" | grep -c '' || true)
  kamome_ok "no config key lost its last consumer ($count known-dead, baselined)"
  exit 0
fi

new=$(comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") | grep -v '^$' || true)
gone=$(comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected") | grep -v '^$' || true)

if [ -n "$new" ]; then
  kamome_fail "config key(s) now have no consumer outside Core/ConfigLoader/:"
  printf '%s\n' "$new" | while read -r k; do kamome_info "  $k"; done
  kamome_info "Either the key is dead — delete it, and say so in the commit — or its"
  kamome_info "consumer was removed by accident. Do not baseline it to get green."
fi
if [ -n "$gone" ]; then
  kamome_fail "baselined key(s) have a consumer again — the baseline is now wrong:"
  printf '%s\n' "$gone" | while read -r k; do kamome_info "  $k"; done
  kamome_info "Remove them from $baseline_file in the same commit."
fi
exit 1
