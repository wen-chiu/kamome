# Every camera frame is fitted inside the map's edge before stations are planned

**Status:** Decided (Chiu, 2026-10-07)
**Supersedes:** nothing — revises the "a capability, not a clamp" stance in `MapRendererCapabilities` for latitude only

## Context
An export failed on a device with `SnapshotReprojection.ContainmentError` (#223).
VERIFIED on a real MapLibre snapshot (#223 comment): a frame reaching past ±85.05°
is **shifted** back inside at the same zoom (11,000 km at 48.5°N: centre drawn at
y 900.9, not 960), and one taller than the world is **zoomed in** until the world
fills it (×1.4477 for 25,000 km at 40°N). The station then no longer holds its
frames. A real render of a synthetic Seoul + Reykjavík film reproduced the device
error ("magnified 1.075× misses the frame by 270.9 px"). Such frames come only
from one picture holding places continents apart. All nine desk fixtures have 0,
and so does every drawn type-2 flight within the 70° policy (VERIFIED, grid).

## Decision
Chiu: 「如果你的推薦不會造成程式太多負擔或減低效能 就照你建議的去做」.
- A substrate declares where its world ends, `maxFramableLatitudeDeg`: MapLibre
  85.0511°, MapKit and the flat provider nil.
- `LinearTimeline` fits every frame into that band (`MercatorBand.fitted`) exactly
  as the substrate would move it. A frame already inside is returned as the
  identical value, so other films are unchanged frame for frame and station for
  station (tested).
- The station planner fits each station the same way and keeps it only if, drawn
  so, it still contains every frame of its run (exact Mercator, the render
  loop's own test). Without that, stations past the edge would be one per frame.
- Not silent: the export logs how many frames moved, the largest move in pixels,
  and how many were taller than the map. A `ContainmentError`'s two numbers are
  now logged in the clear.

## Rejected
- A different form for each beat that cannot be drawn (end reveal of the last
  region only, a cut for a far arc). Measured unnecessary: fitting keeps every
  stop in frame unless the route spans more than ~200° of longitude.
- Leaving the clamp to MapLibre: the picture would move after the stations were
  planned, which is the failure.

## Consequences
Cost: films inside the band, nothing; the synthetic intercontinental films,
+6–7% stations (373→397, 378→404, 365→387) for films that used to fail. The
real render's stills keep the whole route in frame. Not fixed here: a trip that
crosses 180° is framed the long way round the planet (#234). It now renders, but
the wrong hemisphere fills the frame until #234 lands.
