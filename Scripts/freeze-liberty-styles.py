#!/usr/bin/env python3
"""Generates the two frozen OpenFreeMap Liberty styles for Kamome's export.

One transform, two palettes: every subtractive rule is identical — layer
removals, the two-layer road skeleton, peaks (ele >= 1000, rank <= 1), island
labels, hillshade, coast by contrast only, no lake edge. Only the colour set
differs: dark uses the souvenir palette, light keeps Liberty's own.

Usage:
    python3 Scripts/freeze-liberty-styles.py [--check]

Without --check, writes the two JSON files to Config/RecapThemes/.
With --check, fetches upstream, re-runs the transform, and diffs against the
committed files — exits 0 if identical, 1 if they differ.
"""

import json
import os
import sys
import urllib.request


STOCK_URL = "https://tiles.openfreemap.org/styles/liberty"
DARK_OUT = "Config/RecapThemes/openfreemap-liberty-dark.json"
LIGHT_OUT = "Config/RecapThemes/openfreemap-liberty-light.json"

# The tile set the committed styles were frozen against.
FORKED_AGAINST_TILE_SET = "20260917_freeze"


# ── Terrain (D1: Chiu 2026-09-17 「D1 要 hillshade」) ──────────────────────

TERRAIN_SOURCE_ID = "kamome-terrain"

TERRAIN_SOURCE = {
    "type": "raster-dem",
    "tiles": ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
    "encoding": "terrarium",
    "tileSize": 256,
    "maxzoom": 13,
    "attribution": "Elevation data: Mapzen Terrain Tiles / AWS Open Data"
}

DARK_HILLSHADE_PAINT = {
    "hillshade-exaggeration": 0.85,
    "hillshade-shadow-color": "#03070d",
    "hillshade-highlight-color": "#4f7f95",
    "hillshade-accent-color": "#0a1420",
    "hillshade-illumination-direction": 315,
    "hillshade-illumination-anchor": "map",
}

LIGHT_HILLSHADE_PAINT = {
    "hillshade-exaggeration": 0.5,
    "hillshade-shadow-color": "#5a6872",
    "hillshade-highlight-color": "#ffffff",
    "hillshade-accent-color": "#d0d8de",
    "hillshade-illumination-direction": 315,
    "hillshade-illumination-anchor": "map",
}


# ── Layer removals ──────────────────────────────────────────────────────

REMOVED_LAYER_IDS = {
    "poi_r1", "poi_r7", "poi_r20", "poi_transit",
    "highway-shield-non-us", "highway-shield-us-interstate", "road_shield_us",
    "highway-name-path", "highway-name-minor", "highway-name-major",
    "building", "building-3d",
    "aeroway_fill", "aeroway_runway", "aeroway_taxiway", "airport",
}


# ── Dark palette (souvenir, from modern-minimal.json) ───────────────────

class DarkPalette:
    land = "#243440"
    water = "#080b10"
    water_edge = "#4d7f86"
    waterway = "#3f6b72"
    wood = "#213039"
    scrub = "#132b32"
    wetland = "#12303a"
    sand = "#26313a"
    park = "#102a2a"
    ice = "#55646b"  # Round 3: opaque glacier, pre-blended
    road = "#3a4a54"
    label_text = "#e8f1f4"
    label_halo = "#0b141a"
    peak = "#9fd8e8"


# ── Helpers ─────────────────────────────────────────────────────────────

def ramp(low_zoom, low_val, high_zoom, high_val):
    return ["interpolate", ["linear"], ["zoom"], low_zoom, low_val, high_zoom, high_val]


def source_layer(layer):
    return layer.get("source-layer", "")


def position_of(layer_id, layers):
    for i, l in enumerate(layers):
        if l.get("id") == layer_id:
            return i
    return None


DOUBLED_LABEL_IDS = {
    "label_country_1", "label_country_2", "label_country_3",
    "label_city", "label_city_capital", "label_town",
}


def doubled(size):
    if isinstance(size, (int, float)):
        return size * 2
    if isinstance(size, list) and len(size) > 4:
        result = list(size)
        for i in range(4, len(result), 2):
            if isinstance(result[i], (int, float)):
                result[i] = result[i] * 2
        return result
    return size


# ── Skeleton roads ──────────────────────────────────────────────────────

