#!/usr/bin/env python3
"""
Kamome recap — data pipeline (prototype, 2026-07-20)
====================================================

This is the throwaway Python that turned a folder of 170 real iPhone photos
from an actual 13-day Iceland ring-road trip into the data that drives the
`recap_engine.html` prototype. It is checked in NOT to be run in production
(the app is Swift) but as an executable spec of the DATA FLOW the app must
reproduce. Each stage below names the Swift component that owns it.

    photos (EXIF)  ->  stops  ->  route  ->  base map geometry  ->  recap
      §4.3/§4.7        §4.2       §4.4         MapLibre/§7          §4.5

Crucially this pipeline IS the photo-EXIF importer (spec §4.7). It was built
to feed the prototype, but it proves the cold-start / dogfooding path
end-to-end on real sparse data: a handful of geotagged photos per place is
enough to reconstruct a recognizable trip once the route is snapped to roads
and drawn on real-geometry base map.

Run (macOS, needs `sips` + network for Natural Earth):
    python3 recap_data_pipeline.py ~/Desktop/iceland out/
Produces out/kamome_data.json — inline it into recap_engine.html at __KDATA__.
"""

import sys, os, math, json, subprocess, datetime as dt, base64, urllib.request

# ---------------------------------------------------------------------------
# STAGE 0 — read photo GPS + timestamp   (app: PhotoKit, §4.3)
# ---------------------------------------------------------------------------
# App equivalent: PHAsset.creationDate + PHAsset.location (CLLocation).
# Here we shell out to macOS `mdls` which reads the embedded EXIF. We NEVER
# copy pixels around beyond a thumbnail — same rule as photo_ref in the schema
# (reference by identifier, never duplicate the image).

def read_photos(folder):
    rows = []
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith((".jpeg", ".jpg", ".heic")):
            continue
        out = subprocess.run(
            ["mdls", "-name", "kMDItemContentCreationDate",
             "-name", "kMDItemLatitude", "-name", "kMDItemLongitude",
             "-raw", os.path.join(folder, name)],
            capture_output=True, text=True).stdout
        # -raw joins multiple values with NUL, not newline
        date, lat, lon = (out.split("\0") + ["", "", ""])[:3]
        if lat in ("(null)", ""):
            continue
        try:
            t = dt.datetime.strptime(date.strip()[:19], "%Y-%m-%d %H:%M:%S")
            rows.append((t, float(lat), float(lon), name))
        except ValueError:
            continue
    rows.sort()                       # time order == the real visit order
    return rows


def haversine_km(a_lat, a_lon, b_lat, b_lon):
    R = 6371.0
    p1, p2 = math.radians(a_lat), math.radians(b_lat)
    dp = math.radians(b_lat - a_lat)
    dl = math.radians(b_lon - a_lon)
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(h))


# ---------------------------------------------------------------------------
# STAGE 1 — cluster photos into STOPS   (app: DwellDetector / StopDeriver, §4.2)
# ---------------------------------------------------------------------------
# Time-ordered sweep: keep adding photos to the current cluster while they stay
# within RADIUS_KM of the running centroid; otherwise open a new cluster.
# This is the photo-driven analogue of the app's stop detection — the app has
# richer signals (CLVisit, dwell windows), but the "spatial+temporal cluster =
# a place you spent time" idea is identical. A cluster's photo count is a proxy
# for how much that place mattered (Vestrahorn = 48 photos, a big shoot).

RADIUS_KM = 4.0

def cluster_stops(rows):
    clusters = []
    cur = None
    for t, la, lo, fn in rows:
        if cur is None:
            cur = [(t, la, lo, fn)]; clusters.append(cur); continue
        clat = sum(x[1] for x in cur) / len(cur)
        clon = sum(x[2] for x in cur) / len(cur)
        if haversine_km(clat, clon, la, lo) < RADIUS_KM:
            cur.append((t, la, lo, fn))
        else:
            cur = [(t, la, lo, fn)]; clusters.append(cur)
    stops = []
    for c in clusters:
        stops.append({
            "lat": round(sum(x[1] for x in c) / len(c), 5),
            "lon": round(sum(x[2] for x in c) / len(c), 5),
            "n": len(c),
            "day": (c[0][0].date() - rows[0][0].date()).days + 1,
            "files": [x[3] for x in c],
        })
    return stops


