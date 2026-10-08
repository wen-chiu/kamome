# The film counts the road it draws; Home and Footprints count the ground

**Status:** Decided (Chiu, 2026-10-08)
**Supersedes:** nothing. Keeps 2026-09-05 (d) and 2026-09-19 §1 for the film,
2026-09-23 (f) and 2026-10-07-home-reads-like-footprints for the lists.

## Context
#242 said that Trip Detail's stat card and the film print a different distance
from Home and Footprints. Checked against the source on 2026-10-08:
- **Trip Detail matches Home on every shipped trip.** VERIFIED (source): the
  stat card is drawn only when the trip has `stats_json`. Only
  `TrackingSession`, `TripMerger` (for recordings) and the DEBUG-only
  `DemoSeeder` write one. Photo imports and the shipped sample write none. A
  recording's Home figure is that same `stats.distanceM`. The 271 km in the
  2026-10-07 ADR came from `DemoSeeder`.
- **The film differs for a photo trip.** VERIFIED (source): the title card, end
  card and odometer measure the drawn route (`RecapTrip.localRouteDistanceM`).
  Home and Footprints count only ground legs that routing confirmed
  (`LegLength.groundMeters`). The film also counts legs routing has not
  confirmed (drawn dashed, a lower bound), stops at the flight home, and is
  measured on the simplified drawn line. For a recording, the title card prints
  the stored total, as Home does.
- UNKNOWN: the size of that gap on a real routed import. The cheapest way to
  settle it is one routed import, compared on Home and in its film.

## Decision
Chiu, 2026-10-08: 「Keep the film, close #242」.
- The film's kilometres stay the route it draws, so the odometer and the end
  card show one number (2026-09-05 (d)).
- Home and Footprints stay ground kilometres (2026-09-23 (f)).
- They are two figures for two questions, and a photo trip may show both.

## Rejected
- The film counting confirmed legs only: the odometer would move away from the
  drawn line. It changes the film and owes a render.
- The title card taking Home's figure: one film would show two numbers.
- Measuring the gap before deciding: not needed to ship.

## Consequences
No code changes. #242 closes with this file.
