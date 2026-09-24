# Camera context floor — "too tight to know where you are"

Status: **analysis + proposal, nothing built.** Every lever below changes what
the film looks like, so it waits for Chiu (CLAUDE.md hard rule 2).
Raised 2026-09-24 by Chiu from a Miyakojima device film under ADR 2026-09-24
(camera areas): *「宮古島的當地行程又有點zoom in得太近了……最少可以看得出來在哪裡，
太細部的行程會不知道自己在哪裡」*.

## 1. What the frame is today

- The body is now framed per area (ADR 2026-09-24). An area's span is its own
  extent × `wide_span_padding` ÷ `target_zoom_ratio`, **floored at
  `camera_span_m` = 1500 m** (`CameraPath.areaNeedM`, `spansM`). VERIFIED (code).
- Measured at the desk on `miyakojima-round-trip`: the town area lands on
  **1.9 km**, and the old one-span rule gave 19.5 km. VERIFIED (ADR 2026-09-24 §4).
- The screenshot Chiu sent ("Day 1 · 3 km") looks like a frame about 2 km wide.
  INFERRED from the route's size on screen. What would settle it: log the area
  spans for Chiu's dump in `RecapCameraAreaTests`.
- `camera_span_m` was picked as a follow-camera span, not as a legibility
  limit. Before areas, nothing local ever reached it. Now a town loop does.

## 2. Why 2 km reads as "somewhere, nowhere"

1. **The only place names in frame are villages, and they are unreadable.**
   At 2 km on a 1080 px frame, MapLibre renders at z ≈ 15.3
   (`MapLibreSnapshotProvider.zoomLevel`, scale 1). `freeze-liberty-styles.py`
   doubles city/town/island labels but **not** `label_village` (10→12 px).
   12 px on a 1080 px frame shown about 390 pt wide on a phone is roughly
   **4 pt of text**. That matches `KUNINAKA 国仲` in the screenshot.
   VERIFIED (style JSON + screenshot).
2. **No anchor.** At this scale the frame holds no town, city or island label
   and no recognisable coastline shape. INFERRED from one screenshot.
3. **The film has no other "where" channel.** The pill says `Day 1` only.
   VERIFIED (screenshot).

Span → MapLibre zoom at 24.8° N, 1080 px (pure geodesy, computed):

| span | 1.9 km | 3 km | 4.7 km | 6 km | 8.5 km | 12 km | 19 km |
|---|---|---|---|---|---|---|---|
| zoom | 15.3 | 14.6 | 14.0 | 13.6 | 13.1 | 12.6 | 12.0 |

## 3. The balance is not one number

Chiu has now judged both ends:

- **19 km: too wide.** "目的地行程路線根本看不清楚" (the route is a smudge).
- **About 2 km: too tight.** "不知道自己在哪裡" (you can't tell where you are).

These are two different needs. **Reading the route** wants the frame tight.
**Knowing where you are** wants an anchor in view. At some stops no single
span serves both. The fix is to give orientation a channel of its own, so the
span only has to serve the route, and then stop the span from going below a
scale where the map still shows context.

## 4. Proposal (ranked; each is Chiu's call)

**A. Raise the floor to a context scale.** Cost: one key plus a render.
Add `camera_context_span_m` and use it wherever a body span is floored
(`areaNeedM`, `spansM`, `RecapDurationPlan.bodySpanM`). Keep `camera_span_m`
for the prologue and anything else that is not framing a body.
- **Starting value: 6 km.** It is the geometric mean of the two judged ends
  (√(1.9 × 19) ≈ 6.0). At Miyakojima's latitude that is z ≈ 13.6, INFERRED to
  be enough to show coastline and town labels. INFERRED, not judged.
- What would settle it: one contact sheet of Chiu's Miyakojima Day 1 at
  **4 / 6 / 9 km**, and Chiu picks.
- Side effect, a good one: town areas rise to the floor, so more seams fall
  under `opening_collapse_zoom_ratio` and merge. That means fewer reframes and
  less pumping. INFERRED.
- Road trips: Iceland and New Zealand areas are all wider than 6 km, so they
  are unaffected. INFERRED from ADR 2026-09-24's list of spans.

**B. Put the place name in the pill.** For example `Day 1 · 宮古島`, from the
stop names Kamome already asks Apple for (a §0 exception, Chiu 2026-09-17).
This is the only channel that says "where" at every zoom level. It is a
product and visual change, so it needs DESIGNER.md. Which field to use
(locality or administrative area) is UNKNOWN. What would settle it: dump
`CLPlacemark` fields for the Miyakojima stops.

**C. Rejected: a floor relative to the destination** (area ≥ established ÷ k).
It brings back the bounding-box failure that ADR 2026-09-24 removed. Iceland's
~700 km establishing frame ÷ 4 would frame Reykjavík at about 175 km.

**D. Deferred: a locator inset, or an "anchor label in frame" search** over the
vector tiles. Both work, and neither is boring technology. The anchor search
also puts tile queries inside Core, which crosses the Story/Rendering line.

**Recommendation: A at 6 km as the first render, with B designed alongside it.**
A alone probably fixes Miyakojima. B is what keeps a dense city, where 6 km
is still just streets, from having the same problem.

## 5. Owed

- Chiu: pick A's value from the 4 / 6 / 9 km sheet. Decide on B.
- Engineering, after that: the new key goes in `TrackingConfig.json` with no
  magic numbers. `testAOneAreaTripIsUnchangedByAreas` still has to hold. Run
  `./check.sh`, then re-render Miyakojima and Vietnam (both device-only).
