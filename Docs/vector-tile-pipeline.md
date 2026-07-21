# Vector-tile pipeline — recap base maps (Phase 3.5 = Replay MVP)

**Status:** authoritative implementer guide for the MapLibre substrate
(spec v1.7 §4.5 / §7 Phase 3.5 = Replay MVP; ADR `Docs/decisions.md`
2026-07-19). This is Replay MVP work order §2 (`Docs/handoff-P3.5.md`).
Written to be executable by a fresh implementer with no other context.
Read `Docs/kamome-animation-vision.md` first — it is the "why" behind
every choice here.

---

## 1. Why this exists (and when to abandon it)

The recap's base map must be fully Kamome-controlled: colors, typography,
road treatment, and above all **what is omitted**. Apple's
`MKMapSnapshotter` has no styling API, so the recap renders MapLibre
Native over self-hosted vector tiles with a Kamome-authored style sheet.

**Quality bar (the go/no-go for this whole pipeline):** the themed output
must be *clearly better-designed than native Apple Maps for journey
replay*. Concretely, a passing style sheet has:

1. **Zero business-POI noise.** No shop pins, no restaurant icons, no
   commercial labels. The P3 artifact failed here first.
2. **Deliberate empty space.** Subtractive cartography — land, water,
   terrain tint, major road skeleton, and the journey. If a feature does
   not serve the story of the trip, it is not drawn.
3. **Distinctive road/route treatment.** Roads are a quiet substrate; the
   traveled route is unmistakably the hero. Nobody should confuse a frame
   with a navigation app.
4. **Recognizable identity.** With every logo and card removed, a viewer
   who has seen one Kamome replay should recognize the next one (spec §0
   rule 6).

**Judging procedure:** render stills at the camera positions of the three
P3 reference stills (`Docs/demos/phase3/still-*.png` — title card, stop
card, end card) plus two mid-drive frames, and present them side-by-side
with the P3 Apple-tiles versions. Chiu reviews and signs off. **This is a
design review, not the Replay MVP release gate** (2026-07-20): it keeps the
substrate honest, but the release gate is the full-video judgment across three
real trips (spec §4.5 / §10) — "prettier map" is necessary, not sufficient. A
style that fails side-by-side is still not shippable. If after honest iteration
the bar looks unreachable, do not lower the bar — reopen the substrate ADR.

---

## 2. Architecture at a glance

Two halves; only the second ships in the app:

```
OFFLINE (developer machine, one-time per region/data refresh)
  Geofabrik .osm.pbf ──► Planetiler ──► region.pmtiles (single file)
                                          + style JSON (per theme)
                                          + sprites / glyph strategy

APP RUNTIME (iOS)
  region tiles + theme style ──► MapLibre Native snapshotter
        ──► MapLibreSnapshotProvider (: RecapSnapshotProviding)
        ──► existing recap pipeline (compositor → encoders), unchanged
```

Tile generation is a documented offline step, **not runtime
infrastructure** — no tile server runs anywhere in production. This is
the same self-hosting posture as OSRM (§4.4): regional extracts,
developer-run tooling, deterministic artifacts.

## 3. Data source

- **OpenStreetMap regional extracts from Geofabrik** (`download.geofabrik.de`):
  `taiwan-latest.osm.pbf` (≈ 100 MB) and `australia-latest.osm.pbf`
  (≈ 1 GB). Same regions, and ideally the same downloaded snapshot files,
  as the OSRM setup in `Docs/osrm-setup.md` — one data vintage for
  matching and rendering keeps the matched route and the drawn roads
  consistent.
- Pin the extract date in the artifact filename
  (e.g. `taiwan-2026-07-01.pmtiles`) and record it in this doc's
  changelog section when regenerated. Never "latest" in CI.
- License: OSM data is ODbL — the recap's end card / app about screen
  must carry "© OpenStreetMap contributors". Add this attribution when
  the substrate lands; it is not optional.

