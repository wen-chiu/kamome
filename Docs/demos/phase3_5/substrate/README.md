# Replay MVP §2 — MapLibre souvenir-map substrate (demo artifact)

Landed 2026-07-21 on `phase-3-recap`. This is the **functional substrate**, not
the shipping look: Modern Minimal (§3) is a separate step gated on Chiu's
side-by-side design review. MapKit is still the base map users see until then.

## What landed (verified in-repo, CI-green)

- **MapLibre `6.27.0`** via SPM (exact pin), app target only.
- **`App/Services/MapLibreSnapshotProvider.swift`** — conforms to the existing
  `RecapSnapshotProviding` boundary; the **only** file that imports MapLibre
  (CI grep gate). Projection travels with the snapshot
  (`MLNMapSnapshot.point(for:)`); center + span → MapLibre zoom (Web Mercator,
  512 px tiles, `scale = 1`). No pitch/bearing yet (follow-cam, §4).
- **`App/Services/RecapMapStyle.swift`** — pure (no SDK) resolver that injects the
  on-disk tiles path into a theme's `pmtiles://__KAMOME_TILES__` sentinel.
  Unit-tested, so tile wiring is proven without a Metal render.
- **`Config/RecapThemes/functional-base.json`** — subtractive style (land, water,
  a quiet road skeleton; no POI, no labels). OSM attribution set on the source.
- **`Tests/Fixtures/tiles/perth-2026-07-19.pmtiles`** — small Perth-corridor crop
  (`generate_tiles.sh`, Planetiler via Docker). Matches
  `Tests/Fixtures/perth_margaret_river_day1.gpx`.
- Tests: `Tests/AppTests/MapLibreSubstrateTests.swift` (style resolution, zoom
  math, boundary conformance). Golden-frame CI unchanged (`FlatSnapshotProvider`).

## What is NOT self-certified here (needs sim/device — flagged, not faked)

The actual MapLibre **pixel output** is a Metal path and is deliberately **not**
in CI (non-deterministic across machines; golden-frame discipline, pipeline §8).
The following are verified at the §3 design review and the §6 three-trip gate:

1. Tiles load via native `pmtiles://` (else swap the theme source to `mbtiles://`
   — a one-line theme-JSON edit; the ingestion scheme lives in config, not code).
2. The subtractive style renders as intended over real WA geometry.
3. `MLNMapSnapshotter` behaves driven from the recap render loop (threading).

## Reproduce a real frame locally (sim/device)

Not run in CI on purpose. To eyeball a MapLibre frame:

1. `./Tests/Fixtures/tiles/generate_tiles.sh` (Docker) — or reuse the committed
   fixture.
2. In a scratch/dev entry point, resolve a style and render one snapshot:
   ```swift
   let tiles = Bundle.main.url(forResource: "perth-2026-07-19", withExtension: "pmtiles")!
   let styleURL = try RecapMapStyle.resolvedStyleURL(styleResource: "functional-base", tilesURL: tiles)
   let provider = MapLibreSnapshotProvider(styleURL: styleURL)
   let snap = try await provider.snapshot(
       centerLat: -33.95, centerLon: 115.07, spanM: 1500, widthPx: 1080, heightPx: 1920)
   ```
   (For a device build, bundle the region `.pmtiles` or side-load via Files —
   `Docs/vector-tile-pipeline.md` §5.)
3. Confirm land/water/roads render and the projection lands the route on real
   roads. Capture the still for the §3 side-by-side pack.

## Attribution

© OpenStreetMap contributors (ODbL). Set on the theme source now; end-card /
about-screen surfacing lands with the §3 production switch-over (decisions.md
2026-07-21).
