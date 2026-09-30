# The opening zooms out of the title card, and the whole route holds before the end card

**Status:** Decided (Chiu, 2026-09-29)
**Supersedes:** ledger entry "2026-08-31" items 1–2 (the cut out of the title card)

## Context

Chiu, on the New Zealand desk render:
*「影片三秒的時候畫面是用跳的，為什麼不是直接從開始的大畫面zoom in到起始點，這樣感覺畫面不好不舒服」*.
When asked, he reopened 2026-08-31's cut by name (「重開，改成連續 zoom in」).

The cut had two reasons, and neither holds now:

- **"A cut out of a title card reads as chrome."** Chiu has now judged the jump,
  and it reads as wrong.
- **The frame after the card divided the body's span** (`bodySpanM`), so the
  country could not be widened without smudging the destination. VERIFIED gone:
  the scale is decided per area and per trip from its own towns (ADR file
  2026-09-28). Nothing reads the frame after the card any more.

On the ending: *「結尾底圖的背景的大小我覺得很好，我覺得在出現結尾字幕之前可以多停1~2秒。給使用者看一下完整旅程軌跡總共跑了哪些地方」*.

## Decision

1. **The title card sits over one held frame**: the country when it adds context
   (as 2026-08-31 items 3–6 still say), otherwise the trip's own region.
   - As the card leaves, **one continuous zoom** takes the camera into the
     journey's start (`containedLerp`, so every frame stays inside the one
     before it).
   - There is no cut and no regional beat, which held between two zooms would
     be a stutter.
   - The zoom lasts `zoom_transition_s` + `opening_regional_s` (3.5 s), which is
     exactly what the duration plan reserves for the opening after the card.
   - The type-2 flight opening is unchanged: one held frame that the aircraft
     crosses.
2. **The revealed route holds for `end_route_hold_s` (1.5 s, the middle of
   Chiu's 1–2 s) before the end card.**
   - The journey ends that much earlier. The seconds come out of the body
     (travel), not out of the film's length, so the Short ceiling and the
     sheet's estimate are unchanged.

## Rejected

- **Easing country → region → body:** two zooms with a hold between them
  stutter.
- **Adding the hold to the film's length:** it would move every film's plan and
  the 90 s Short fit for 1.5 s the road can spare.

## Consequences

- `CameraPath.titleCutS` is nil on every film now, and the continuity gates scan
  the opening from frame 0.
- `CameraPath.collapse` has no production caller left. It is kept with its tests
  and noted on #121 (built, never reached).
- Tests:
  - `testARegionNoWiderThanTheBodyOpensOnTheJourneyWithoutPanning` now asserts
    no cut and no jump as the card leaves; the containment half is unchanged;
  - `RecapCameraAreaTests` reads the reveal as starting before the hold;
  - new `testTheRevealedRouteHoldsBeforeTheEndCard`, which fails with the hold
    at 0.
- Owed: Chiu judges the NZ render, and a device re-export.
