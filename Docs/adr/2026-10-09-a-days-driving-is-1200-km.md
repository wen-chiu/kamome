# A road with no photograph along it is a road only up to 1,200 km

**Status:** Decided (Chiu, 2026-10-09)
**Supersedes:** the witness ceiling of 2026-10-03-a-road-is-stored-only-if-it-could-be-driven

## Context
The witness test refused a routed road as `implausible_route` when a stretch of
it longer than "a day's driving" had no photograph along it. That day was
`route_unwitnessed_max_drive_s` (10 h) at `crossing_route_pace_min_kmh`
(120 km/h): **4,320 km** (VERIFIED, `RouteFeasibility`). A device film
(2026-10-08) logged `0/40 legs marked crossing` and drew a multi-flight trip as
one drive — film type UNKNOWN, so neither the outbound nor the homecoming trim
ran (VERIFIED, diagnostics). That flights of 2,000–4,000 km over connected land
with a night either side passed as road under 4,320 km is INFERRED: the
per-leg `route: feasibility` lines are written at import, and the diagnostics
keep only the current launch and exports. Settled by re-importing the trip
and exporting the diagnostics in the same launch.

## Decision
Chiu: 「4,320 km 確實太多 我覺得開車最多就是1200」, and on rail: 「高鐵才會有可能超過這個距離」.
- `matching.route_unwitnessed_max_m` = 1,200,000 replaces
  `route_unwitnessed_max_drive_s`: the ceiling is a distance, as decided, not
  hours × a pace.
- Over land, only China's longest high-speed services cover more in a day
  (Beijing–Kunming 2,760 km, Beijing–Hong Kong 2,439 km). Within a day the time
  test already makes those crossings (≈ 216 km/h against 120); with a night
  either side they now draw dashed rather than as road. Shinkansen (675 km
  longest line), TGV/AVE and Taiwan HSR stay well under.

## Rejected
- 800 km — the low end of Chiu's range: more real one-day drives with no photo
  drawn dashed, and no flight caught that 1,200 km misses.
- Keeping hours × pace — two numbers standing for one Chiu stated as a distance.

## Consequences
Config key renamed, value 1,200 km. Stored verdicts are still not re-judged
(ADR 2026-10-03): a trip already imported changes only when deleted and
imported again. Discussed, not decided here: a time-zone test at export from
`stop.time_zone`; routing only at export (Chiu: leave it at import for now).
