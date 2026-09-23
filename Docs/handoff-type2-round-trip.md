# Handoff — the Miyakojima film: round trips, airport-only homes, the crash

**Opened 2026-09-23** from Chiu's device export of his Miyakojima trip. The
decisions are ADR 2026-09-23 (b) and (c); this file holds what is **owed** and what is
**not known**, and is archived when the device re-export below is judged.

## What changed (one line each — the ADR has the reasoning)

1. `RecapFilmType.distinctJourneyCount` counts a trip's first/last place as
   ground when its crossing outspans the ground beside it → an airport-only home
   is a type-2 trip again.
2. `RecapTypeTwoFilm.homecomingLegIndex` + `RecapComposer.filmRecords` build ADR
   2026-09-01's "no return flight": cut by time at the first crossing landing
   within `discovery.away_radius_m` of home.
3. `FrameCompositor` flies the plane on every crossing.
4. `MapLibreSnapshotProvider.MainThreadLeases` owns every snapshotter and
   releases it on main (the device crash).

## Measured at the desk (VERIFIED 2026-09-23, simulator)

New committed fixture `miyakojima-round-trip` (public places, synthetic times —
Chiu's shape: an airport pair at home on each end, nothing driven there), routed
by `UnroutableSeaProvider` and added to `RecapCameraContinuityTests`:

- `homecoming: 1 legs, 1 stops left out` · `film type: oneDestination · 2 local
  journeys` — the old rule counted this shape as 1 journey (`.unknown`).
- `RecapTimelineReportTests`: title 0–3.00 s · Taoyuan departure 3.00–6.41 s ·
  flight 6.41–10.41 s · closing zoom to 12.91 s · 78.5 s total.
- Established span **614.8 km** → body **19.5 km** (31.5×): the island fills the
  frame after the flight. Continuity ✅, 0 violations, opens on the flight.

## ⏳ Owed — needs the phone

- **Re-export Miyakojima (`1C3B9614…`).** The log must read
  `film type one destination abroad` (or `multi-region` if a transit remains) and
  `the trip comes home — … left out`; the film must open on the plane + pass and
  end on the island. Chiu judges the picture.
- **The crash.** It was an interleaving, so one clean export proves nothing.
  Cheapest real evidence: three full exports of the longest trip on the phone,
  then `xcrun devicectl device info files --domain-type systemCrashLogs` shows no
  new `Kamome-*.ips`.

## Status of every claim

| claim | status | cheapest thing that settles it |
|---|---|---|
| The film was `.unknown` with 4 crossings, 1 journey | VERIFIED — device log | — |
| Home side was airport photographs only | INFERRED from the counts (DB read was denied this session) | read segment modes/verdicts on device, counts only |
| The 4 crossings are 2 flights + 2 beach/transit legs | UNKNOWN | same read |
| Crash = snapshotter `dealloc` off main | VERIFIED thread 13 shape; MapLibre frames INFERRED (binary stripped) | MapLibre dSYM for `30B84B8E…` |
| The fix removes the crash | INFERRED — the lease contract is tested, the interleaving is not reproducible in CI | three device exports, no new `.ips` |

## Known limits, accepted

- ~~A beach photograph's "no road" leg shows a short plane hop~~ — **closed by
  ADR 2026-09-23 (c)**: `No suitable edges` is its own verdict and never a
  crossing. Owed on the phone: the routing line on the Miyakojima re-export
  should show its beach legs under `off the road network`, not `NO ROAD`.
- **Flying home to a different city** (Kaohsiung after Taoyuan) keeps its last
  flight: 300 km is not home under `away_radius_m`.
- **The first crossing is assumed to be the flight.** A "no road" beach leg in the
  origin *before* the flight would open the film on it. Pre-existing
  (`RecapTypeTwoFilm.destinationJourney`), not widened by this change.
- **Origin stops still spend the stop budget** before `LinearTimeline` trims them
  (8 stops on every trip, Variant B) — the return's no longer do.
