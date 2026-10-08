# Trip Detail's stat card prints the trip's ground distance, as Home and Footprints do

**Status:** Decided (Chiu, 2026-10-08)
**Supersedes:** nothing; extends 2026-10-07-home-reads-like-footprints to Trip Detail

## Context
After 2026-10-07-home-reads-like-footprints, Home and Footprints print one
distance for a trip, `LegLength.groundMeters`: a recording's measured distance,
or a photo trip's routed ground legs with flights left out (Chiu 2026-09-23).
Trip Detail's stat card still printed `stats.distanceM` and the stop count
stored when the trip was made (#242, VERIFIED in source). Only recordings carry
`stats_json`: photo imports and the shipped sample write none, so they had no
card at all. A recording's Home figure is that same `stats.distanceM`, so the two
already agreed for it. The 271 km in 2026-10-07 came from the DEBUG `DemoSeeder`
(corrected 2026-10-08, from #251; VERIFIED in source).
The film measures the route it draws (`RecapTrip.localRouteDistanceM`: the end
card, the odometer, and a photo trip's title card; 2026-09-05 (d), 2026-09-19
§1). A recording's title card prints `stats.distanceM` minus flown legs.

## Decision
Chiu, 2026-10-08: 「#242 照你建議做」.
- The stat card's distance is `LegLength.groundMeters(trip:segments:)`, in
  Home's words (`journey_km`); a dash while no leg counts yet.
- Its stop count is the trip's stops as they stand, which is what Home and
  Footprints count.
- The film's figure is unchanged. Chiu, 2026-10-08, asked separately (#251):
  「Keep the film」. The film counts the road it draws, so the odometer and the
  end card agree; a photo trip may show a different figure in its film than on
  Home, Footprints and Trip Detail.

## Rejected
- Changing the film's figure too: it was decided by measurement with the film,
  and the app UI does not override a film decision by taste.
- Keeping `stats.distanceM` on the card: it counts flights, which 2026-09-23
  refused for every distance shown as "on the ground".

## Consequences
Home, Footprints and Trip Detail print one distance per trip; a photo trip now
gets a stat card it did not have. The film can still differ by its own rule. UNKNOWN how often the film's figure and the
ground figure differ on a routed trip; comparing both on one routed photo
import that includes a flight would settle it.
