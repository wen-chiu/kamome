# Fixture vector tiles (Replay MVP §2 substrate)

A **small** Perth-corridor PMTiles crop for exercising `MapLibreSnapshotProvider`
locally and on a sim/device. Regenerate with `./generate_tiles.sh` (needs Docker;
the Planetiler image bundles Java 21). The extract vintage is pinned in the
filename — never `latest` in a fixture (`Docs/vector-tile-pipeline.md` §3).

## What is / isn't checked in

- **In git:** only the small cropped `perth-2026-07-19.pmtiles` (~1.3 MB) — a
  tight Margaret River **coastal** crop of the day-1 corridor, bbox
  `114.96,-34.00,115.16,-33.78`. It overlaps the southern leg of
  `../perth_margaret_river_day1.gpx`, so a rendered frame sits over real WA roads
  and Indian Ocean coastline. (The full corridor tiles to ~20 MB — too big for
  git; widen `$BOUNDS` in `generate_tiles.sh` for a full-region build.)
- **Not in git:** full-region tiles (WA, Taiwan) and Planetiler's downloaded
  auxiliary sources — all live under `~/kamome-osrm/planetiler-*` (gitignored
  location), same as the OSRM data.

## Not wired into golden-frame CI

Golden-frame tests stay on `FlatSnapshotProvider` — bit-stable, no tiles, no
Metal (`Docs/vector-tile-pipeline.md` §8). MapLibre rendering is a Metal path
that is **not** deterministic across machines and is verified on sim/device, not
in CI. These tiles back that manual verification and any future
MapLibre-specific golden test added after Chiu's §3 sign-off.

## Provenance

© OpenStreetMap contributors (ODbL). OSM data via Geofabrik
(`western-australia-latest.osm.pbf`), same extract as `Docs/osrm-setup.md`.
