# Handoff — Recap render-layers refactor (2026-07-24)

The recap OUTPUT / video-format redesign (CLAUDE.md "recap OUTPUT / video-format
redesign") became a **render-pipeline re-architecture** on Chiu's direction
(2026-07-24). Target: a TravelBoast/Relive-class animated map video — cute anime
hero car, dark souvenir night map, photos at stops — where **the same animation
timeline can render in any visual style** (TravelBoast / modern-minimal /
cinematic) without rewriting the story/timing logic.

Branch `phase-3-recap`. Foundation + Layers 1–2 committed at `c933121`. **Not
merged** — PR #11 holds until the §6 three-trip gate.

## The architecture (the one rule)

Story/timing and rendering couple **only** through style-independent value
types — the "narrow waist". Everything left of the waist is story (no pixels, no
style); everything right is rendering (no story, no timing). One-way dependency:

```
RecapTrip ─▶ LinearTimeline ─▶ { CameraFrame, SubjectState, MapState, OverlayContent }
                                          │  (the waist)
                                          ▼
          MapRenderer · SubjectRenderer · OverlayRenderer ─▶ frames
```

Renderers never see `RecapTrip` or the timeline. **Overlays never drive the
camera** — camera choreography (incl. the deck zoom) lives in the timeline's
camera stream, synchronized with overlay content by `LinearTimeline`.

## 1. What landed (committed `c933121`, 115 tests green, swiftlint --strict clean)

- **`RecapTrip` extraction** (`Core/ExportEngine/RecapTrip.swift`) — replaces
  `RecapComposer.Content`. Style-independent trip data: route coords, stops
  (coord/name/dayLabel/detail/**`[PhotoRef]`**/dwellS), title/subtitle/stats/CTA,
  **`shareURL`** (a string, not a rendered QR). `PhotoRef` is `.asset(id)` /
  `.file(url)` — the data layer points at images, never holds a `CGImage`.
- **4 state types** (the narrow waist, `RecapAnimationState.swift`), all
  `Equatable`, no bitmaps: `CameraFrame` (center/span/bearing; **no pitch** —
  Phase 4 with a `supportsPitch` capability), `SubjectState` (lat/lon/heading/
  emphasis/isVisible), `MapState` (opacity only — style id is a renderer concern),
  `OverlayContent` (`routeReveal` / `stopLabel` / `photoDeck` / `titleChrome` /
  `endChrome`).
- **Renderer protocols** (`RecapRenderers.swift`): `MapRenderer` (with
  `MapRendererCapabilities` + `FollowCamMode.resolve(requestHeadingUp:_:)` — the
  sole capability consumer, decides heading-up vs. a rotating marker),
  `SubjectRenderer`, `OverlayRenderer`, `RenderSurface` (carries a cross-fade-aware
  `project` closure + `cgPoint` helpers). `SpriteMode` = `.heroUpright` /
  `.topDownRotating`; `SubjectVisual` = `.sprite` / `.marker`.
- **`LinearTimeline`** (`LinearTimeline.swift`) — concrete struct (no
  SceneDirector/Scene/TimelineCompiler ceremony; one story shape). Produces the
  four streams `cameraFrame / subjectState / mapState / overlayContents(atTime:)`
  by **reusing `CameraPath`'s** speed-warp/hold/easing math. **Two-beat stop
  scene (approved by Chiu 2026-07-24):** label-lead (`deck_label_lead_s`, camera
  parked at follow span) → dolly-in (`deck_zoom_s`, span → `deck_span_m`) →
  hold+rotate (`n·deck_photo_hold_s`, one dot per photo, highlight leads) →
  dolly-out. Camera span and deck emphasis ride one shared 0…1 envelope. Timing
  verified in `LinearTimelineTests` (+ env-gated `testDumpStopTransition`,
  `KAMOME_TIMELINE_DUMP=1`).
- **§4/§5 visual work** (Chiu-reviewed, in the same commit): top-down vector car
  marker (rotates to heading, swappable), anime raster car sprite via a
  `markerImage` token (heading-up hero pose), gull ported from the prototype,
  photo-deck scale envelope. Stills harnesses `RecapMarkerDeckStillsTests`
  (flat) + `RecapFollowCamStillsTests` (real MapLibre, env-gated).
- **Layers 1–2 compositor migration (pixel-identical, golden frames verified):**
  - Layer 1 `MapRenderer`: `RecapSnapshotProviding` → `MapRenderer`; providers
    declare `capabilities` (MapKit `supportsBearing:false`; MapLibre/Flat `true`)
    and render a `CameraFrame` + `MapState`.
  - Layer 2 `SubjectRenderer`: marker drawing moved into `SpriteSubjectRenderer`;
    the compositor supplies `SubjectState`+`CameraFrame`, owns no screen transform.

## 2. What's next — Layer 3 + wiring (the visual-changing chunk)

This is **not** byte-identical — it lands the approved new visuals. It ends with
a **MapLibre stills render for Chiu's sign-off**, not golden-frame gates.

- **`RecapOverlayRenderer`** (concrete `OverlayRenderer`) consuming
  `OverlayContent`: `routeReveal` (glow trail — port the route stroke),
  **`stopLabel`** (pin + name — NEW drawing, the two-beat lead), `photoDeck`
  (port the deck bloom, now driven by `RecapPhotoDeck.emphasis`/`focusIndex`),
  `titleChrome`, `endChrome` (generate the QR from `shareURL` via `RecapQRCode`).
- **`PhotoRef` resolver** — `PhotoRef` → `CGImage` at draw size. App-provided
  (PhotoKit, moved out of `RecapModel.loadDeckImages`); a synthetic **test stub**
  for deterministic CI.
- **New `FrameCompositor`** consuming `LinearTimeline` + the three renderers; the
  render loop pulls the four state streams per frame (apply the timeline's
  `cameraFrame` — incl. the stop dolly — when fetching snapshots).
- **Retire** the old `OverlayTimeline` / `OverlayEvent` / `RecapCardDrawing` /
  the old single-beat deck; delete the `RecapModel` bridge (it currently maps
  `RecapTrip` back into today's compositor inputs + resolves refs→bitmaps).
- **Rewrite the golden tests** to construct via `LinearTimeline` + renderers +
  the test resolver. Marker/route/chrome frames stay assertable; the stop frames
  are new (two-beat) behavior.
- Then render fresh **MapLibre follow-cam stills** (anime car + two-beat deck over
  the dark souvenir map) for Chiu to sign off.

Suggested order: `RecapOverlayRenderer` + resolver → new `FrameCompositor` +
loop → `RecapModel` switch + bridge deletion → retire old overlay code → rewrite
tests → stills.

## 3. Key constraints (do not violate)

- **MapKit still ships** until the switch-over. Do not flip production to MapLibre
  / `follow_heading_up=true` until Chiu signs off the Layer-3 look (the heading-up
  anime car needs MapLibre — that IS the switch-over, un-held by Chiu 2026-07-24).
- **PR #11 holds** — nothing merges to `main` until the §6 three-real-trip gate.
- **All durations are config tunables** (`Config/TrackingConfig.json` + typed
  mirror + `ConfigLoaderTests`): `deck_photo_hold_s` 0.8, `deck_zoom_s` 0.5,
  `deck_span_m` 600, `deck_label_lead_s` 0.6. No magic numbers (spec §0).
- **Overlays never drive the camera.** Any camera move is a `LinearTimeline`
  camera-stream concern, synchronized with the overlay content.
- Renderer/SDK confinement holds: `import MapLibre` only in
  `MapLibreSnapshotProvider.swift`; `import MapKit` only in
  `MapKitSnapshotProvider.swift`; PhotoKit only in the app layer.
- Golden-frame CI stays deterministic (`FlatSnapshotProvider`, no Metal/network);
  the real look is judged on env-gated MapLibre stills + the §6 device gate.