## 4. Tile generation — Planetiler → PMTiles

**Planetiler** (github.com/onthegomap/planetiler, Java 21+, single JAR)
generates a full basemap in the **OpenMapTiles layer schema** from a
`.osm.pbf` in minutes on a laptop. **PMTiles** (protomaps.com/docs/pmtiles)
is a single-file tile archive readable by HTTP range requests or straight
off local disk — no server.

```bash
# one-time per region; output committed to a data location, not the repo
java -Xmx4g -jar planetiler.jar \
  --osm-path=taiwan-2026-07-01.osm.pbf \
  --output=taiwan-2026-07-01.pmtiles \
  --bounds=119.0,21.7,122.1,25.4        # Taiwan; omit for full extract

java -Xmx16g -jar planetiler.jar \
  --osm-path=australia-2026-07-01.osm.pbf \
  --output=australia-2026-07-01.pmtiles
```

Notes for the implementer:
- Default profile = OpenMapTiles schema. **Use it.** Every style JSON in
  this project assumes OpenMapTiles source-layer names (`transportation`,
  `water`, `landcover`, `place`, …). Custom profiles are icebox.
- Max zoom: recap cameras sit at `export.camera_span_m` (city-to-regional
  scale). Generate to z14 (Planetiler default) — more than enough; do not
  chase z15+ detail we never render.
- Large `.pmtiles` files do **not** go into git. CI fixtures (see §8) use
  a tiny cropped extract that does.

## 5. Hosting & distribution

- **Development / simulator:** read the `.pmtiles` from local disk, or
  serve the directory with any static file server. Nothing bespoke.
- **Device builds (P3.5):** bundle the trip region's `.pmtiles` with the
  build or side-load via Files during device testing. Taiwan-sized files
  bundle comfortably; Australia does not — device tests there use a
  state-level extract (e.g. `western-australia` from Geofabrik).
- **Post-POC:** `.pmtiles` on any static host/CDN (range requests) with
  on-demand region download. Design nothing for this now (spec §0 rule 1
  — Phase 7 territory).

**MapLibre ingestion — verify at implementation time, in this order:**
1. Native `pmtiles://` URL support in the current MapLibre Native iOS
   release (landed upstream in the v6 line; confirm it is in the release
   you pin, on iOS specifically).
2. Fallback A: convert to MBTiles (`pmtiles convert` from the protomaps
   CLI) and use MapLibre Native's `mbtiles://` file source.
3. Fallback B: a trivial in-app localhost range-request handler in the
   dev harness only.
Record which path was taken in `Docs/decisions.md` when the provider PR
lands. Do not build Fallback B for production.

## 6. Style-sheet authoring (theme = MapLibre style JSON)

A **theme** at the substrate level is a MapLibre style JSON (MapLibre
Style Spec) against the OpenMapTiles schema. First theme: **Modern
Minimal** (`Config/RecapThemes/modern-minimal.json` — create the folder;
themes are config, not code, per spec §0 rule 2).

Authoring workflow:
- Edit in **Maputnik** (maputnik.github.io — web editor for the MapLibre
  style spec) pointed at the local tiles; commit the resulting JSON.
  Style iteration must never require recompiling the app.
- Start from a deliberately empty style and **add** layers (subtractive
  by construction), rather than deleting from a busy open-source style.
  Layer budget discipline: if a layer's absence doesn't hurt the replay,
  it stays out.
- Modern Minimal direction (from the vision doc): Apple-like restraint —
  desaturated terrain palette, one accent (the route), simplified road
  hierarchy (motorway/trunk/primary rendered; residential only at close
  spans), sparse place labels (city/town names only, never street names,
  never POIs), subtle water/land contrast, soft shadows if any.
- **Typography / CJK:** label rendering needs glyphs. Do not self-host
  multi-hundred-MB CJK glyph PBFs: set MapLibre's
  `localIdeographFontFamily` so zh-Hant labels render via the system
  font, and bundle small Latin glyph ranges only (generate with
  maplibre/font-maker if a custom face is wanted). Verify zh-Hant place
  names render on the Taiwan fixture before calling the theme done.
