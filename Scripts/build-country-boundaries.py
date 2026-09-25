#!/usr/bin/env python3
"""Builds Core/ImportKit/Resources/country-boundaries.bin (ADR 2026-09-25).

Journey discovery ends a journey at the first photograph back in the home
country after one taken abroad. That needs "which country is this photograph
in?" answered on the phone: §0 scopes Apple geocoding to stop points, and a
scan runs before any stop exists. This script turns Natural Earth's public-
domain admin-0 boundaries into a compact file the app reads offline.

Source, pinned (never `master`): Natural Earth v5.1.2, 1:10m
  geojson/ne_10m_admin_0_countries.geojson
  geojson/ne_10m_minor_islands.geojson
from https://github.com/nvkelso/natural-earth-vector.

**Taiwan and China are two countries** (Chiu 2026-09-25: 「台灣跟中國不管爭議
就是兩個國家 這在我的app是要明確界線的」). Countries are keyed by `ADM0_A3`
(TWN), never `ISO_A2`, which Natural Earth sets to "CN-TW" for Taiwan. The 1:10m
layer lacks Matsu, Lieyu, Wuqiu and Xiaoliuqiu; their outlines are taken from
the minor-islands layer, which carries no country, by the explicit list below —
never by nearest country, which would hand Matsu to China. Neighbouring islands
in that layer that are China's (Dadeng, Nanri, Pingtan) are not on the list.
Known gap: Dongsha and Taiping have no outline in either layer.

Format: b"KCB2", u32 country count; per country: 3 ASCII bytes (ADM0_A3),
u32 ring count; per ring: u32 point count, then each point's (lon, lat) in units
of UNIT_DEG (~11 m) as zigzag varints — the first absolute, the rest as the
change from the point before. u32 is little-endian. Holes are ordinary rings:
the reader uses the even-odd rule over all of a country's rings. Rings are
Douglas–Peucker simplified at EPSILON_DEG; a ring that would collapse keeps its
four extreme points, so no island vanishes.

Usage: Scripts/build-country-boundaries.py <countries.geojson> <minor_islands.geojson> <out.bin>
"""
import json
import math
import struct
import os
import sys

EPSILON_DEG = 0.01  # ~1.1 km; the app's coast buffer (3 km) absorbs it
UNIT_DEG = 1e-4  # ~11 m: storage precision, far below the simplification
SMALL_RING_FRACTION = 0.02  # a small ring is simplified at 2% of its own extent

# Taiwan's islands missing from the 1:10m admin-0 layer, found in the minor-
# islands layer by the centroid of their outline (matched within MATCH_KM).
TAIWAN_MINOR_ISLANDS = {
    "Lieyu (烈嶼)": (24.432, 118.244),
    "Wuqiu (烏坵)": (24.988, 119.468),
    "Nangan, Matsu (南竿)": (26.158, 119.933),
    "Beigan, Matsu (北竿)": (26.215, 119.991),
    "Dongju, Matsu (東莒)": (25.961, 119.982),
    "Xiju, Matsu (西莒)": (25.975, 119.939),
    "Dongyin, Matsu (東引)": (26.374, 120.491),
    "Xiaoliuqiu (小琉球)": (22.339, 120.362),
}
MATCH_KM = 1.0
CONFIG_PATH = os.path.join(os.path.dirname(__file__), "..", "Config", "TrackingConfig.json")

# Checked after building, on the simplified rings: the build fails if any moves.
EXPECTED = {
    (25.04, 121.56): "TWN",  # Taipei
    (24.44, 118.37): "TWN",  # Kinmen
    (24.43, 118.24): "TWN",  # Lieyu
    (26.155, 119.93): "TWN",  # Nangan, Matsu
    (26.37, 120.49): "TWN",  # Dongyin, Matsu
    (23.57, 119.58): "TWN",  # Penghu
    (22.05, 121.55): "TWN",  # Lanyu
    (22.34, 120.37): "TWN",  # Xiaoliuqiu
    (26.07, 119.30): "CHN",  # Fuzhou
    (24.53, 118.10): "CHN",  # Xiamen
    (24.34, 124.16): "JPN",  # Ishigaki
    (24.465, 122.99): "JPN",  # Yonaguni
    (35.68, 139.65): "JPN",  # Tokyo
    (33.50, 126.53): "KOR",  # Jeju
    (48.86, 2.35): "FRA",  # Paris
    (46.20, 6.14): "CHE",  # Geneva
}


def km(lat1, lon1, lat2, lon2):
    p1, p2 = math.radians(lat1), math.radians(lat2)
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 12742 * math.asin(min(1, math.sqrt(h)))


def rings_of(geometry):
    polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    return [ring for polygon in polygons for ring in polygon]


def centroid(ring):
    return sum(p[1] for p in ring) / len(ring), sum(p[0] for p in ring) / len(ring)


def douglas_peucker(points, epsilon):
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        first, last = stack.pop()
        (x1, y1), (x2, y2) = points[first][:2], points[last][:2]
        dx, dy = x2 - x1, y2 - y1
        norm = math.hypot(dx, dy)
        best, index = 0.0, None
        for i in range(first + 1, last):
            x, y = points[i][:2]
            d = abs(dy * x - dx * y + x2 * y1 - y2 * x1) / norm if norm else math.hypot(x - x1, y - y1)
            if d > best:
                best, index = d, i
        if index is not None and best > epsilon:
            keep[index] = True
            stack += [(first, index), (index, last)]
    return [p for p, k in zip(points, keep) if k]


