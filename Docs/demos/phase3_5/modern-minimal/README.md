# §3 Modern Minimal — design review harness (needs Chiu + a real render)

Modern Minimal is the **one** MVP theme (spec §4.5; handoff-P3.5 §3). Its
acceptance is **not** a test — it is a **side-by-side design review that Chiu
signs off** (vector-tile-pipeline §1 quality bar). This folder is the review
setup. The theme itself cannot be self-certified: the actual look is a Metal
render that is not produced in this repo's CI.

## Status

- `Config/RecapThemes/modern-minimal.json` — **DRAFT, NOT signed off.** Authored
  from `Docs/kamome-animation-vision.md` without a live render. A starting point
  for iteration, not the finished look.
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

## How to render (sim/device — Metal)

Not run in CI on purpose (non-deterministic Metal; golden-frame discipline,
vector-tile-pipeline §8). From a scratch/dev entry point:

```swift
// Quick local check uses the committed Margaret River fixture crop.
// For the FULL side-by-side at the P3 camera positions, generate region-wide
// WA tiles first (widen $BOUNDS in Tests/Fixtures/tiles/generate_tiles.sh).
let tiles = Bundle.main.url(forResource: "perth-2026-07-19", withExtension: "pmtiles")!
let styleURL = try RecapMapStyle.resolvedStyleURL(styleResource: "modern-minimal", tilesURL: tiles)
let provider = MapLibreSnapshotProvider(styleURL: styleURL)

// Representative camera inside the fixture crop (span matches export.camera_span_m):
let frame = try await provider.snapshot(
    centerLat: -33.955, centerLon: 115.075, spanM: 1500, widthPx: 1080, heightPx: 1920)
// Save frame.image beside the P3 still for the same kind of moment.
```

Suggested review set: the three P3 card moments + two mid-drive frames = five
side-by-side pairs. Drop the rendered PNGs in this folder as `mm-*.png` next to a
short note, and post the pairs for Chiu.

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
