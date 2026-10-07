# A photograph taken in flight makes its leg a crossing, at import

**Status:** Decided (Chiu, 2026-10-06)
**Supersedes:** nothing — the second layer named in ADR 2026-10-03-a-road-is-stored-only-if-it-could-be-driven

## Context
Every crossing verdict so far reads the photographs' clocks (`LegPace`,
`RouteFeasibility`), and a night either side of a flight defeats both — the
road is then refused as dashed at best, never flown (#222). Import read only
latitude and longitude (VERIFIED, `PhotoLibraryImportSource`), and a window
photograph made things worse: seconds apart at ~900 km/h, it is a lone cluster,
so it became an **interior waypoint** of the flight's leg — sent to the road
router as a via point, and counted by #222 as a *witness* of a drive (VERIFIED,
`PhotoImportClusterer.legs`). How often real window photographs carry a GPS fix
in airplane mode is UNKNOWN; the import log now counts them.

## Decision
Chiu, 2026-10-03, on the layering: 「照你建議的分層」, and 2026-10-06: 「解223 224」.
- Import reads each photo's fix as **lower bounds**: altitude less vertical
  accuracy, speed less speed accuracy; an invalid value is nil. They live only
  in `ImportPhoto` — read on the phone, never stored (§0).
- A photograph at ≥ `import.airborne_min_altitude_m` (6,000 m: above the highest
  motorable passes, ≈ 5,800 m) or ≥ `import.airborne_min_speed_kmh` (450 km/h:
  above the Shanghai maglev's 431) was taken in flight. Both numbers are the
  implementing session's; Chiu may restate them.
- Every leg holding such a photograph — as an interior point, or as a stop end,
  so a stop of window photographs flies both its legs — is stored
  `beyond_driving` straight after the trip is saved, before routing runs.

## Rejected
- Storing altitude and speed per trackpoint — a schema change for a fact needed
  once, at import, and more location-derived data kept on the device.
- Dropping airborne photographs from the trip — they are often the photographs
  of the flight; whether one may be a *stop* is a product question (below).

## Consequences
New `import` keys `airborne_min_altitude_m` 6000 and `airborne_min_speed_kmh`
450; `ImportPhoto.isAirborne`; an import log line with the counts. Trips already
imported are unchanged until re-imported. Open for Chiu: two window photographs
seconds apart still form a stop in the sky with its own card.
