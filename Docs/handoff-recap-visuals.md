# Handoff — Recap Layer 3 + visual redesign (2026-07-25)

Branch `phase-3-recap`, commits `ce28db6` (Layer 3 + redesign) and `2917008`
(final car art). 119 tests green, `swiftlint --strict` clean. **Not merged —
PR #11 still holds until the §6 three-real-trip gate.**

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
  timeline's own `cameraFrame`, so the base map dollies into a stop. Z-order
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

**The card's scale envelope and the camera dolly are deliberately different
curves.** The camera reaches `deck_span_m` over `deck_zoom_s` and holds; the card
keeps opening across the whole dwell. One value driving both is exactly what this
forbids — locked by
`LinearTimelineTests.testDeckRevealKeepsOpeningAfterTheCameraDollyHasSettled`,
which asserts `reveal < 0.6` at the instant the map finishes dollying.

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

## 7. What is left before PR #11 can go up

Nothing in this document blocks. The remaining work is **device validation plus
two deferred rendering decisions**, in rough dependency order.

### Code work still outstanding

1. **MapLibre production switch** — `RecapModel` still constructs
   `MapKitSnapshotProvider`. Flipping it to `MapLibreSnapshotProvider` retires
   MapKit and the OSM attribution overlay. Deferred at the §3 sign-off
   (2026-07-22) and *not* re-opened by this session; the 8-direction car renders
   identically on both, so the switch is now purely a base-map change and no
   longer gated on the subject.
2. **Compositor atmosphere** — vignette / route-glow / grade as `RecapTheme`
   tokens, plus labels/glyphs and the `RecapStyle.modernMinimal` preset. Also
   deferred from §3. The stills use an ad-hoc `glowRouteStyle()` in the harness;
   the shipped default is still the plain blue trail.

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
