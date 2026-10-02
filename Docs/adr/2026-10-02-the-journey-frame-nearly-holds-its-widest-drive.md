# The journey's frame nearly holds the widest drive between two of the trip's towns

**Status:** Decided (Chiu, 2026-10-02: 「可以167*0.9拉近」 from the New Zealand render, then 「冰島可以」 from Iceland's)
**Supersedes:** nothing. Amends ADR file 2026-09-28-a-drive-is-never-framed-at-town-scale, Decision 1: how the trip's scale is found

## Context

Chiu, on his phone's New Zealand film (build 0.2.1, which has the town rule):
*「在中間行程的時候拉太近了 … 我不希望這是一個常數」*, then of the rule itself:
*「我不能理解，這樣的算法怎麼來的」*.

- The 2026-09-28 scale was the median, over stops, of the frame holding each stop's two nearest other towns. "Two" and "median" were both fitted to his New Zealand verdicts.
- It was not stable (VERIFIED, desk probe): the stops' frames come in two sizes, and the median sat between them — 130 km at the desk, about 64 km on his phone (INFERRED from his screenshot, ±15 %), the scale he had rejected.
- A rule he could not restate was a rule he could not judge. He was shown one frame at 64 / 118 / 167 km, 167 km being the frame that just holds the widest drive between two towns, and chose from the picture: 0.9 of that.

## Decision

1. **A drive** is the road from one town to the next the film stops in: the last stop in one, the first in the other. Stops with no town are driven past.
2. **The journey's scale is `journey_drive_fit` (0.9) of the frame that holds the widest drive.** A share of the trip's own geometry; no distance is tuned.
3. **A scale belongs to one journey.** Each side of a crossing has its own: the drive to the airport does not frame the island.
4. **A journey of fewer than three towns has no scale** and is framed as before, as every island film judged so far was.
5. Earned zoom, earned travel and the areas are unchanged (ADR file 2026-09-28).
6. **The export logs its scales**: `camera: <spans> km · N stops · N with a town · N towns`. Widths and counts, never a place (§0).

Desk results, local dumps with cached towns (VERIFIED, `KAMOME_AREAS`):

| trip | 2026-09-28 rule | now | film |
|---|---|---|---|
| NZ | 130.4 km | 150.5 km | 126.2 → 124.3 s |
| Iceland | 126.6 km | 151.9 km | 173.8 → 170.1 s |
| nz-real (committed, 8 stops) | 118.1 km | 156.0 km | 77.8 → 75.2 s |
| Auckland, after the flight | 110.5 km | 92.0 km | |
| Margaret River (33 km of road) | 16.6 km | 9.1 km | |
| Miyakojima, its round trip, Ishigaki | identical | identical | |

## Rejected

- **The mean of the stops' frames** (built first, 118 km on NZ): steadier than the median, no easier to say.
- **The widest drive, fitted exactly** (167 km): Chiu, from the render — the far towns sit on the edge.
- **One scale across a flight, for any two towns:** it framed Ishigaki at 20 km (VERIFIED; was 4.4 / 11.6 km). INFERRED cause: the drive to the airport in Taiwan was the widest.
- **An upper quantile or a cap in km:** a constant of the kind Chiu asked not to have.

## Consequences

- **0.9 was chosen on New Zealand and accepted on Iceland**, from renders at 150 and 152 km. Two road trips, both of long drives.
- UNKNOWN, no verdict exists: Margaret River and Auckland are now *closer* than before. A short trip's widest drive is short.
- UNKNOWN: one very long drive in a trip of short ones frames the whole film. No fixture has one. The `camera:` line on a real film is the cheapest check.
- The scale cannot move with the film's stop list: more photo stops in a town add no drive. Whether that is what happened on the phone is settled by one re-export and its `camera:` line.
- Tests (`CameraPathJourneyScaleTests`, five). Shown to fail on the median: `testOneMoreStopInATownDoesNotRescaleTheFilm`, `testABasinOfCloseTownsDoesNotSetTheScaleAlone`.
- Owed: a device re-export. Renders: `~/Kamome-films/2026-10-02-nz-scale/`.
