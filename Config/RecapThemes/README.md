# Recap themes — MapLibre style JSON

A **theme** at the substrate level is a [MapLibre style JSON](https://maplibre.org/maplibre-style-spec/)
against the **OpenMapTiles** schema (Planetiler default source-layer names:
`water`, `waterway`, `landcover`, `transportation`, `place`, …). Themes are
**config, not code** (spec §0 rule 2) — iterate them without recompiling the app.

## Files

- `functional-base.json` — **Replay MVP §2 substrate.** Deliberately unstyled and
  subtractive: land + water + a quiet road skeleton, **no POI, no labels**. Its
  only job is to prove MapLibre frames render through `MapLibreSnapshotProvider`.
  **Not the shipping look.**
- `modern-minimal.json` — **§3, not yet built.** The one publishable MVP theme,
  authored during Modern Minimal and signed off by Chiu via a side-by-side design
  review. It supersedes `functional-base.json` in production; that switch-over is
  the PR where `MapKitSnapshotProvider` is retired.

## Tile-source sentinel

Each theme carries a sentinel tiles URL — `pmtiles://__KAMOME_TILES__`. The app
owns where the tiles actually live at runtime, so `RecapMapStyle` substitutes the
real on-disk path before handing the style to the snapshotter
(`App/Services/RecapMapStyle.swift`). Keep the sentinel in any hand-edited style,
or resolution throws.

The `pmtiles://` **scheme** lives in the JSON, not the code — so switching the
ingestion path (native `pmtiles://` vs. an `mbtiles://` fallback; see
`Docs/vector-tile-pipeline.md` §5) is a one-line theme edit, verified on device.

## Authoring workflow

1. Generate local tiles (see `Tests/Fixtures/tiles/README.md` for the fixture, or
   `Docs/vector-tile-pipeline.md` §4 for a full region).
2. Point [Maputnik](https://maputnik.github.io) at those tiles, edit, and commit
   the resulting JSON here.
3. Start from a deliberately empty style and **add** layers (subtractive by
   construction). If a layer's absence doesn't hurt the replay, it stays out.
4. Attribution `© OpenStreetMap contributors` on the source is **not optional**
   (ODbL). Its end-card / about-screen surfacing lands with the production
   switch-over (§3).
