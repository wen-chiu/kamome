# A trip that crosses 180° is unwrapped once, so the camera frames it the short way

**Status:** Decided (Chiu, 2026-10-07)
**Supersedes:** nothing

## Context
The camera takes longitude as a plain number: min/max bounds, spans, the follow
cam, the opening's lerp, `CrossingFraming`'s longitude test (#234). Across 180°
that is wrong by a planet. Synthetic Taipei → Tokyo → Vancouver asked for frames
44,338 km wide over the wrong hemisphere, and with the band
(2026-10-07-every-frame-fits-inside-the-maps-edge) 1,770 stop positions the
frames should have held fell outside them (VERIFIED, #234). Taipei → Tonga
measured 296° apart instead of 64°, and a local trip on 180° got a whole-world
frame. VERIFIED on real MapLibre: a camera centre past ±180° draws garbage,
while for a normal centre `point(for:)` returns the copy nearest it (centred on
179°, −179° and 181° both land at x 606).

## Decision
Chiu, 2026-10-07: 「修 #234」.
- `LinearTimeline` unwraps the trip once, before anything is measured: the seam
  goes into the widest stretch of longitude the trip never visits
  (`Antimeridian`). A trip that does not cross 180° already has it there and is
  returned as the identical value, so every other film is unchanged.
- Unwrapped longitudes may pass ±180. Only the camera centre is normalised, at
  the substrate boundary (MapLibre and MapKit); every projected point lands on
  the copy nearest that centre.
- The opening's country extent, stored in ordinary longitudes, is looked up
  normal and framed back in the route's window.

## Rejected
- Teaching each of ~30 call sites about the seam: thirty places to get wrong,
  against one unwrap at the waist.

## Consequences
Synthetic films: Tokyo + Vancouver widest frame 44,338 → 19,538 km, stops lost
1,770 → 0, stations 397 → 371; Tokyo + Anchorage 44,701 → 13,763 km; a local
trip on 180° 117 km wide; Taipei → Tonga draws its flight. A real MapLibre
render of the Pacific film exported every sampled frame across the seam.
Outside the film (`RecapTrip.filmType` read by the export log, the map credit's
bounding box) longitudes stay raw; neither moves the camera.