SKELETON = [
    {"id": "road-major", "classes": ["motorway", "trunk", "primary"], "minzoom": 8},
    {"id": "road-secondary", "classes": ["secondary"], "minzoom": 11},
]


def skeleton_layer(road, paint):
    filt = [
        "all",
        ["match", ["geometry-type"], ["LineString", "MultiLineString"], True, False],
        ["match", ["get", "class"], road["classes"], True, False],
    ]
    return {
        "id": road["id"], "type": "line", "source": "openmaptiles",
        "source-layer": "transportation", "minzoom": road["minzoom"],
        "filter": filt,
        "layout": {"line-cap": "round", "line-join": "round"},
        "paint": paint,
    }


# ── Peaks ───────────────────────────────────────────────────────────────

PEAK_MIN_ELEVATION_M = 1000
PEAK_MAX_RANK = 1


def peak_layers(layers, text_color, halo_color, dot_color):
    town_idx = position_of("label_town", layers)
    if town_idx is None:
        raise ValueError("no label_town to name peaks with")
    town = layers[town_idx]
    town_layout = town.get("layout", {})
    name_field = town_layout.get("text-field")
    if not name_field:
        raise ValueError("no label_town text-field")

    filt = ["all", [">=", ["get", "ele"], PEAK_MIN_ELEVATION_M], ["<=", ["get", "rank"], PEAK_MAX_RANK]]
    base = {"source": "openmaptiles", "source-layer": "mountain_peak", "minzoom": 7, "filter": filt}

    dot_paint = {"circle-color": dot_color, "circle-radius": ramp(7, 2.5, 12, 4.0), "circle-opacity": 0.9}
    height = ["concat", ["to-string", ["get", "ele"]], " m"]
    name_layout = {
        "text-field": ["format", name_field, {}, "\n", {}, height, {"font-scale": 0.75}],
        "text-font": ["Noto Sans Regular"],
        "text-size": ramp(7, 16, 12, 20), "text-anchor": "top",
        "text-offset": [0, 0.6], "text-max-width": 8,
    }
    name_paint = {
        "text-color": text_color, "text-halo-color": halo_color,
        "text-halo-width": 1, "text-halo-blur": 1,
    }

    dot = {**base, "id": "mountain-peak-dot", "type": "circle", "paint": dot_paint}
    label = {**base, "id": "mountain-peak-name", "type": "symbol", "layout": name_layout, "paint": name_paint}
    return [dot, label]


# ── Island labels ───────────────────────────────────────────────────────

ISLAND_MAX_RANK = 2
ISLAND_SIZE_OVER_CITY = 1.25


def with_island_labels(layers, text_color=None, halo_color=None):
    other_idx = position_of("label_other", layers)
    town_idx = position_of("label_town", layers)
    if other_idx is None or town_idx is None:
        raise ValueError("no label_other or label_town")

    other = dict(layers[other_idx])
    filt = list(other.get("filter", []))
    if len(filt) >= 3 and isinstance(filt[2], list):
        excluded = list(filt[2])
        excluded.append("island")
        filt[2] = excluded
        other["filter"] = filt
    layers[other_idx] = other

    town = layers[town_idx]
    island = dict(town)
    island["id"] = "label_island"
    island["minzoom"] = 8
    island["filter"] = ["all", ["==", ["get", "class"], "island"],
                         ["<=", ["get", "rank"], ISLAND_MAX_RANK]]
    layout = dict(town.get("layout", {}))
    for key in ["icon-allow-overlap", "icon-image", "icon-optional", "icon-size", "text-transform"]:
        layout.pop(key, None)
    layout["text-anchor"] = "center"

    city_layout = None
    for l in layers:
        if l.get("id") == "label_city":
            city_layout = l.get("layout", {})
            break
    city_size = city_layout.get("text-size") if city_layout else None
    if city_size is not None:
        layout["text-size"] = scaled(city_size, ISLAND_SIZE_OVER_CITY)
    island["layout"] = layout

    if text_color is not None or halo_color is not None:
        paint = dict(island.get("paint", {}))
        if text_color is not None:
            paint["text-color"] = text_color
        if halo_color is not None:
            paint["text-halo-color"] = halo_color
        island["paint"] = paint

    place_labels = ["label_city_capital", "label_city", "label_town"]
    last_place = None
    for i, l in enumerate(layers):
        if l.get("id") in place_labels:
            last_place = i
    insert_at = (last_place + 1) if last_place is not None else len(layers)
    layers.insert(insert_at, island)
    return layers


