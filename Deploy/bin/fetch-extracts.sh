#!/usr/bin/env bash
# Download the Geofabrik extract for every region in Deploy/regions.json.
#
#   ./Deploy/bin/fetch-extracts.sh
#   KAMOME_REGIONS="iceland miyakojima" ./Deploy/bin/fetch-extracts.sh
#
# Re-runnable: an extract already on disk is left alone unless KAMOME_REFRESH=1.
# Geofabrik regenerates "-latest" daily, so a refresh changes the road network
# under an already-built routing dataset — rebuild OSRM after refreshing.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

mkdir -p "$EXTRACT_DIR"
require_disk 5

for name in $(region_names); do
  source_path="$(region_field "$name" geofabrik)"
  target="$EXTRACT_DIR/${name}.osm.pbf"

  if [ -f "$target" ] && [ "${KAMOME_REFRESH:-0}" != "1" ]; then
    echo "✓ $name — already have $(du -h "$target" | cut -f1)"
    continue
  fi

  url="https://download.geofabrik.de/${source_path}-latest.osm.pbf"
  echo "↓ $name ← $url"
  # Resume a part-file rather than starting over: these are hundreds of
  # megabytes, and an interrupted download otherwise costs the whole thing.
  # --retry rides out the transient 5xx Geofabrik serves under load.
  curl -fL --progress-bar --continue-at - --retry 5 --retry-delay 5 \
    -o "$target.part" "$url"
  mv "$target.part" "$target"
  echo "✓ $name — $(du -h "$target" | cut -f1)"
done

echo
echo "Extracts in $EXTRACT_DIR:"
du -h "$EXTRACT_DIR"/*.osm.pbf 2>/dev/null || true
