# Deploy — self-hosted routing and map regions

Everything Kamome needs that is not the app: an OSRM the phone can reach, and
map tiles for the places you actually travelled.

**Local now, VPS later** (Chiu 2026-07-29). The whole stack runs on a laptop over
home Wi-Fi today. Nothing here assumes that is permanent — the same
`docker-compose.yml` runs on a Hetzner box with `--profile public`, which adds
the TLS reverse proxy. That is the only difference.

```
Deploy/
  regions.json        which places to cover — the single source for both halves
  docker-compose.yml  osrm-routed; caddy behind a `public` profile
  Caddyfile           TLS + endpoint allow-list, inactive locally
  .env.example        copy to .env; every value has a working local default
  bin/
    fetch-extracts.sh  download Geofabrik sources
    build-osrm.sh      clip → merge → one routing dataset
    build-tiles.sh     one .pmtiles per region
```

## First run

```bash
./Deploy/bin/fetch-extracts.sh     # ~1.4 GB down
./Deploy/bin/build-osrm.sh         # the slow one; osrm-extract is memory-hungry
./Deploy/bin/build-tiles.sh        # one region file each
cd Deploy && docker compose up -d
```

Then point the app at it in `Config/TrackingConfig.json`:

```json
"matching": { "base_url": "http://127.0.0.1:5100" }
```

Use the Mac's LAN address (`ipconfig getifaddr en0`) instead of `127.0.0.1` when
testing from a real iPhone rather than the simulator.

Check it answers:

```bash
curl -s "http://127.0.0.1:5100/nearest/v1/driving/-21.94,64.15" | head -c 120
```

## Adding or changing a region

Edit `Deploy/regions.json` and re-run the three scripts. Nothing else knows the
list. `KAMOME_REGIONS="iceland finland" ./Deploy/bin/build-tiles.sh` builds a
subset.

`bbox` clips a source to an area (`W,S,E,N`, or `null` for the whole extract).
Clip when a country is far bigger than anywhere you went — it is the lever that
decides whether `osrm-extract` fits in RAM, and how much disk the result takes.

## Two shapes, on purpose

**Routing is one merged dataset.** OSRM serves exactly one dataset per process,
and `matching.base_url` is a single value, so the app cannot pick a server per
trip. Merging first means one process and one URL. Teaching the app to route by
region is the infrastructure this arrangement exists to avoid.

**Tiles are one file per region.** A `.pmtiles` covers a bounded area, and the
app picks the one covering each trip by reading its header (`RecapMapTiles`).
Merging those would mean one enormous file where a phone only ever needs the
region it is rendering.

## Moving to a VPS

1. Copy `Deploy/` and `$KAMOME_DATA_DIR` to the box (or rebuild there — only the
   `.osrm.*` files are slow to produce).
2. `cp .env.example .env`, set `OSRM_BIND=127.0.0.1` and `OSRM_DOMAIN`.
3. Point the DNS name at the box.
4. `docker compose --profile public up -d`.
5. Set `matching.base_url` to `https://your-domain`.

⚠️ **Do not skip step 2.** With `OSRM_BIND=0.0.0.0` on a public box, OSRM is
exposed directly: no authentication, no rate limiting, and iOS blocks plain HTTP
from the app anyway.

⚠️ **Token auth is not implemented.** `Caddyfile` carries the server half
commented out; the app half does not exist — both OSRM providers send bare
requests. Enabling one without the other makes every request 403, and because a
routing failure means "keep raw geometry", **every leg would silently render
dashed** with nothing saying why. Tracked in `Docs/_archive/handoff-P3.5.md` under "VPS
migration — deferred security work". Ship both halves together.

## Disk

Built artifacts live in `$KAMOME_DATA_DIR` (default `~/kamome-osrm`), never in
git. Budget roughly **10× the merged `.osm.pbf`** for the `.osrm.*` files, plus
the tiles. The scripts refuse to start when free space looks short; override with
`KAMOME_FORCE=1` once you have checked.
