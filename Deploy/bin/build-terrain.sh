#!/usr/bin/env bash
# Build a terrain-RGB tile set for one region, so the souvenir map can carry
# hillshade — mountains and ridgelines (Chiu 2026-07-30).
#
#   ./Deploy/bin/build-terrain.sh new-zealand
#   TERRAIN_MAXZOOM=11 ./Deploy/bin/build-terrain.sh iceland
#
# **Why a separate file.** The vector tiles Planetiler builds carry no elevation
# at all — the OpenMapTiles schema has `landcover`, `mountain_peak` (a point with
# an `ele` field) and `waterway`, but no contours and no DEM. Hillshade therefore
# cannot come from them; it needs a raster-DEM source, which MapLibre shades at
# draw time from a `hillshade` layer. That is a style + data addition, not a
# change to the map stack.
#
# Source: AWS "elevation-tiles-prod" terrarium tiles (Mapzen's open DEM, ~30 m
# where SRTM covers, coarser at high latitude). Terrarium encodes height in RGB,
# which MapLibre reads natively with `"encoding": "terrarium"`.
#
# Zoom 10 by default: enough for relief at country and regional framing, and
# MapLibre overzooms it for closer shots — hillshade does not need per-metre
# detail to read as mountains. Each further zoom multiplies tile count by 4.
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

NAME="${1:?usage: build-terrain.sh <region-name>}"
MAXZOOM="${TERRAIN_MAXZOOM:-10}"
TERRAIN_DIR="$KAMOME_DATA_DIR/terrain"
TILE_CACHE="$TERRAIN_DIR/${NAME}-src"
MBTILES="$TERRAIN_DIR/${NAME}-terrain.mbtiles"
OUT="$TERRAIN_DIR/${NAME}-terrain.pmtiles"
mkdir -p "$TERRAIN_DIR" "$TILE_CACHE"
rm -f "$MBTILES"

# The area to cover: the region's manifest bbox, else the bounds its built vector
# tiles declare — the same extent the app frames the establishing shot to.
BBOX="$(region_field "$NAME" bbox)"
if [ -z "$BBOX" ]; then
  vector="$(ls "$TILE_DIR/${NAME}"-*.pmtiles 2>/dev/null | tail -1)"
  [ -n "$vector" ] || { echo "no bbox for $NAME and no built vector tiles to read one from" >&2; exit 1; }
  BBOX="$(python3 -c "
import struct, sys
h = open(sys.argv[1], 'rb').read(127)
w, s, e, n = (v / 1e7 for v in struct.unpack('<iiii', h[102:118]))
print(f'{w},{s},{e},{n}')
" "$vector")"
  echo "· bbox from built vector tiles: $BBOX"
fi

# Tile list → a curl config. curl rather than Python's urllib: the system Python
# on macOS ships without a CA bundle, so every HTTPS fetch fails certificate
# verification, while curl is configured to talk to the internet.
python3 -c "
import math, sys, os
bbox, maxzoom, cache = sys.argv[1], int(sys.argv[2]), sys.argv[3]
west, south, east, north = (float(v) for v in bbox.split(','))
BASE = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium'

def tile_x(lon, z):
    return int((lon + 180.0) / 360.0 * (1 << z))

def tile_y(lat, z):
    lat = max(min(lat, 85.05112878), -85.05112878)
    return int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * (1 << z))

for z in range(0, maxzoom + 1):
    for x in range(tile_x(west, z), tile_x(east, z) + 1):
        # y grows southward, so the north edge is the smaller index.
        for y in range(tile_y(north, z), tile_y(south, z) + 1):
            os.makedirs(f'{cache}/{z}/{x}', exist_ok=True)
            print(f'url = \"{BASE}/{z}/{x}/{y}.png\"')
            print(f'output = \"{cache}/{z}/{x}/{y}.png\"')
" "$BBOX" "$MAXZOOM" "$TILE_CACHE" > "$TERRAIN_DIR/curl.cfg"

TILE_COUNT=$(grep -c '^url' "$TERRAIN_DIR/curl.cfg")
echo "· $TILE_COUNT terrain tiles, z0-$MAXZOOM"
# --fail so a 404 leaves no file (genuinely absent ocean tiles) while any other
# failure surfaces, rather than being mistaken for absence.
curl --parallel --parallel-max 16 --retry 3 --retry-delay 2 -sS --fail \
  -K "$TERRAIN_DIR/curl.cfg" || true
rm -f "$TERRAIN_DIR/curl.cfg"

python3 -c "
import os, sqlite3, sys
bbox, maxzoom, out, name, cache, expected = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5], int(sys.argv[6])
west, south, east, north = (float(v) for v in bbox.split(','))

db = sqlite3.connect(out)
db.executescript('''
CREATE TABLE metadata (name TEXT, value TEXT);
CREATE TABLE tiles (zoom_level INTEGER, tile_column INTEGER, tile_row INTEGER, tile_data BLOB);
CREATE UNIQUE INDEX tile_index ON tiles (zoom_level, tile_column, tile_row);
''')
db.executemany('INSERT INTO metadata VALUES (?,?)', [
    ('name', name + ' terrain'), ('format', 'png'), ('type', 'baselayer'),
    ('minzoom', '0'), ('maxzoom', str(maxzoom)),
    ('bounds', f'{west},{south},{east},{north}'),
    # Read by MapLibre as the DEM encoding; terrarium is Mapzen's RGB scheme.
    ('encoding', 'terrarium'),
])

written = 0
for z_dir in sorted(os.listdir(cache)):
    if not z_dir.isdigit():
        continue
    z = int(z_dir)
    for x_dir in os.listdir(f'{cache}/{z_dir}'):
        for png in os.listdir(f'{cache}/{z_dir}/{x_dir}'):
            path = f'{cache}/{z_dir}/{x_dir}/{png}'
            if os.path.getsize(path) == 0:
                continue
            x, y = int(x_dir), int(png[:-4])
            # MBTiles rows count from the south (TMS), tile y from the north.
            db.execute('INSERT OR REPLACE INTO tiles VALUES (?,?,?,?)',
                       (z, x, (1 << z) - 1 - y, sqlite3.Binary(open(path, 'rb').read())))
            written += 1
            if written % 500 == 0:
                db.commit()
db.commit()
db.close()

print(f'· {written} of {expected} tiles written')
# A handful of absent tiles is ocean or beyond DEM coverage. Nearly all of them
# absent is a broken fetch, and shipping a near-empty DEM renders as a flat map
# rather than as an error — so fail loudly instead of quietly succeeding.
if written < expected * 0.25:
    sys.exit(f'only {written}/{expected} tiles fetched — a fetch failure, not sparse '
             'coverage. Check network access to elevation-tiles-prod.')
" "$BBOX" "$MAXZOOM" "$MBTILES" "$NAME" "$TILE_CACHE" "$TILE_COUNT"

rm -rf "$TILE_CACHE"

echo "· converting to PMTiles"
docker run --rm -v "$TERRAIN_DIR:/data" protomaps/go-pmtiles \
  convert "/data/$(basename "$MBTILES")" "/data/$(basename "$OUT")"
rm -f "$MBTILES"

echo
echo "✓ $NAME terrain — $(du -h "$OUT" | cut -f1)"
echo "  Point KAMOME_TERRAIN_PATH at $TERRAIN_DIR, or side-load next to the region."
