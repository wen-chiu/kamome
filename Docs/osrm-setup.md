# OSRM map-matching server — setup & validation

Self-hosted OSRM backing §4.4 map matching, pulled forward into Phase 3.5
(decisions.md 2026-07-19): the recap replay must follow real roads, never
straight lines between GPS points. The same Geofabrik extracts later feed the
Planetiler → PMTiles vector-tile build (`Docs/vector-tile-pipeline.md`), so
keep the downloaded `.osm.pbf` files.

The app side is already wired and dormant: `matching.base_url` in
`Config/TrackingConfig.json` is `""` (disabled). Point it at a running server
and every newly ended trip — and any recap export — matches automatically
(`RouteMatchService`; drive/scooter segments only, walks stay raw).

## 1. Get extracts

```bash
mkdir -p ~/kamome-osrm && cd ~/kamome-osrm
curl -LO https://download.geofabrik.de/asia/taiwan-latest.osm.pbf
curl -LO https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf
```

**Low-RAM machines — use the Western Australia state extract for the perth
fixture.** Full `australia-latest` needs ~8 GB RAM for `osrm-extract`; on an
8 GB Docker allocation that OOMs. The perth fixture is in Western Australia,
and `Docs/vector-tile-pipeline.md` already endorses the WA state extract for
this region, so swap it in:

```bash
curl -LO https://download.geofabrik.de/australia-oceania/australia/western-australia-latest.osm.pbf
```

Then use `western-australia` in place of `australia` throughout the steps
below. (Setup on 2026-07-19 used this on an 8 GB machine — full Australia
was not attempted.)

## 2. Preprocess (once per extract, car profile)

MLD pipeline; Australia needs ~8 GB RAM for the extract step.

```bash
for region in taiwan australia; do
  docker run --rm -t -v "$PWD:/data" osrm/osrm-backend \
    osrm-extract -p /opt/car.lua "/data/${region}-latest.osm.pbf"
  docker run --rm -t -v "$PWD:/data" osrm/osrm-backend \
    osrm-partition "/data/${region}-latest.osrm"
  docker run --rm -t -v "$PWD:/data" osrm/osrm-backend \
    osrm-customize "/data/${region}-latest.osrm"
done
```

## 3. Serve

One region per port — OSRM serves a single dataset per process. Compose file
(`~/kamome-osrm/docker-compose.yml`):

```yaml
services:
  osrm-taiwan:
    image: osrm/osrm-backend
    restart: unless-stopped
    command: osrm-routed --algorithm mld /data/taiwan-latest.osrm
    volumes: [".:/data"]
    # macOS: host 5000 is taken by AirPlay Receiver (ControlCenter) — use 5002
    ports: ["5002:5000"]
  osrm-australia:
    image: osrm/osrm-backend
    restart: unless-stopped
    # low-RAM machines: western-australia-latest.osrm covers the perth fixture
    command: osrm-routed --algorithm mld /data/australia-latest.osrm
    volumes: [".:/data"]
    ports: ["5001:5000"]
```

```bash
docker compose up -d
```

`restart: unless-stopped` brings the servers back after a Docker or machine
restart; the preprocessed `.osrm*` files persist on disk, so no reprocessing
is needed — just `docker compose up -d` from `~/kamome-osrm` again.

Region selection is manual for now (set `base_url` to the port covering the
trip). Auto-selection by trip bounding box is deferred (region auto-select is
not needed while `base_url` ships `""` = disabled) — do not build it before a
consumer needs it.

## 4. Point the app at it

`Config/TrackingConfig.json`:

- Simulator, perth fixture (WA): `"base_url": "http://127.0.0.1:5001"`
- Simulator, Taiwan: `"base_url": "http://127.0.0.1:5002"` (5000 = AirPlay)
- Physical device: `"base_url": "http://<Mac-LAN-IP>:5000"` — plain HTTP to a
  private-network host; if ATS blocks it, add an
  `NSAllowsLocalNetworking`-scoped exception in project.yml (dev builds
  only), never a blanket `NSAllowsArbitraryLoads`.

## 5. Validate

Smoke-check the server with two points on Perth's Kwinana Freeway:

```bash
curl -s "http://127.0.0.1:5001/match/v1/driving/115.8496,-32.0397;115.8501,-32.0497?geometries=polyline&tidy=true&radiuses=25;25" | python3 -m json.tool | head
```

Expect `"code": "Ok"` with a non-empty `matchings` array. Then the real
check: run the app (sim), open the perth fixture trip
(`Docs/demos/phase3/` seeding notes), export a recap, and confirm the
replay follows the freeway curves where the P3 artifact cut corners.
A recorded `/match` response for the perth fixture is already checked into
`Tests/Fixtures/osrm/` and replayed in CI (done in the Replay MVP / P3.5
matching validation; the transport hook on `OSRMMatchProvider` is built for
exactly that).

## Troubleshooting

- `NoSegment` / empty matchings: points are too far from any drivable way —
  check you queried the right region/port.
- Chunk-size errors (`TooBig`): OSRM caps match locations at 100 per request
  by default; `matching.chunk_size` must stay ≤ 100 (or raise the server's
  `--max-matching-size`, not recommended).
- Low confidence on sparse traces: expected on sparse photo-EXIF points (Replay
  MVP) and later passive-tier density (Capture Beta) —
  that is what `matching.confidence_min` and the raw-polyline fallback are
  for. Do not lower the floor to force matches. (The two-point freeway smoke
  in §5 returns `code: Ok` with `confidence: 0` — normal for a 2-location
  request; the real per-segment match on the fixture has real confidence.)
- `bind: address already in use` on 5000 (macOS): AirPlay Receiver
  (ControlCenter) listens on 5000. Map the container to 5002 instead
  (`ports: ["5002:5000"]`) rather than disabling AirPlay.
- `osrm-extract` killed / OOM: the extract step is the RAM peak. Full
  Australia needs ~8 GB; drop to the `western-australia` state extract (§1).
