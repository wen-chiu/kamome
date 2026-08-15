#!/usr/bin/env bash
# Does this region leave the opening anything to zoom out to?
#
# Covering the trip is not enough. `CameraPath.cappedToRegion` refuses to frame
# ground the tiles cannot draw, so a region cut close to the trip caps the
# establishing beat down to the body's own width and the film opens on a flat
# picture with a "zoom" that does not zoom. Iceland shipped that way until
# 2026-08-08.
#
# The region has to be able to hold the establishing beat at full width:
#
#     containedSpan(region) > fittingSpan(trip) x export.wide_span_padding
#
# containedSpan is the widest portrait frame that fits inside the region, which
# for a wide region is bounded by latitude. Full derivation of the 2.67 factor:
# Deploy/regions.json `_establishing_headroom`.
#
#   ./Tools/tile-headroom.sh region.pmtiles [wide_span_padding]
set -euo pipefail

FILE="${1:?usage: tile-headroom.sh <file.pmtiles> [wide_span_padding]}"
# `wide_span_padding` is what the body span asks for over the trip's own
# framing, so it is what converts a region's contained span into "the widest
# trip this region can still open on". Read from the shipped config so this
# cannot drift from what the camera actually does.
PADDING="${2:-$(python3 -c "import json;print(json.load(open('$(dirname "$0")/../Config/TrackingConfig.json'))['export']['wide_span_padding'])")}"

python3 - "$FILE" "$PADDING" <<'PY'
import math, struct, sys

path, padding = sys.argv[1], float(sys.argv[2])
with open(path, 'rb') as handle:
    header = handle.read(127)
if len(header) < 127 or header[:7] != b'PMTiles':
    sys.exit(f"{path}: not a PMTiles file")
if header[7] != 3:
    sys.exit(f"{path}: PMTiles v{header[7]}, the app reads v3 only")

# Same four fields, in the same order, as Tools/pmtiles-bounds.sh.
west, south, east, north = (v / 1e7 for v in struct.unpack('<iiii', header[102:118]))
mid = math.radians((south + north) / 2)
lat_km = (north - south) * 111.32
lon_km = (east - west) * 111.32 * math.cos(mid)

# The widest portrait frame (1080x1920) that fits entirely inside the region —
# the same min() CameraPath.containedSpanM computes.
contained = min(lon_km, lat_km * 1080 / 1920)
# The body span asks for fittingSpan(trip) x wide_span_padding, and the cap must
# not bind on it — so invert that to get the widest trip this region can hold.
supports = contained / padding

print(f"  region      {lon_km:>6.0f} km wide x {lat_km:>6.0f} km tall")
print(f"  contained   {contained:>6.0f} km  (the cap the camera sees)")
print(f"  headroom    supports trips up to {supports:>6.0f} km across "
      f"(wide_span_padding {padding})")
PY
