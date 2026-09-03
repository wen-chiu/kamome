# Handoff — Recap Layer 3 + visual redesign (2026-07-25)

> **Historical phase record.** PR #11 **merged to `main` 2026-08-15**
> (`Docs/decisions.md` 2026-08-15) — the "not merged / holds until §6" line
> below is of its era. One section stays load-bearing: **§3 vehicle-sprite
> constraints**, cited by `Core/ExportEngine/Resources/Vehicles/README.md` and
> `HANDOFF.md` (Phase 4 sprite work). Everything else is history; current state
> is `Docs/current-state.md`.

Branch `phase-3-recap`, commits `ce28db6` (Layer 3 + redesign), `2917008` (final
car art) and `f294883` (static camera + MapLibre switch + theme atmosphere).
131 tests green, `swiftlint --strict` clean. **Not merged — PR #11 holds until
the §6 three-real-trip gate.**

**This closes the recap-visuals phase.** Nothing in the pipeline is waiting on a
design decision; what remains before PR #11 is device validation (§7). Read §0
first if you are picking this up cold — the camera model reverses what earlier
sections of this document and `handoff-P3.5.md` describe.

## 0. The camera is static — read this before the rest

The final and largest reversal of the session (Chiu 2026-07-25). Sections 1–6
below describe a camera that flew: a wide establishing shot, a close follow-cam
riding the vehicle, and a dolly into every stop. **All of that is gone.**

- **One fixed frame per act.** The map does not move and does not zoom. A still
  frame is what makes the distance covered legible — the drawn line grows against
  a backdrop the eye can measure — which a continuously sliding, scaling
  follow-cam destroyed. This restores the web prototype's model, and TravelBoast's.
- **The route draws itself** progressively down that fixed map while the car
  moves along it. That is the whole animation now.
- **Re-framing happens only across a genuine jump**: consecutive route points more
  than `export.act_split_km` (25 km) apart, which is what a flight, a ferry, or a
  drive resuming in another region looks like in the data. Act changes ease rather
  than cut. A continuous trip is a single act — one frame for the whole film.
- **`deck_span_m` is gone** with the stop dolly. `act_split_km` replaces it.
- **The GPS-noise problem resolved itself.** Raw wobble was only ever visible
  because the close zoom magnified it; at a fixed whole-trip frame it sits at its
  true, negligible scale. That is a *consequence* of the change, not its reason —
  do not "fix" it by zooming back in.

Implementation: `CameraPath.cameraFrame` plus `CameraPathActs.swift` (the act
split and per-act framing, kept in its own file for readability). `LinearTimeline`
passes the frame straight through; nothing modulates it — not the stop, not the
deck.

**Layer 3 is fully landed, visuals included** — Chiu signed off the car sprites,
the photo-deck zoom-in reveal, and the two-beat stop label on 2026-07-25. The
render-layers refactor that began at `c933121` is complete: nothing in the recap
pipeline is still waiting on a design decision. What remains before PR #11 is
device validation, not visual work — see §7.

Continues `Docs/handoff-render-layers.md` (Layers 1–2, `c933121`). That document
describes the architecture; this one records Layer 3 and the visual decisions
Chiu made on top of it, several of which reverse earlier ones.

## 1. Layer 3 is wired — the render-layers refactor is complete

`RecapTrip → LinearTimeline → { CameraFrame, SubjectState, MapState,
OverlayContent } → three renderers` now runs end to end.

- **`FrameCompositor`** (new) consumes the timeline + the three renderers. The
  render loop pulls the four streams per frame and takes snapshots at the
  timeline's own `cameraFrame` (see §0 — that frame is now static). Z-order
  (trail under the subject, label/deck/chrome over it) is a rendering decision
  and lives here, not on `OverlayContent`.
- **`PhotoLibraryPhotoResolver`** (app) resolves `PhotoRef` → `CGImage`. PhotoKit
  stays in the app layer; the resolver warms a cache off the render thread
  because the overlay renderer resolves synchronously per frame.
- **`RecapModel`** builds the timeline + renderers directly. The old bridge
  (mapping `RecapTrip` back into the previous compositor's inputs, resolving
  refs to bitmaps up front) is deleted.
- **Retired:** `RecapFrameCompositor`, `OverlayTimeline` / `OverlayEvent`,
  `RecapCardDrawing`, the single-beat deck. Golden-frame tests were rewritten
  against the new pipeline rather than patched.

## 2. North-up map — heading-up abandoned (Chiu 2026-07-25)

**The map never rotates to follow the vehicle.** A turning map obscures the
route's real shape and the distance covered, which is the whole point of a travel
recap. Fixed map, moving/turning vehicle — the model the web prototype used.

This *reverses* an earlier decision in the same session, which had briefly made
heading-up the shipping mode. Consequences:

- `export.follow_heading_up` stays `false`. `CameraPath` still supports it, but
  nothing turns it on.
- **`FollowCamMode` is deleted.** Its only job was choosing between the two
  orientations; with the choice settled, `resolve` would have ignored its
  arguments and returned a constant. The capability guard survives inline in
  `RecapModel` (`followHeadingUp && provider.capabilities.supportsHeadingUp`), so
  a renderer that cannot rotate still cannot be handed a bearing if the flag is
  ever flipped.