- Sprites: Modern Minimal should need few or none (no POI icons by
  design). If any are added, the sprite sheet is part of the theme
  artifact and checked in.

**Boundary reminder:** route line, seagull/vehicle marker, stop cards,
title/end cards are **not** in the style JSON — they are compositor
overlays (`RecapFrameCompositor`), so they animate per-frame and work
over every provider including `FlatSnapshotProvider`. When Modern Minimal
lands, its overlay colors/weights get extracted into a `RecapTheme`
token value (defined then, from real needs — ADR 2026-07-19; no
speculative theme interface before that).

## 7. iOS integration

- Dependency: **MapLibre Native iOS** via SPM
  (`maplibre/maplibre-gl-native-distribution`), added in `project.yml`
  (the `.xcodeproj` is generated — never hand-edit it).
- Rendering: MapLibre's snapshotter (`MLNMapSnapshotter` — same shape as
  `MKMapSnapshotter`: options in → image + coordinate→point conversion
  out). Wrap it in `MapLibreSnapshotProvider: RecapSnapshotProviding` in
  `Core/ExportEngine/MapLibreSnapshotProvider.swift`.
- **The provider file is the only file in the codebase that may
  `import MapLibre`.** This mirrors today's discipline (`import MapKit`
  exists only in `MapKitSnapshotProvider.swift` — audited 2026-07-19).
  Consider a CI grep gate. The `MapSnapshot` contract (CGImage + the
  producer's own projection closure) is unchanged — the snapshotter's
  conversion function becomes the closure, exactly like the MapKit
  provider does it.
- Camera attitude (pitch/bearing for the isometric look) is **not** in
  the current protocol. When the isometric camera lands, extend the
  snapshot request additively; do not pre-build it.
- Snapshot prefetch, keyframe cadence (`export.keyframe_interval_frames`)
  and the render budget (< 90 s on device) all still apply — measure via
  the S5 render-time readout, same as P3.

## 8. Determinism & CI

The move to self-hosted tiles makes golden-frame testing *stronger*:
- CI fixture: a tiny cropped `.pmtiles` (Perth fixture corridor) + the
  checked-in theme JSON → **bit-stable rendering**; golden-frame hashes
  can be exact, no live-tile tolerance.
- Keep `FlatSnapshotProvider` for pure pipeline tests — fast, no tile
  dependency, and it doubles as the route-only "theme" for the
  theme-swap gate demo.
- Add one golden test per theme at the three reference camera positions
  (§1 judging set) so style regressions are caught mechanically after
  Chiu's one-time sign-off.

## 9. Deliverables checklist (Phase 3.5, substrate portion)

- [ ] `Docs/osrm-setup.md` OSRM matching running first (§4.4) — visuals
      wait until routes are road-true.
- [ ] Planetiler runs documented + regional `.pmtiles` generated (TW +
      WA), extract dates pinned.
- [ ] MapLibre SPM dependency in `project.yml`; ingestion path (§5
      verify list) decided and recorded in decisions.md.
- [ ] `MapLibreSnapshotProvider` conforming to `RecapSnapshotProviding`;
      `import MapLibre` confined to that file (grep gate).
- [ ] `Config/RecapThemes/modern-minimal.json` + Maputnik workflow note.
- [ ] zh-Hant labels verified on Taiwan fixture
      (`localIdeographFontFamily`).
- [ ] OSM attribution ("© OpenStreetMap contributors") in end card /
      about screen.
- [ ] CI: cropped fixture tiles checked in, golden frames exact-hash.
- [ ] Side-by-side quality-bar review pack rendered (§1) → Chiu sign-off.
- [ ] Render budget re-measured on device via S5 readout (< 90 s).

## Changelog

- 2026-07-19 — initial version (with substrate ADR, decisions.md).
