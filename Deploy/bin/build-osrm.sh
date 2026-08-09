#!/usr/bin/env bash
# Clip, merge and preprocess every region in Deploy/regions.json into ONE OSRM
# routing dataset.
#
#   ./Deploy/bin/build-osrm.sh
#
# **Why one merged dataset.** OSRM serves exactly one dataset per process, and
# `matching.base_url` in Config/TrackingConfig.json is a single value — the app
# cannot pick a server per trip, and teaching it to would be building the
# region-routing infrastructure this whole arrangement exists to avoid. Merge
# first, serve once.
#
# The car profile is what both drive and scooter legs route against; walk legs
# stay raw by design (PD-8), so no foot profile is built.
#
# Steps, all in Docker so no local osmium/OSRM install is needed:
#   1. clip each extract to its bbox (skipped where bbox is null)
#   2. merge the results
#   3. osrm-extract → osrm-partition → osrm-customize (MLD)
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

OSM_IMAGE="osrm/osrm-backend"
OSMIUM_IMAGE="stefda/osmium-tool"

mkdir -p "$EXTRACT_DIR"
require_disk 25

names=$(region_names)
[ -n "$names" ] || { echo "no regions selected" >&2; exit 1; }

merge_inputs=()
for name in $names; do
  extract="$EXTRACT_DIR/${name}.osm.pbf"
  [ -f "$extract" ] || { echo "missing $extract — run Deploy/bin/fetch-extracts.sh first" >&2; exit 1; }

  bbox="$(region_field "$name" bbox)"
  if [ -z "$bbox" ]; then
    merge_inputs+=("extracts/${name}.osm.pbf")
    echo "· $name — whole extract ($(du -h "$extract" | cut -f1))"
    continue
  fi

  clipped="$EXTRACT_DIR/${name}.clipped.osm.pbf"
  if [ ! -f "$clipped" ] || [ "$extract" -nt "$clipped" ]; then
    echo "✂ $name — clipping to $bbox"
    docker_osm "$OSMIUM_IMAGE" osmium extract \
      --bbox "$bbox" --set-bounds --overwrite \
      -o "/data/extracts/${name}.clipped.osm.pbf" "/data/extracts/${name}.osm.pbf"
  fi
  merge_inputs+=("extracts/${name}.clipped.osm.pbf")
  echo "· $name — clipped ($(du -h "$clipped" | cut -f1))"
done

merged="$KAMOME_DATA_DIR/${MERGED_NAME}.osm.pbf"
echo
if [ "${#merge_inputs[@]}" -eq 1 ]; then
  # osmium merge refuses a single input; a copy keeps the rest of the pipeline
  # identical whether you build one region or four.
  cp "$KAMOME_DATA_DIR/${merge_inputs[0]}" "$merged"
else
  echo "⊕ merging ${#merge_inputs[@]} regions"
  docker_osm "$OSMIUM_IMAGE" osmium merge --overwrite \
    "${merge_inputs[@]/#//data/}" -o "/data/${MERGED_NAME}.osm.pbf"
fi
echo "✓ merged — $(du -h "$merged" | cut -f1)"

echo
echo "⚙ osrm-extract (car profile) — the memory-hungry step"
docker_osm "$OSM_IMAGE" osrm-extract -p /opt/car.lua "/data/${MERGED_NAME}.osm.pbf"
echo "⚙ osrm-partition"
docker_osm "$OSM_IMAGE" osrm-partition "/data/${MERGED_NAME}.osrm"
echo "⚙ osrm-customize"
docker_osm "$OSM_IMAGE" osrm-customize "/data/${MERGED_NAME}.osrm"

echo
echo "✓ routing dataset ready: $KAMOME_DATA_DIR/${MERGED_NAME}.osrm"
echo "  Serve it:  cd Deploy && docker compose up -d"
echo "  Then set matching.base_url in Config/TrackingConfig.json."
echo
echo "If osrm-extract was killed (exit 137 = out of memory), add or tighten a"
echo "bbox in Deploy/regions.json and re-run — that is the intended lever."
