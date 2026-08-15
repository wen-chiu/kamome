# §3 Modern Minimal — design review harness (needs Chiu + a real render)

Modern Minimal is the **one** MVP theme (spec §4.5; handoff-P3.5 §3). Its
acceptance is **not** a test — it is a **side-by-side design review that Chiu
signs off** (vector-tile-pipeline §1 quality bar). This folder is the review
setup. The theme itself cannot be self-certified: the actual look is a Metal
render that is not produced in this repo's CI.

## Status

- `Config/RecapThemes/modern-minimal.json` — **DRAFT v2, NOT signed off.**
  **v1 (pale "desaturated OSM") was rejected by Chiu 2026-07-22** — it read as an
  engineering map with the contrast turned down. v2 is a **dark atmospheric
  souvenir map** matching the validated prototype + WIP demo
  (`Docs/prototype`, artifact "Kamome Recap 冰島環島"): dark-navy sea, dark-slate
  land, a **glowing teal coastline**, pale ice, water bodies with glowing rims,
  no roads/POI/labels (only a faint major-road whisper). Rendered in-sim.
- **This is the base map only.** ~Half the crafted feeling — **vignette, route
  glow, marker glow, vertical grade** — is a *compositor* job (`RecapTheme`
  tokens in `RecapFrameCompositor`), not this style, and is the **next** step.
- **MapKit is still the shipping base map.** `RecapModel` is untouched. Nothing
  switches to MapLibre until this review passes.

## What Chiu judges (the quality bar — vector-tile-pipeline §1)

Render Modern Minimal stills and place them **beside the P3 Apple-tiles stills**
(`Docs/demos/phase3/still-title-card.png`, `still-stop-card.png`,
`still-end-card.png`) at matched camera positions, plus two mid-drive frames.
A passing style has:

1. **Zero business-POI noise** — no shop pins, no commercial labels.
2. **Deliberate empty space** — subtractive; only what serves the journey.
3. **Distinctive road/route treatment** — roads are a quiet substrate; the
   traveled route (a compositor overlay, not in this style) is unmistakably hero.
4. **Recognizable Kamome identity** — branding stripped, still recognizably not a
   navigation app.

Priorities, in order (vision doc): **beauty → clarity → smooth animation →
geographical accuracy → delightful details.** If, after honest iteration, the bar
looks unreachable, **do not lower it — reopen the substrate ADR** (decisions.md
2026-07-19).

## How to check it (one command)

A render harness is wired up — `Tests/AppTests/ModernMinimalRenderTests.swift`.
It drives the **real** MapLibre snapshotter (Metal) over the committed fixture
tiles and writes PNG stills you open by eye. Env-gated so it never runs in CI
(non-deterministic Metal; golden-frame discipline, vector-tile-pipeline §8).

```bash
KAMOME_RENDER_STILLS=1 xcodebuild -scheme Kamome test \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:KamomeTests/ModernMinimalRenderTests \
  TEST_RUNNER_KAMOME_RENDER_STILLS=1
```

The console prints the output dir; open `modern-minimal-*.png` (and the
`functional-base-*` pair). Override the location with
`TEST_RUNNER_KAMOME_RENDER_OUT=/some/dir`. On a **device**, bundle a region
`.pmtiles` (or side-load via Files) — see vector-tile-pipeline §5.

## First-look stills (committed, 2026-07-22 — DRAFT v2 dark souvenir)

Rendered in-sim from the committed Margaret River fixture crop:

- `modern-minimal-{town-close,town-mid,coast-wide}.png` — the dark souvenir draft.
- `functional-base-{town-close,town-mid,coast-wide}.png` — the §2 substrate.

Known refinement knobs (not yet tuned; awaiting Chiu's read of the direction):
coastline glow width/opacity; hiding tiny water polygons (WA farm dams make the
mid frame spotty — Iceland/coastal trips are cleaner); the landcover tint;
whether the faint road whisper stays. The land looks flat because the **vertical
grade + vignette are the compositor's job** (next step), not the base style.

These are a **first look**, not the matched-position side-by-side: they sit over
the small fixture area (Margaret River coast), not the P3 stills' camera
positions. For the true matched review, generate **region-wide** WA tiles (widen
`$BOUNDS` in `Tests/Fixtures/tiles/generate_tiles.sh`) and render at the P3 card
moments beside `Docs/demos/phase3/still-*.png`.

## Findings from the in-sim render (2026-07-22)

- ✅ **The substrate renders.** MapLibre 6.27.0 loads the pmtiles and applies the
  style in the simulator. Tiles load via `pmtiles://file:///…` — a bare
  `pmtiles:///path` throws "unsupported URL" (`RecapMapStyle` now injects the file
  URL; recorded in decisions.md 2026-07-22 / vector-tile-pipeline §5).
- ⚠️ **MapLibre bakes its own wordmark + attribution into the snapshot** (a
  "MapLibre" logo bottom-left, "© OpenMapTiles © OpenStreetMap contributors"
  bottom-right). Good for the ODbL credit, but the wordmark is not wanted in the
  final recap. **§3 sign-off item:** decide whether the compositor covers the
  corners or the snapshotter ornaments are suppressed, and place the OSM/OMT
  attribution deliberately (end card).

## Follow-ups gated on sign-off (all land in the switch-over PR)

Do **not** do these before Chiu approves the look — they are driven by what the
review reveals (ADR 2026-07-19: theme tokens come "from what the theme actually
needs"):

- **Sparse place labels + glyphs** — city/town only (never streets/POIs). Needs
  the glyph pipeline: bundle small Latin ranges + `localIdeographFontFamily` for
  zh-Hant, verified on the Taiwan fixture (vector-tile-pipeline §6). Deliberately
  absent from the draft.
- **Overlay `RecapStyle.modernMinimal` preset** — route casing/color, marker,
  card chrome tuned to sit on this base map (`RecapFrameCompositor.RecapStyle`).
  Golden-frame-safe: add a preset; the P3 default stays the test baseline.
- **Production switch** — `RecapModel` builds `MapLibreSnapshotProvider`;
  **`MapKitSnapshotProvider` is retired in that same PR** (handoff-P3.5 §2.4).
- **OSM attribution** on the end card / about screen — now that OSM tiles reach
  users (decisions.md 2026-07-21).

This review keeps the substrate honest; it does **not** replace the §6 three-trip
release gate (a "prettier map" is necessary, not sufficient — pipeline §1).
