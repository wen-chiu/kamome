#!/usr/bin/env bash
# Build one .pmtiles map region per entry in Deploy/regions.json.
#
#   ./Deploy/bin/build-tiles.sh
#   KAMOME_REGIONS="iceland" ./Deploy/bin/build-tiles.sh
#
# Unlike routing — one merged dataset, because the app has one base_url — tiles
# stay one file per region: a .pmtiles covers a bounded area, and the app picks
# the region covering each trip by reading its own header (RecapMapTiles).
#
# Output goes to $KAMOME_DATA_DIR/tiles/. Side-load onto the device over Finder
# (Docs/dogfood-infrastructure.md §2); these files never belong in git.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

PLANETILER_IMAGE="ghcr.io/onthegomap/planetiler:latest"
STAMP="${EXTRACT_DATE:-$(date +%Y-%m-%d)}"

mkdir -p "$TILE_DIR" "$KAMOME_DATA_DIR/planetiler-data/sources"
require_disk 10

for name in $(region_names); do
  extract="$EXTRACT_DIR/${name}.osm.pbf"
  [ -f "$extract" ] || { echo "missing $extract — run Deploy/bin/fetch-extracts.sh first" >&2; exit 1; }

  out="${name}-${STAMP}.pmtiles"
  bbox="$(region_field "$name" bbox)"

  echo "▦ $name${bbox:+ (bbox $bbox)}"
  # Planetiler takes --bounds in the same W,S,E,N order as the manifest, so the
  # tile file and the routing clip describe the same area by construction.
  docker run --rm -v "$KAMOME_DATA_DIR:/data" "$PLANETILER_IMAGE" \
    --osm-path="/data/extracts/${name}.osm.pbf" \
    --output="/data/tiles/${out}" \
    --download --download-dir=/data/planetiler-data/sources --download-threads=4 \
    ${bbox:+--bounds="$bbox"} \
    --force

  echo "✓ $name — $(du -h "$TILE_DIR/$out" | cut -f1)"
  "$REPO_DIR/Tools/pmtiles-bounds.sh" "$TILE_DIR/$out"
  echo
done

echo "Regions in $TILE_DIR:"
du -h "$TILE_DIR"/*.pmtiles 2>/dev/null || true
echo
echo "Side-load: Finder → iPhone → Files → Kamome → drag these in."
echo "Simulator/demo renders: point KAMOME_TILES_PATH at $TILE_DIR (a directory"
echo "is scanned and matched per trip)."
