#!/usr/bin/env bash
# Build one dogfood map region (.pmtiles) for the Replay MVP §6 gate.
#
# Same posture as the CI fixture (Tests/Fixtures/tiles/generate_tiles.sh) and the
# OSRM setup (Docs/osrm-setup.md): a Geofabrik extract → Planetiler → one file.
# The difference is scope — this builds a region sized around a *real* trip, so
# it is far too large for git and is side-loaded onto the device over Finder
# instead (PD-7, Docs/dogfood-infrastructure.md).
#
# The app picks a region by reading its PMTiles header, so the only thing that
# has to be right is $BOUNDS. Pad it: `RecapMapTiles` requires a region to cover
# the whole trip, and falls back to Apple's map if it does not.
#
#   ./Tools/build-dogfood-region.sh <name> <W,S,E,N> [extract.osm.pbf]
#
# e.g. ./Tools/build-dogfood-region.sh margaret-river 114.8,-34.3,115.4,-33.5
set -euo pipefail

NAME="${1:?usage: build-dogfood-region.sh <name> <W,S,E,N> [extract.osm.pbf]}"
BOUNDS="${2:?missing bounds W,S,E,N}"
DATA="${KAMOME_OSRM_DIR:-$HOME/kamome-osrm}"
EXTRACT="${3:-$DATA/western-australia-latest.osm.pbf}"
OUT_DIR="$DATA/planetiler-out"
STAMP="${EXTRACT_DATE:-$(date +%Y-%m-%d)}"
OUT="${NAME}-${STAMP}.pmtiles"

[ -f "$EXTRACT" ] || { echo "Missing extract $EXTRACT — see Docs/osrm-setup.md §1" >&2; exit 1; }
mkdir -p "$OUT_DIR" "$DATA/planetiler-data/sources"

docker run --rm -v "$DATA:/data" ghcr.io/onthegomap/planetiler:latest \
  --osm-path="/data/$(basename "$EXTRACT")" \
  --output="/data/planetiler-out/${OUT}" \
  --download --download-dir=/data/planetiler-data/sources --download-threads=4 \
  --bounds="$BOUNDS" \
  --force

SIZE=$(du -h "$OUT_DIR/$OUT" | cut -f1)
echo
echo "Wrote $OUT_DIR/$OUT ($SIZE)"
echo "Side-load: Finder → iPhone → Files → Kamome → drag this file in."
echo "Verify the header bounds the app will read:"
echo "  ./Tools/pmtiles-bounds.sh \"$OUT_DIR/$OUT\""
