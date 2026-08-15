#!/usr/bin/env bash
# Print the bounds a .pmtiles file declares in its own v3 header — the exact
# bytes `PMTilesHeader.swift` reads to decide whether a region covers a trip.
#
# Use it to check a region *before* side-loading it: if these bounds do not
# enclose the whole trip, the app falls back to Apple's map rather than render
# blank ocean, and the fix is to rebuild with wider --bounds.
#
#   ./Tools/pmtiles-bounds.sh region.pmtiles [trip W,S,E,N]
set -euo pipefail

FILE="${1:?usage: pmtiles-bounds.sh <file.pmtiles> [W,S,E,N]}"
TRIP="${2:-}"

python3 - "$FILE" "$TRIP" <<'PY'
import struct, sys

path, trip = sys.argv[1], sys.argv[2]
with open(path, 'rb') as handle:
    header = handle.read(127)

if len(header) < 127 or header[:7] != b'PMTiles':
    sys.exit(f"{path}: not a PMTiles file")
if header[7] != 3:
    sys.exit(f"{path}: PMTiles v{header[7]}, the app reads v3 only")

min_lon, min_lat, max_lon, max_lat = (v / 1e7 for v in struct.unpack('<iiii', header[102:118]))
print(f"{path}")
print(f"  zoom   {header[100]}–{header[101]}")
print(f"  bounds {min_lon:.5f},{min_lat:.5f},{max_lon:.5f},{max_lat:.5f}  (W,S,E,N)")

if trip:
    t_w, t_s, t_e, t_n = (float(v) for v in trip.split(','))
    covers = min_lon <= t_w and min_lat <= t_s and max_lon >= t_e and max_lat >= t_n
    print(f"  trip   {t_w},{t_s},{t_e},{t_n}")
    print("  COVERS the trip — the app will render this region."
          if covers else
          "  DOES NOT cover the trip — the app will fall back to Apple's map. Rebuild wider.")
    sys.exit(0 if covers else 1)
PY
