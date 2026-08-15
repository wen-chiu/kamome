#!/usr/bin/env bash
# Shared plumbing for the Deploy/bin scripts: where data lives, and reading
# Deploy/regions.json. Sourced, never run directly.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$DEPLOY_DIR/.." && pwd)"

# Everything built lives outside the repo — these artifacts are gigabytes and
# must never end up in git. Override to build somewhere with more disk.
KAMOME_DATA_DIR="${KAMOME_DATA_DIR:-$HOME/kamome-osrm}"
EXTRACT_DIR="$KAMOME_DATA_DIR/extracts"
TILE_DIR="$KAMOME_DATA_DIR/tiles"
MERGED_NAME="kamome-merged"

REGIONS_JSON="${KAMOME_REGIONS_JSON:-$DEPLOY_DIR/regions.json}"

# Build a subset: KAMOME_REGIONS="iceland miyakojima" ./bin/whatever.sh
region_names() {
  local wanted="${KAMOME_REGIONS:-}"
  python3 - "$REGIONS_JSON" "$wanted" <<'PY'
import json, sys
manifest, wanted = sys.argv[1], sys.argv[2].split()
names = [r["name"] for r in json.load(open(manifest))["regions"]]
if wanted:
    unknown = [w for w in wanted if w not in names]
    if unknown:
        sys.exit(f"unknown region(s): {', '.join(unknown)}; known: {', '.join(names)}")
    names = [n for n in names if n in wanted]
print("\n".join(names))
PY
}

region_field() {
  python3 - "$REGIONS_JSON" "$1" "$2" <<'PY'
import json, sys
manifest, name, field = sys.argv[1:4]
for region in json.load(open(manifest))["regions"]:
    if region["name"] == name:
        print(region.get(field) or "")
        break
PY
}

# A region must be big enough that the opening establishing shot can be WIDER
# than the body shot, or the film opens flat. Not a taste value: it is
# (frame_height / frame_width) x export.wide_span_padding. Derivation and the
# Iceland case that produced it: Deploy/regions.json _establishing_headroom.
KAMOME_ESTABLISHING_HEADROOM="${KAMOME_ESTABLISHING_HEADROOM:-2.67}"
export KAMOME_ESTABLISHING_HEADROOM

# Free space on the data volume, in GB.
free_gb() {
  df -g "$KAMOME_DATA_DIR" 2>/dev/null | tail -1 | awk '{print $4}'
}

require_disk() {
  local needed="$1" have
  have="$(free_gb)"
  if [ -n "$have" ] && [ "$have" -lt "$needed" ]; then
    echo "⚠️  ${have} GB free on $KAMOME_DATA_DIR; this step wants ~${needed} GB." >&2
    echo "    Clip regions in Deploy/regions.json, or set KAMOME_DATA_DIR to a bigger volume." >&2
    [ "${KAMOME_FORCE:-0}" = "1" ] || { echo "    Re-run with KAMOME_FORCE=1 to proceed anyway." >&2; exit 1; }
  fi
}

docker_osm() {
  docker run --rm -t -v "$KAMOME_DATA_DIR:/data" "$@"
}