- **The MapKit/MapLibre distinction no longer affects the subject.** The car
  renders identically on both, so the base-map switch-over is now purely a map
  change. The vector gull is only a missing-asset fallback.

## 3. Car = 8-direction sprite set, not one rotatable image

Two approaches were tried and rejected before this one:

1. **Code-drawn vector car** (`RecapCarSilhouette`, ~60° perspective with
   gradient shading, panel seams, rim light). Rejected: the quality ceiling for
   CoreGraphics path art is too low. The whole `VehicleSilhouette` protocol went
   with it.
2. **Single rotatable raster sprite** with a fixed art-angle correction.
   Rejected: a 3/4 drawing only reads correctly at the angle it was drawn;
   rotating it breaks the perspective at every intermediate angle.

**Current design** — the classic isometric-game technique:

- `SpriteDirection` — eight cases, raw values are the asset filename suffixes
  (`n`, `ne`, `e`, `se`, `s`, `sw`, `w`, `nw`).
- `SpriteDirection.nearest(toBearing:)` rounds to 45° and wraps at 360°. No
  interpolation, no `context.rotate` anywhere in the subject path.
- `RecapCarSprite.set` loads all eight from `Core/ExportEngine/Resources/`,
  cached; returns nil if *any* is missing, so a partial set never renders.
- `SubjectVisual.rasterSprite([SpriteDirection: CGImage])`.

### Final art landed 2026-07-25

Chiu's eight drawings replaced the placeholders — a pure asset swap, no code
change, as designed. Each is 512×512 with a transparent background: N is a rear
view (driving away), E/W are profiles with the nose right/left, S is head-on, and
the diagonals sit between.

Sizing note: the car fills 52–74% of the canvas depending on direction, and the
drawings are centred to within ~±35 px of the canvas centre. Scaling is by
**canvas**, not by content bounds — that is deliberate, and the reason the car
does not pulse as it turns. The size variation between a rear view and a profile
is physically correct.

## 4. Stop scene — zoom-in reveal + two beats

**Photo deck is a reveal, not a bloom.** The card opens from
`deckPhotoMinWidthFraction` (0.30) to `deckPhotoMaxWidthFraction` (0.50) of frame
width, so the map and trail stay visible around it. `RecapPhotoDeck` carries
`reveal` (0…1, the renderer maps it onto its own size range) and `opacity`.

**The card's scale envelope was deliberately kept separate from the camera.**
That mattered when a dolly existed; since §0 the camera does not move at all, so
the reveal is now purely an overlay concern — which is exactly why it survived
the camera change untouched. `LinearTimelineTests` still asserts the card opens
across the hold *and* that the map span does not budge while it does.

**Two beats.** Beat 1: the pin **and** its name pill float as a group above the
vehicle, cleared by the subject's half-length plus `labelVehicleClearancePx`
(50 px at the 1080 reference) so neither ever prints over the car. Beat 2: that
label cross-fades out as the card takes over the stop's identity, redrawn beneath
the photo. An early version anchored the pin at the map coordinate and printed it
on the car's roof — the group floats precisely to avoid that.

## 5. Tests worth knowing about

- `RecapSubjectOrientationTests` — bucket boundaries (337° → nw, 338° → n),
  compass wrap (−45°, 405°, 720°), all eight sprites sharing one canvas size (so
  the car cannot pulse as it turns), same-bucket headings rendering
  pixel-identically, and **north-up keeps the map fixed**: an eastbound trail
  lies to the *left* of the car, not below it.
- Vehicle pixel probes assert the *hue* (red-dominant) over a region, never an
  exact tone — the sprite's centre is windshield glass, and exact-pixel probes
  turned every art tweak into a false failure.
- The MapLibre stills harness (`RecapFollowCamStillsTests`, env-gated) renders
  the sweep through the **real pipeline**: it flies a route that genuinely turns
  through each heading and grabs the frame where the vehicle travels that way. An
  earlier version faked it — pinned an arbitrary bearing onto a fixed camera and
  drew a trail that did not end at the car — and produced a convincing-looking
  but meaningless image. If the sweep ever needs changing, keep it on the real
  pipeline.

## 6. Carried forward from this work

- Car art is **done** (2026-07-25). The glow and residual-tilt caveats from the
  single-sprite era died with it; the new drawings have clean transparent edges
  and each faces its own bearing.
- **Known, accepted, not blocking (Chiu 2026-07-25):** scaling by canvas rather
  than by content bounds leaves the car up to ~26 px (at the 1080 reference) off
  the true vehicle point on `sw`/`nw`, where the artwork sits furthest from its
  canvas centre. Invisible in stills. **Revisit only if it shows in rendered
  video**, via per-sprite content-centre correction at load — the canvas scaling
  itself must stay, or the car pulses as it turns.

## 7. Base map, theme atmosphere, and stop layout (`f294883`)

### The MapLibre switch is conditional, on purpose