def scaled(size, factor):
    if isinstance(size, (int, float)):
        return size * factor
    if isinstance(size, list) and len(size) > 4:
        result = list(size)
        for i in range(4, len(result), 2):
            if isinstance(result[i], (int, float)):
                result[i] = result[i] * factor
        return result
    return size


# ── The transform ───────────────────────────────────────────────────────

def transform(stock, dark=True):
    """Apply the frozen fork transform to the stock Liberty style."""
    layers = list(stock["layers"])

    # 1. Remove furniture layers
    layers = [l for l in layers if l.get("id", "") not in REMOVED_LAYER_IDS]

    # 2. Dark palette repaint (skip for light)
    if dark:
        layers = [repaint_dark(l) for l in layers]

    # 3. Replace all transportation layers with skeleton
    first_transport = None
    for i, l in enumerate(layers):
        if source_layer(l) == "transportation":
            if first_transport is None:
                first_transport = i
            break

    kept = [l for l in layers if source_layer(l) != "transportation"]
    insert_at = min(first_transport, len(kept)) if first_transport is not None else len(kept)

    if dark:
        road_paint = {
            "line-color": DarkPalette.road,
            "line-opacity": ramp(8, 0.25, 14, 0.5),
            "line-width": ramp(8, 0.5, 14, 2.0),
        }
    else:
        road_paint = {
            "line-color": "#b8b8b8",
            "line-opacity": ramp(8, 0.4, 14, 0.6),
            "line-width": ramp(8, 0.5, 14, 2.0),
        }

    skeleton_layers = [skeleton_layer(r, road_paint) for r in SKELETON]
    kept[insert_at:insert_at] = skeleton_layers
    layers = kept

    # 4. Opaque glacier
    if dark:
        layers = [opaque_glacier(l) for l in layers]

    # 5. Doubled labels
    if dark:
        layers = [enlarge_label_dark(l) for l in layers]
    else:
        layers = [enlarge_label_light(l) for l in layers]

    # 6. Island labels
    if dark:
        layers = with_island_labels(layers, text_color=DarkPalette.label_text, halo_color=DarkPalette.label_halo)
    else:
        layers = with_island_labels(layers)

    # 7. Peaks (before place labels)
    first_place = None
    for i, l in enumerate(layers):
        if source_layer(l) == "place":
            first_place = i
            break
    insert_at = first_place if first_place is not None else len(layers)

    if dark:
        peaks = peak_layers(layers, DarkPalette.label_text, DarkPalette.label_halo, DarkPalette.peak)
    else:
        peaks = peak_layers(layers, "#333333", "#ffffff", "#7a8a6a")

    layers[insert_at:insert_at] = peaks

    # 8. Terrain hillshade (D1, Chiu 2026-09-17)
    hillshade_paint = DARK_HILLSHADE_PAINT if dark else LIGHT_HILLSHADE_PAINT
    hillshade_layer = {
        "id": "hillshade", "type": "hillshade", "source": TERRAIN_SOURCE_ID,
        "paint": hillshade_paint,
    }
    # Directly above the land background, exactly where the souvenir map puts it.
    if layers and layers[0].get("type") == "background":
        layers.insert(1, hillshade_layer)
    else:
        layers.insert(0, hillshade_layer)

    style = dict(stock)
    style["layers"] = layers
    # Add the terrain DEM source alongside the existing sources.
    sources = dict(style.get("sources", {}))
    sources[TERRAIN_SOURCE_ID] = TERRAIN_SOURCE
    style["sources"] = sources
    style["metadata"] = {
        "kamome:forkedAgainstTileSet": FORKED_AGAINST_TILE_SET,
        "kamome:variant": "dark" if dark else "light",
    }
    return style


