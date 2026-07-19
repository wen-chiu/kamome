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
    command: osrm-routed --algorithm mld /data/taiwan-latest.osrm
    volumes: [".:/data"]
    ports: ["5000:5000"]
  osrm-australia:
    image: osrm/osrm-backend
    command: osrm-routed --algorithm mld /data/australia-latest.osrm
    volumes: [".:/data"]
    ports: ["5001:5000"]
```

```bash
docker compose up -d
```

Region selection is manual for now (set `base_url` to the port covering the
trip). Auto-selection by trip bounding box is a P4 concern — do not build it
before an importer needs it.

## 4. Point the app at it

`Config/TrackingConfig.json`:

- Simulator: `"base_url": "http://127.0.0.1:5000"`
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
Capture one recorded `/match` response for the perth fixture into
`Tests/Fixtures/` when P4's replay-in-CI gate lands (the transport hook on
`OSRMMatchProvider` is built for exactly that).

## Troubleshooting

- `NoSegment` / empty matchings: points are too far from any drivable way —
  check you queried the right region/port.
- Chunk-size errors (`TooBig`): OSRM caps match locations at 100 per request
  by default; `matching.chunk_size` must stay ≤ 100 (or raise the server's
  `--max-matching-size`, not recommended).
- Low confidence on sparse traces: expected on passive-tier density (P5) —
  that is what `matching.confidence_min` and the raw-polyline fallback are
  for. Do not lower the floor to force matches.