# ---------------------------------------------------------------------------
# STAGE 2 — name stops + pick 3–8 photos each   (app: CLGeocoder §4.3 + curation)
# ---------------------------------------------------------------------------
# App equivalent: reverse-geocode each stop (CLGeocoder honours device locale,
# gives Chinese names natively). The prototype hand-mapped the famous Iceland
# landmarks from coordinates because offline reverse-geocode wasn't available.
# For each chosen stop we pick up to 8 photos spread across its time span — this
# is the OverlayTimeline's per-stop "deck" (see recap decision, §4.5).
#
# NAMED_STOPS: (english, chinese, lat, lon) — nearest cluster wins. Replace with
# CLGeocoder output in the app.
NAMED_STOPS = [
    ("Snæfellsnes",     "斯奈山半島",      64.820, -23.380),
    ("Mývatn",          "米湖 · 北境",     65.626, -16.916),
    ("Vestrahorn",      "西角山 · 東岸",   64.250, -14.980),
    ("Jökulsárlón",     "傑古沙龍冰河湖",  64.050, -16.180),
    ("Skaftafell",      "史卡夫塔冰川",    63.990, -16.880),
    ("Fjaðrárgljúfur",  "羽毛峽谷",        63.778, -18.176),
    ("Skógafoss",       "斯科加瀑布",      63.525, -19.546),
    ("Reynisfjara",     "黑沙灘 · 維克",   63.404, -19.041),
    ("Gullfoss·Geysir", "黃金圈",          64.264, -20.516),
]
MAX_PICS = 8

def choose_named_stops(stops):
    chosen, wanted_files = [], set()
    for en, zh, la, lo in NAMED_STOPS:
        best = min(stops, key=lambda s: haversine_km(la, lo, s["lat"], s["lon"]))
        files, n = best["files"], len(best["files"])
        want = max(3, min(MAX_PICS, n))
        if n <= want:
            pics = files
        else:                          # evenly spread across the visit
            pics = [files[round(i * (n - 1) / (want - 1))] for i in range(want)]
        seen = list(dict.fromkeys(pics))
        chosen.append({"en": en, "zh": zh, "lat": best["lat"], "lon": best["lon"],
                       "day": best["day"], "pics": seen})
        wanted_files.update(seen)
    return chosen, wanted_files


# ---------------------------------------------------------------------------
# STAGE 3 — base map GEOMETRY   (app: MapLibre vector tiles + Kamome style, §7)
# ---------------------------------------------------------------------------
# THE key cartography finding: the base map must use REAL geometry (users
# recognize the place) but a hand-written SUBTRACTIVE style (only coast + glacier
# + route; no POI, no road labels; picked colors) so it never looks like a map
# app. "Souvenir map = real geometry + subtractive styling."
#
# Prototype: Natural Earth 10m coastline + glaciated areas, Douglas–Peucker
# simplified to souvenir level. App: MapLibre renders the same classes of real
# geometry from self-hosted PMTiles; the Kamome style JSON does the subtraction.
# (This is exactly the substrate ADR / vector-tile-pipeline.md — the prototype
# validates WHY it's needed: abstract shapes were unrecognizable and got
# rejected; real coastline was instantly "that's Iceland".)

NE_COUNTRIES = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
                "master/geojson/ne_10m_admin_0_countries.geojson")
NE_GLACIERS = ("https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
               "master/geojson/ne_10m_glaciated_areas.geojson")

def _rdp(pts, eps):                    # Douglas–Peucker (degrees)
    if len(pts) < 3:
        return pts
    a, b = pts[0], pts[-1]
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = _perp(pts[i], a, b)
        if d > dmax:
            dmax, idx = d, i
    if dmax > eps:
        return _rdp(pts[:idx+1], eps)[:-1] + _rdp(pts[idx:], eps)
    return [a, b]

def _perp(p, a, b):
    (x, y), (x1, y1), (x2, y2) = p, a, b
    dx, dy = x2 - x1, y2 - y1
    if dx == 0 and dy == 0:
        return math.hypot(x - x1, y - y1)
    t = max(0, min(1, ((x-x1)*dx + (y-y1)*dy) / (dx*dx + dy*dy)))
    return math.hypot(x - (x1 + t*dx), y - (y1 + t*dy))

