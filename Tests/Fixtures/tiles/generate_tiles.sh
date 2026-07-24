#!/usr/bin/env bash
# Regenerate the Perth-corridor fixture PMTiles (Replay MVP §2 substrate).
#
# Offline developer step, same posture as OSRM (Docs/osrm-setup.md): a regional
# Geofabrik extract → Planetiler → a single .pmtiles file. Only the SMALL
# fixture crop is checked into git (Tests/Fixtures/tiles/); full-region tiles
# stay out (Docs/vector-tile-pipeline.md §4).
#
# Requires Docker (the Planetiler image bundles Java 21; local Java is 11).
# The western-australia extract is the same one the OSRM setup uses; see
# Docs/osrm-setup.md §1. Auxiliary sources (water polygons, natural earth) are
# downloaded once and cached under $DATA/planetiler-data/sources.
set -euo pipefail

DATA="${KAMOME_OSRM_DIR:-$HOME/kamome-osrm}"
EXTRACT="$DATA/western-australia-latest.osm.pbf"
OUT_DIR="$DATA/planetiler-out"
# Pin the extract vintage in the artifact name — never "latest" in a fixture.
STAMP="${EXTRACT_DATE:-2026-07-19}"
OUT="perth-${STAMP}.pmtiles"

# A tight Margaret River coastal crop of the day-1 corridor (W,S,E,N) — kept
# small on purpose (the full 0.9°×2.1° corridor is ~20 MB; this is a few MB).
# Includes the Indian Ocean coast so the souvenir-map water fill is exercised,
# plus Caves Rd / Bussell Hwy and a slice of Tests/Fixtures/perth_margaret_river_day1.gpx.
# Widen/remove for a full-region build (that file stays out of git).
BOUNDS="114.96,-34.00,115.16,-33.78"

[ -f "$EXTRACT" ] || { echo "Missing $EXTRACT — see Docs/osrm-setup.md §1" >&2; exit 1; }
mkdir -p "$OUT_DIR" "$DATA/planetiler-data/sources"

docker run --rm -v "$DATA:/data" ghcr.io/onthegomap/planetiler:latest \
  --osm-path="/data/$(basename "$EXTRACT")" \
  --output="/data/planetiler-out/${OUT}" \
  --download --download-dir=/data/planetiler-data/sources --download-threads=4 \
  --bounds="$BOUNDS" \
  --force

cp "$OUT_DIR/$OUT" "$(dirname "$0")/$OUT"
echo "Wrote $(dirname "$0")/$OUT ($(du -h "$OUT_DIR/$OUT" | cut -f1))"
echo "If this exceeds a few MB, tighten \$BOUNDS before committing."
