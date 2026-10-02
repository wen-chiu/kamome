# A waypoint the drive profile refuses is asked again from where a walk reaches it

**Status:** Decided (Chiu, 2026-10-01)
**Supersedes:** nothing. Amends 2026-09-23 (c) (what `No suitable edges` leads to) and refines 2026-08-20 (d) ("no snap radius exists")

## Context

Issue #172. Chiu, from a phone export: 「海邊的照片被判斷出沒有路線的機率很高」 — a
Miyakojima film reported 5 legs with no road, each a straight dashed line over
land that has roads. One beach stop costs two legs, the one in and the one out.

Measured through the Worker on 2026-10-01, public landmark coordinates only:

- **VERIFIED:** stepping out from the car park at Reynisfjara, the drive profile
  answers 200 at 144–461 m and `400 No suitable edges` at 519 m and 576 m. The
  walk profile answers 200 at all of them, and at a point 2.1 km from any path.
- **VERIFIED:** the walk answer has one part per waypoint pair, and the drive
  profile accepts the walk route's last coordinate. Skógafoss → the Reynisfjara
  sand: refused; walk moves the end 576 m; drive again is 200 at 1.30×.
- **INFERRED:** the drive profile has an implicit snap cutoff near 500 m
  everywhere (one beach). Settled by the same step-out on two more beaches.
- **INFERRED:** Chiu's 5 legs were `off_road_network`. Settled by that trip's
  routing summary line in About → Export diagnostics.

## Decision

Chiu: 「如果你判斷是那就可以。步行吸附距離上限先放 650 公尺」.

When drive answers `No suitable edges`, `GeoapifyRouteProvider` asks the walk
profile once with the same waypoints, takes the points where the walk route's
parts meet, and asks drive again through those points. A route that comes back
faces the detour gate as any other, measured against the original waypoints.
If any waypoint moved more than `matching.route_off_network_walk_snap_max_m`
(650), or the walk or the second drive request is refused or unreadable, the
leg stays `off_road_network`, as before. Nobody answering throws, so the leg is
asked again on the next export.

Stored verdicts are not re-asked (Chiu: he re-imports the trip himself).

## Rejected

- A snap-radius parameter: the provider has none (2026-08-20 (d)).
- Drawing the walk geometry: a footpath is not the road the car took.
- Moving only the refused waypoint: the 400 does not say which one it was.
- Bumping `SegmentRoutability.rulesVersion` to re-ask stored beach legs.

## Consequences

- A beach stop within 650 m of where a walk joins the network gets a solid road
  to the car park; its pin already sits on the drawn route (2026-08-06).
- Up to two more requests per refused leg, once. Same provider, same waypoints
  (CLAUDE.md §0); no walk geometry is kept.
- Not covered: one via-photograph farther than 650 m still dashes its leg, and
  a peninsula road over 2.5× the straight line is still refused by the gate
  (Vík → Reynisfjara measured 3.56×).
- Owed, device: re-import a trip with a beach stop and read the routing summary.