`RecapModel` renders MapLibre when vector tiles for the region are present and
MapKit otherwise (`RecapMapTiles`, searching `KAMOME_TILES_PATH` → Application
Support → the app bundle). A `.pmtiles` file covers a bounded region and there is
no planet-sized file to bundle; serving tiles for wherever someone actually
travelled is the P7 backend problem. A hard retirement of MapKit today would
render blank frames for any trip outside a shipped region.

**No tiles ship yet**, so devices still render Apple's map. The demo film used a
20 MB corridor build generated locally (`Tests/Fixtures/tiles/generate_tiles.sh`
with widened bounds); that artifact stays out of git.

### Theme atmosphere — and a correction worth knowing

`RecapStyle` gained grade, vignette and route-glow tokens, applied by
`FrameCompositor` over the finished frame, plus a `modernMinimal` preset that is
now what the app renders. All tokens default to off so the deterministic
golden-frame gates do not move.

**The glow in every still reviewed before this commit was not real.** It came
from a `glowRouteStyle()` helper that existed only in the stills harness;
production was drawing the flat blue polyline the whole time. The preset is what
finally makes the shipped pipeline match what was signed off.

### Coastline: partially done, the rest unscoped

The Modern Minimal style already carried coastline layers, but tuned for close
zoom — 0.6 px strokes that vanished at the far zoom a fixed frame now sits at.
Retuned for z4–10, which is why the coast reads as a drawn outline.

**That is emphasis on tile data we already have, not the terrain-outline feature.**
Full island/region outline rendering (draw the whole of Iceland, or the region
around an inland route) remains **unscoped future work** and is two problems, not
one: a **geometry source** — tiles only give coastline where the extract covers,
so an island needs the whole island in the build or a separate simplified
coastline dataset — and **framing**, since "draw the whole island" means framing
the island rather than the trip, a different decision from what acts make today.
Chiu will scope it separately; do not start it opportunistically.

### Stop layout — the static camera's fallout

While the camera dollied into each stop the vehicle was guaranteed centred, so a
frame-centred card could never collide with it. With the camera static the
vehicle is wherever it really is, and the stop name printed across the car.

`RecapStopLayout` (pure geometry, no drawing) places the card tracking the
vehicle horizontally and clamped into the frame, then puts the name band on
whichever side of the card faces *away* from the vehicle.

**The rule is deliberately split, and this is the part to preserve:** the card
**may** cover the car — it is opaque, it is the subject of the beat, and a card
half the frame tall plus its caption cannot always clear a mid-frame vehicle in
1920 px. The **name band may not** — text across the car is what looked broken.
An earlier attempt at one blanket "nothing overlaps the vehicle" rule was proved
impossible by the test sweep before it ever reached a render.

`RecapStopLayoutTests` sweeps **121 anchor positions** across the frame and
asserts the invariants directly — name band never covers the vehicle, card and
band both stay in frame, the band always lands on the card's far side, the card
flips above/below correctly, edges clamp inward. The same layout also fixed the
beat-1 label, which could previously run off-frame entirely for the same reason.

Several *tests* carried the old assumption too (probing the frame centre for the
card); they now assert which photo is on screen rather than sampling a fixed
point, which is what they were actually checking.

## 8. What is left before PR #11 can go up

Nothing in this document blocks. The remaining work is **device validation plus
two deferred rendering decisions**, in rough dependency order.

### Code work still outstanding

1. **Tile provisioning** — the one thing standing between the app and the
   souvenir map on a real device. Needs a decision on how a region reaches the
   phone (bundled for the dogfood regions, downloaded, or served — P7). Until
   then `RecapMapTiles` finds nothing and MapKit renders.
2. **Labels / glyphs** in the map style — the last piece deferred from the §3
   sign-off that this session did not pick up.
3. **Terrain outline** (§7) — unscoped, Chiu's call, do not start unprompted.

### Device validation (needs a real iPhone — none of it can be faked)

From `Docs/device-test-P3.md`, the items redistributed to the Replay MVP gate:

- **F — render budget:** export the longest real trip on device, record the S5
  readout. The `< 90 s` number is retired; the criterion is *product-acceptable*.
- **G — S5 UX pass:** S3 → film button → sheet, photos toggle on/off, MP4 and
  GIF through the share sheet, cancel mid-render.
- **Limited Photo Library path** — still unproven on device (flagged since §1;
  the simulator's photo-grant is broken on iOS 26, see the toolchain note).
- **MapLibre pixel render + `pmtiles://` vs `mbtiles://`** — Metal, so CI has
  never executed it. Folds into the switch above.

### The gate itself (`Docs/handoff-P3.5.md` §6)

Three of Chiu's real past trips, of different character, each run **entirely
in-app**: photos import → matching → recap → MP4 → share. No DB edits, no
external tools. Routes honest (no sea-crossing straight lines), all three films
worth keeping, **≥ 1 published publicly**, stable export on device. Three trips
is hard and never downgrades to one. Chiu signs off; artifacts land in
`Docs/demos/phase3_5/`.

**Merge point:** the whole Replay MVP goes to `main` as one PR (or a tight
stack) once §6 passes — that is what PR #11 is waiting for.