def _fetch_json(url, path):
    if not os.path.exists(path):
        urllib.request.urlretrieve(url, path)
    return json.load(open(path))

def base_geometry(cache_dir, country="Iceland",
                  bbox=(-24.7, -13.3, 63.2, 66.7)):   # lon_min, lon_max, lat_min, lat_max
    g = _fetch_json(NE_COUNTRIES, os.path.join(cache_dir, "ne10.json"))
    geom = next(f["geometry"] for f in g["features"]
                if country in (f["properties"].get("NAME") or f["properties"].get("ADMIN") or ""))
    land = []
    for poly in geom["coordinates"]:                  # MultiPolygon
        s = _rdp(poly[0], 0.015)                       # ~1.5 km souvenir detail
        if len(s) >= 8:                                # drop tiny islets
            land.append([[round(la, 4), round(lo, 4)] for lo, la in s])
    land.sort(key=len, reverse=True)
    land = land[:3]

    gd = _fetch_json(NE_GLACIERS, os.path.join(cache_dir, "glac.json"))
    lo0, lo1, la0, la1 = bbox
    rings = []
    for f in gd["features"]:
        polys = (f["geometry"]["coordinates"] if f["geometry"]["type"] == "MultiPolygon"
                 else [f["geometry"]["coordinates"]])
        for poly in polys:
            ring = poly[0]
            cx = sum(p[0] for p in ring) / len(ring)
            cy = sum(p[1] for p in ring) / len(ring)
            if lo0 < cx < lo1 and la0 < cy < la1:
                rings.append(ring)
    rings.sort(key=len, reverse=True)
    glaciers = []
    for ring in rings[:5]:
        s = _rdp(ring, 0.012)
        if len(s) >= 6:
            glaciers.append([[round(la, 4), round(lo, 4)] for lo, la in s])
    return land, glaciers


# ---------------------------------------------------------------------------
# STAGE 4 — thumbnails   (app: PHImageManager request at export resolution)
# ---------------------------------------------------------------------------
def thumbnail_b64(folder, files, out_dir, px=440, quality=52):
    os.makedirs(out_dir, exist_ok=True)
    photos = {}
    for fn in files:
        dst = os.path.join(out_dir, fn)
        subprocess.run(["sips", "-Z", str(px), "-s", "formatOptions", str(quality),
                        os.path.join(folder, fn), "--out", dst],
                       capture_output=True)
        if os.path.exists(dst):
            with open(dst, "rb") as f:
                photos[fn] = "data:image/jpeg;base64," + base64.b64encode(f.read()).decode()
    return photos


# ---------------------------------------------------------------------------
# assemble  ->  kamome_data.json   (consumed by recap_engine.html)
# The route is simply every geotagged photo in time order: the REAL trajectory.
# In the app this is the recorded GPS track (§2.3) or imported points, then
# snapped to roads by OSRM (§4.4) so it never cuts across terrain.
# ---------------------------------------------------------------------------
def main(photo_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    rows = read_photos(photo_dir)
    stops_all = cluster_stops(rows)
    chosen, files = choose_named_stops(stops_all)
    land, glaciers = base_geometry(out_dir)
    photos = thumbnail_b64(photo_dir, sorted(files), os.path.join(out_dir, "thumbs"))
    for s in chosen:
        s["pics"] = [p for p in s["pics"] if p in photos]

    route = [[round(la, 5), round(lo, 5)] for _, la, lo, _ in rows]
    km = sum(haversine_km(route[i][0], route[i][1], route[i+1][0], route[i+1][1])
             for i in range(len(route) - 1))

    data = {"land": land, "glaciers": glaciers, "stops": chosen,
            "route": route, "photos": photos,
            "meta": {"km": round(km), "days": (rows[-1][0].date() - rows[0][0].date()).days + 1}}
    path = os.path.join(out_dir, "kamome_data.json")
    json.dump(data, open(path, "w"), ensure_ascii=False)
    print(f"{len(rows)} photos -> {len(chosen)} stops, {len(route)} route pts, "
          f"{round(km)} km, {len(photos)} thumbnails")
    print(f"wrote {path} — inline it into recap_engine.html at __KDATA__")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: recap_data_pipeline.py <photo_dir> <out_dir>")
    main(os.path.expanduser(sys.argv[1]), os.path.expanduser(sys.argv[2]))