def simplify(ring):
    open_ring = ring[:-1] if ring[0] == ring[-1] else ring
    # Split at the far point so a closed ring's two ends are not one "segment".
    far = max(range(len(open_ring)), key=lambda i: math.hypot(open_ring[i][0] - open_ring[0][0], open_ring[i][1] - open_ring[0][1]))
    # Scaled to the ring: 1 km off a 3 km island is most of the island, and an
    # island's few points cost nothing. Coastlines a continent long get the cap.
    extent = math.hypot(max(p[0] for p in open_ring) - min(p[0] for p in open_ring),
                        max(p[1] for p in open_ring) - min(p[1] for p in open_ring))
    epsilon = min(EPSILON_DEG, extent * SMALL_RING_FRACTION)
    a = douglas_peucker(open_ring[: far + 1], epsilon)
    b = douglas_peucker(open_ring[far:] + [open_ring[0]], epsilon)
    out = a[:-1] + b[:-1]
    if len(out) < 3:
        extremes = [min(open_ring, key=lambda p: p[0]), min(open_ring, key=lambda p: p[1]),
                    max(open_ring, key=lambda p: p[0]), max(open_ring, key=lambda p: p[1])]
        out = []
        for p in extremes:
            if p not in out:
                out.append(p)
    # Quantised here, so the checks below test exactly what the app will read.
    return [(round(p[0] / UNIT_DEG) * UNIT_DEG, round(p[1] / UNIT_DEG) * UNIT_DEG) for p in out]


def varint(value):
    zigzag = value * 2 if value >= 0 else -value * 2 - 1
    out = bytearray()
    while True:
        byte = zigzag & 0x7F
        zigzag >>= 7
        if zigzag:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def distance_m(lat, lon, ring):
    """Distance to the ring's nearest edge on a local flat projection, as the app measures it."""
    per_lat = 111_320.0
    per_lon = per_lat * math.cos(math.radians(lat))
    best = math.inf
    for (x1, y1), (x2, y2) in zip(ring, ring[1:] + ring[:1]):
        ax, ay = (x1 - lon) * per_lon, (y1 - lat) * per_lat
        bx, by = (x2 - lon) * per_lon, (y2 - lat) * per_lat
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        t = min(max(-(ax * dx + ay * dy) / length, 0), 1) if length else 0
        best = min(best, math.hypot(ax + t * dx, ay + t * dy))
    return best


def inside(lat, lon, rings):
    hit = False
    for ring in rings:
        j = len(ring) - 1
        for i in range(len(ring)):
            xi, yi = ring[i]
            xj, yj = ring[j]
            if (yi > lat) != (yj > lat) and lon < (xj - xi) * (lat - yi) / (yj - yi) + xi:
                hit = not hit
            j = i
    return hit


def main(countries_path, islands_path, out_path):
    countries = {}
    for feature in json.load(open(countries_path, encoding="utf-8"))["features"]:
        code = feature["properties"]["ADM0_A3"]
        assert len(code) == 3 and code.isascii(), code
        countries.setdefault(code, []).extend(rings_of(feature["geometry"]))

    islands = [ring for f in json.load(open(islands_path, encoding="utf-8"))["features"] for ring in rings_of(f["geometry"])]
    for name, (lat, lon) in TAIWAN_MINOR_ISLANDS.items():
        matches = [r for r in islands if km(lat, lon, *centroid(r)) < MATCH_KM]
        if len(matches) != 1:
            sys.exit(f"{name}: expected one outline within {MATCH_KM} km, found {len(matches)}")
        countries["TWN"].append(matches[0])

    simplified = {code: [simplify(r) for r in rings] for code, rings in sorted(countries.items())}

    # Resolved as the app resolves (`CountryBoundaries.country`): inside, else the
    # nearest outline within the configured coast buffer.
    config = json.load(open(CONFIG_PATH, encoding="utf-8"))
    buffer_m = config["discovery"]["country_coast_buffer_m"]
    for (lat, lon), want in EXPECTED.items():
        got = [code for code, rings in simplified.items() if inside(lat, lon, rings)]
        if not got:
            near = [(distance_m(lat, lon, ring), code) for code, rings in simplified.items() for ring in rings]
            near = [n for n in near if n[0] <= buffer_m]
            got = [min(near)[1]] if near else []
        if got != [want]:
            sys.exit(f"({lat}, {lon}) resolves to {got}, expected {want}")

    with open(out_path, "wb") as out:
        out.write(b"KCB2" + struct.pack("<I", len(simplified)))
        for code, rings in simplified.items():
            out.write(code.encode("ascii") + struct.pack("<I", len(rings)))
            for ring in rings:
                out.write(struct.pack("<I", len(ring)))
                previous = (0, 0)
                for lon, lat in ring:
                    point = (round(lon / UNIT_DEG), round(lat / UNIT_DEG))
                    out.write(varint(point[0] - previous[0]) + varint(point[1] - previous[1]))
                    previous = point
    points = sum(len(r) for rings in simplified.values() for r in rings)
    print(f"{len(simplified)} countries, {points} points, epsilon {EPSILON_DEG}° -> {out_path}")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
