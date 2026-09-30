# A trip is framed by its own towns, and travel lasts only as long as its windows need

**Status:** Draft (built at Chiu's request 2026-09-28/29; the direction is approved, and the renders are owed his judgement)
**Supersedes:** nothing. Amends ledger entries "2026-09-24" §2.2 (the brief-area merge), "2026-09-24 (e)" (the scale on a road trip), "2026-08-14" (travel's fixed share) and "2026-09-27" (the length on the sheet)

## Context

Chiu, on his New Zealand film, over four rounds:
*「車子一直跑浪費一堆時間」*, *「tekapo跟mountain cook那邊都不用拉這麼近」*,
*「除非是使用者有市區行程…我們可以拉近」*,
*「旅程地點行進長度密度不同我們要顯示的畫面大小就要有所變化……不要用其中一個旅程的數目當作常數」*,
*「宮古島市區日會比以前寬 這也不合理」*.

His judgments, which fixed the design (VERIFIED as statements; frame sizes read off renders, so INFERRED ±20 %):

| trip | frame | verdict |
|---|---|---|
| NZ Tekapo / Wānaka | about 60 km | too close |
| NZ Cromwell | about 110 km | fine |
| Miyakojima | 19 km | too wide |
| Miyakojima | 1.9 km | too tight |
| Miyakojima | 12.4 km (was 8.5 km) | wider is wrong |

No geometric ratio separates the two trips: the towns sit at about 1/20 of the trip in both (VERIFIED at the desk). What separates them is **how dense the towns are**.

## Decision (chosen by Chiu 2026-09-29, 「照這個做」「兩者都要」)

1. **Journey scale from the trip's own towns** (`CameraPath.journeySpansM`).
   - For every stop, take the frame centred on it that holds the stops of
     its **two nearest other towns**: one reference says how far, two say where.
   - The trip's scale is the median of those frames.
   - Every area is shown at that scale unless it earns its own.
   - A town is the stop's `locality`, joined with stops within `camera_span_m`
     (the geocoder is noisy: a lakeside stop 2 km out comes back as a "Ward").
   - Never across a crossing.
   - A trip that is all one town (Miyakojima geocodes to one municipality),
     or has no names, has no scale and is framed exactly as before.
2. **Earned zoom.** An area keeps its own, tighter frame only when all three hold:
   - its stops are all one town;
   - it fits inside the journey frame;
   - its route crosses at least 2 × `zoom_transition_s` × the travel rate
     windows of the frame that just holds it.

   That means days driven around a town. An airport and a mall, three
   lakeside stops, or the road in and out of Mt Cook past two other towns do
   not earn it.
3. **The brief-area merge** never absorbs into a neighbour more than
   `target_zoom_ratio` tighter. Areas merged down to one stay an area rather
   than falling back to the bounding-box rule.
4. **Earned travel** (`travel_pacing.windows_per_s` 0.6, INFERRED from
   Miyakojima's pace).
   - The film is rebuilt on a shorter clock, with the framing frozen.
   - The stops take back, out of the road's saving, the ~12 % `cappedHolds`
     had squeezed from them.
   - The film is never longer than the plan.
   - A rebuild that would let a crossing arc lose its subject is refused.
5. **The sheet measures the length** from the export's own composition
   (`RecapComposer.filmComposition`, shared) and timeline, in the background.
   It keeps the 「約」 label.

Desk results, local dumps with cached town names:

| trip | reframes | film |
|---|---|---|
| NZ (routed render) | 10 → 0; one ~130 km scale | 154.5 → 129.6 s; stops get 99 s, was 85.5 s |
| Iceland | 11 → 0; 127 km | 211 → 171 s |
| Miyakojima | identical frames (8.5 / 18.2 / 8.3 / 6.3 km) | |
| Miyakojima round trip | identical (6.5 / 9.1 km) | |

The continuity and crossing gates pass on every fixture.

## Rejected (each built, measured and dropped)

- **A tuned cap (80 km):** a constant fitted to one trip.
- **Earned zoom by moving seconds alone:** it widened Miyakojima.
- **One reference town:** 60 km on NZ, which Chiu judged too close.
- **Clustering unnamed stops into towns:** it made every photo spot on an
  island a town (the round trip widened from 6.5 to 27 km).
- **Re-deciding the areas on the shorter clock:** unstable.

## Consequences / owed

- Chiu judges the NZ render and a device re-export. UNKNOWN: Vietnam, Japan.
- The desk geocoder now caches towns in `local/<fixture>-places.json`
  (gitignored), from the same Apple lookup the app makes.
- Tests:
  - new, each shown to fail without its rule:
    `testARoadTripIsFramedByItsOwnTownsWithoutZooming`,
    `testATripOfOneTownIsFramedAsWithoutTowns`,
    `testATownDrivenAroundKeepsItsZoomOnARoadTrip`,
    `testALongDriveKeepsItsOwnWideFrame`, `EarnedTravelTests`,
    `testTheSheetSaysTheExportsLength`;
  - town fixtures re-expressed as days in a town;
  - `testASmallTripShowsWholeDecks` re-baselined [4, 8, 8, 8] → [5, 8, 8, 8]
    (more shown), flagged under hard rule 3.
