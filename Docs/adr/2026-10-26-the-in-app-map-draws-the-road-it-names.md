# Trip Detail's map draws a matched leg along its road, names only the road it draws, and frames the trip itself

**Status:** Decided (Chiu, 2026-10-26)
**Supersedes:** nothing — S3's map drew trackpoints only and took MapKit's automatic camera; no decision chose either

## Context
#195: Trip Detail drew every leg from its trackpoints (`TripDetailModel.thinned`), so an
imported leg was a straight line between two photographs even with a road stored in
`matched_polyline`; the film, `LegLength` and routing read that road, no map in `UI/` did.
VERIFIED on `main` 2026-10-26 with the sample: four straight chords down the coast while
its OpenStreetMap road ships stored. #195 also found the diary's map under a 「已對齊道路」
legend; that map went on 2026-10-06 (`659f657`, #169). Today's diary has no map, and its
one 「已對齊道路」 is a leg's caption, shown only when every segment of the leg has a road
(`RecapComposer.provenance`, weakest claim) — VERIFIED in source and on screen.
#295 item 5: the map framed more than the trip. On the desk (iPhone 17 Pro simulator)
MapKit's automatic camera centred the sample and left margins of its own; most of the
width beyond the route is the map's shape, a ~140 km north–south trip in a near-square
map. Chiu's "route along the right edge" was not reproduced — UNKNOWN which state showed
it; opening the sample on the phone would settle it.

## Decision
Chiu, 2026-10-26 (#195, #295): 「Trip Detail and the diary draw a matched leg from
`matched_polyline`. A leg with no matched road keeps today's line and is not labelled
「已對齊道路」: the line and its legend say the same thing (rule 5). The map frames the
trip itself.」
- One choice of line, `LegGeometry`: the stored road (two points or more), else the
  leg's own points — for Trip Detail, the film and `LegLength` alike. A road is thinned
  at `matching.display_epsilon_m` as in the film; any other leg as before. Strokes unchanged.
- The diary needs no change: it draws no line, and names a road only where one is stored.
- The camera frames the bounding box of what the map draws, lines and pins, under the
  day chip, × `trip_map.frame_padding` (1.25), at least `trip_map.frame_min_span_m`
  (2000), across 180° the short way. It re-frames only when that box changes, so a pan
  survives the reloads stop naming causes. Both numbers and framing a chip's day are the
  implementing session's (INFERRED); Chiu judges them from the screenshots on the PR.

## Rejected
- Dashing an unmatched leg, as the film does (#195 option 2): Chiu kept today's line.
- Keeping straight lines and dropping the label (option 3): the road is known; draw it.
- MapKit's automatic camera: its margins are its own, with no handle on what is framed.
- Sharing ExportEngine's `Antimeridian.windowStart`: it is internal, and making it public
  changes a module interface (rule 2); its eight lines are restated at MapKit's boundary.

## Consequences
`trip_map` in `Config/TrackingConfig.json`; `TripMapFrame`; `thinned` takes the road ε;
`TripDetailRoadTests`. DEBUG desk arguments `-demo-seed-sample`, `-demo-seed-mixed-legs`,
`-demo-open-journey`. UNKNOWN: drawing cost on a long trip with many matched legs (more
points at 5 m than at 15 m); opening the longest routed trip on the phone would settle it.