def repaint_dark(layer):
    """Apply the souvenir palette to one layer."""
    layer = dict(layer)
    lid = layer.get("id", "")
    sl = source_layer(layer)
    ltype = layer.get("type", "")

    override = None

    if lid == "background":
        override = {"background-color": DarkPalette.land}
    elif lid == "water":
        override = {"fill-color": DarkPalette.water}
    elif lid == "park":
        override = {"fill-color": DarkPalette.park, "fill-opacity": 0.35}
    elif lid == "park_outline":
        override = {"line-color": DarkPalette.park}
    elif lid == "landcover_wood":
        override = {"fill-color": DarkPalette.wood, "fill-opacity": 0.55}
    elif lid == "landcover_grass":
        override = {"fill-color": DarkPalette.scrub, "fill-opacity": 0.45}
    elif lid == "landcover_wetland":
        override = {"fill-color": DarkPalette.wetland, "fill-opacity": 0.45}
    elif lid == "landcover_sand":
        override = {"fill-color": DarkPalette.sand, "fill-opacity": 0.45}
    elif lid == "landcover_ice":
        override = {"fill-color": DarkPalette.ice, "fill-opacity": 1.0}
    elif sl == "landuse" and ltype == "fill":
        override = {"fill-color": DarkPalette.land}
    elif sl == "waterway" and ltype == "line":
        override = {"line-color": DarkPalette.waterway, "line-opacity": ramp(6, 0.2, 12, 0.3)}

    if override is not None:
        paint = dict(layer.get("paint", {}))
        paint.update(override)
        if "fill-color" in override:
            paint.pop("fill-pattern", None)
            paint.pop("fill-outline-color", None)
        layer["paint"] = paint

    return layer


def opaque_glacier(layer):
    if layer.get("id") != "landcover_ice":
        return layer
    layer = dict(layer)
    paint = dict(layer.get("paint", {}))
    paint["fill-color"] = DarkPalette.ice
    paint["fill-opacity"] = 1.0
    layer["paint"] = paint
    return layer


def enlarge_label_dark(layer):
    if layer.get("type") != "symbol":
        return layer
    layer = dict(layer)
    paint = dict(layer.get("paint", {}))
    paint["text-color"] = DarkPalette.label_text
    paint["text-halo-color"] = DarkPalette.label_halo
    layer["paint"] = paint

    if layer.get("id", "") in DOUBLED_LABEL_IDS:
        layout = dict(layer.get("layout", {}))
        if "text-size" in layout:
            layout["text-size"] = doubled(layout["text-size"])
            layer["layout"] = layout

    return layer


def enlarge_label_light(layer):
    """For light: only double the sizes, keep stock Liberty colours."""
    if layer.get("type") != "symbol":
        return layer
    if layer.get("id", "") not in DOUBLED_LABEL_IDS:
        return layer
    layer = dict(layer)
    layout = dict(layer.get("layout", {}))
    if "text-size" in layout:
        layout["text-size"] = doubled(layout["text-size"])
        layer["layout"] = layout
    return layer


# ── Main ────────────────────────────────────────────────────────────────

def fetch_stock(local_path=None):
    if local_path and os.path.exists(local_path):
        with open(local_path) as f:
            return json.load(f)
    import certifi
    req = urllib.request.Request(STOCK_URL)
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def write_style(style, path):
    with open(path, "w") as f:
        json.dump(style, f, indent=2, ensure_ascii=False)
        f.write("\n")


def main():
    check_mode = "--check" in sys.argv

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(repo_root)

    local_stock = os.environ.get("LIBERTY_STOCK_PATH")
    stock = fetch_stock(local_path=local_stock)

    dark = transform(stock, dark=True)
    light = transform(stock, dark=False)

    if check_mode:
        dark_json = json.dumps(dark, indent=2, ensure_ascii=False) + "\n"
        light_json = json.dumps(light, indent=2, ensure_ascii=False) + "\n"

        with open(DARK_OUT) as f:
            committed_dark = f.read()
        with open(LIGHT_OUT) as f:
            committed_light = f.read()

        ok = True
        if dark_json != committed_dark:
            print(f"FAIL  {DARK_OUT} differs from upstream transform", file=sys.stderr)
            ok = False
        else:
            print(f"  ok  {DARK_OUT} matches upstream")

        if light_json != committed_light:
            print(f"FAIL  {LIGHT_OUT} differs from upstream transform", file=sys.stderr)
            ok = False
        else:
            print(f"  ok  {LIGHT_OUT} matches upstream")

        sys.exit(0 if ok else 1)
    else:
        write_style(dark, DARK_OUT)
        write_style(light, LIGHT_OUT)
        print(f"wrote {DARK_OUT}")
        print(f"wrote {LIGHT_OUT}")
        print(f"forked against tile set: {FORKED_AGAINST_TILE_SET}")
        print(f"dark layers: {len(dark['layers'])}")
        print(f"light layers: {len(light['layers'])}")


if __name__ == "__main__":
    main()
