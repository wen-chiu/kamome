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

**Recommendation: superseded by §6.** Use the dynamic context floor instead
of A's fixed number, and keep B.

## 5. Owed (as of §4; §6 replaces A)

- Chiu: pick A's value from the 4 / 6 / 9 km sheet. Decide on B.
- Engineering, after that: the new key goes in `TrackingConfig.json` with no
  magic numbers. `testAOneAreaTripIsUnchangedByAreas` still has to hold. Run
  `./check.sh`, then re-render Miyakojima and Vietnam (both device-only).

## 6. Dynamic: each area's floor comes from the place around it

Chiu, 2026-09-24: *「旅程地點不同 需要zoom的比例也不同」*. The right floor
depends on where you are. A fixed metre floor cannot give an island town
enough context and still leave a road-trip town readable.

### Judged, in relative terms

Relative to the place the stops sit in (the island), both of Chiu's verdicts
are depths:
- 19 km is about 1.7× inside Miyakojima's 31.6 km box: **too wide**.
- 1.9 km is about 17× inside it: **too tight**.
The geometric mean is about **5×**. So the rule to try: *never frame an area
more than about 5× deeper than the place it sits in.* "The place" has to be
found per area, not taken from the trip's box (§4 C).

### Finding "the place it sits in": the trip's own scale ladder

Link stops by single-linkage (the minimum spanning tree over stop positions).
The joining distance jumps wherever the trip moves up a level (town →
island → country). Measured on the committed fixtures
(`Tools/stop-scale-ladder.py`: photos within 300 m merged into stops, a break at a
link more than 3× the largest link so far). VERIFIED at the desk; that stops
≈ photo clusters is INFERRED:

| fixture | natural levels (cluster span) | parent of a town area | floor = parent ÷ 5, ≤ 10 km |
|---|---|---|---|
| miyakojima-round-trip | town → **32.5 km** (island) → Taiwan | 32.5 km | **6.5 km** |
| ishigaki-crossing | 0.6 km → **34 km** (island) → 312 km | 34 km | **6.8 km** |
| auckland-crossing | 1 km → **34 km** → 158 km → 7038 km | 34 km | **6.8 km** |
| miyakojima (local) | 0.3 km → whole 25.5 km | 25.5 km | **5.1 km** |
| finland | 2 km → whole 64 km | 64 km | 12.8 → **10 km** (cap) |
| new-zealand | 1.1 → 4.8 km → whole 205 km | 4.8 / 205 km | 1.5 km / **10 km** (cap) |
| margaret-river | one level, 13.4 km | 13.4 km | 2.7 km |

On islands and city regions, the parent level is the island or the region
itself: the thing a viewer recognises. On a road trip, the level above a town
is the whole route, which is a line rather than a place. That is what the cap
is for.

### The rule

    floor(area) = clamp(parent(area).span ÷ camera_context_depth,
                        camera_span_m, camera_context_span_max_m)
    span(area)  = max(existing ask, floor(area)), then the existing ceilings

- `parent(area)`: the smallest ladder cluster that strictly contains the
  area's stops and whose link is a level break. It is computed once per film
  in Core, is deterministic, and uses no new data. That leaves the
  Story/Rendering boundary and §0 alone.
- `camera_context_depth` = **5** (INFERRED, the relative midpoint above).
  `camera_context_span_max_m` = **10 km** (INFERRED, about city scale).
  Both go in `TrackingConfig.json`.
- Every area gets its own floor, so as the trip moves between places and
  days, the scale changes with it. Seams that end up closer than
  `opening_collapse_zoom_ratio` still merge.

### What it does not solve

- **A dense city.** At 6–10 km, Tokyo is still all streets. The anchor there
  has to be text: B, the place name in the pill. At that point the name
  (locality or prefecture) can follow the same ladder: one name per level,
  and the area shows its parent's name. The field choice is UNKNOWN (§4 B).
- **Vietnam and Chiu's own dump:** UNKNOWN. What would settle it: run the
  ladder on the local dumps and add a desk test that pins each area's floor.

### Owed

1. Chiu: approve the rule. It is a framing change (hard rule 2).
2. Build: `CameraPath` ladder + floor, two keys, tests pinning the table
   above. `testAOneAreaTripIsUnchangedByAreas` needs care, because the floor
   applies to one-area films too; that is a deliberate behaviour change, so
   the baseline gets re-pinned with Chiu's approval and the test is not
   weakened. Then `./check.sh`.
3. Render Chiu's Miyakojima Day 1 at depth 4 / 5 / 6 so he can pick the value.
