# A new day presses a stamp into the film

**Status:** Decided (Chiu, 2026-10-28) — the stamp's position, ink and timing are a first cut, INFERRED, for Chiu to judge from the film
**Supersedes:** nothing. Reopens, for this one slice only, the icebox entry "Place names as narrative rhythm" and Story Director "chapters"

## Context
The film names places often (stop label, deck caption, HUD place, town names), but a new day had no
moment: the HUD's day text changed on arrival, and nothing else did.
- VERIFIED (source): the day is `RecapTrip.Stop.dayLabel` and the HUD turns over when the day's first
  stop arrives (`LinearTimeline.dayLabel(atTime:)`); a one-day film's labels are `""`
  (ADR 2026-10-26-a-one-day-film-names-no-day).
- VERIFIED (desk, `RecapTimelineReportTests`): New Zealand turns the day 8 times, Iceland 11. Before
  most turns there are 0.04–5.2 s of road; every turn has a 1.0 s arrival beat before its photographs
  open, and a 0.4 s pull-away after the previous stop's photographs close.

## Decision
Chiu, 2026-10-28: 「參考 Polarsteps 的優點，做出卡摸咩自己的風格，不要跟它一樣」, reopening the two
deferred items for this work and nothing else on the deferred list.
- When the day turns, a hand-drawn ink stamp naming the new day presses into the frame, holds, and
  shrinks into the HUD pill's day slot; the HUD's day appears as it lands. The pill's previous day fades
  out first and the slot stays empty under the stamp, so the day is never shown twice in one frame.
- Content is the stop's own `dayLabel`. No new day rule: the film's first day and a one-day film have
  no turn and no stamp.
- **No added film time.** The stamp rides on the pull-away, the road in and the arrival beat; it lands
  on arrival where the road has room, and inside the arrival beat where it does not. It is never on
  screen with a photograph, the title card, the boarding pass, a crossing or the end card. A turn with
  less than `export.day_stamp.min_s` of room turns over unstamped and the log names its stop index.
- The type is the HUD's face; the hand-drawn part is the stamp: a wobbling double border, the
  wordmark's gull breaking its top edge, ink gaps, set askew. Deterministic (FNV-1a of the day).
- It crosses the waist inside `OverlayContent.hud` as `RecapDayStamp`, because it lands in a slot
  that only the pill's layout knows. Tokens: `RecapDayStampStyle`. Timing: `export.day_stamp`.
- First cut: pressed under the pill, vermilion ink `#D9452E`, 0.25 + 0.35 + 0.9 + 0.55 s.

## Rejected
- **Adding time for the stamp:** pacing is Chiu's decision, and the room was there.
- **The film's accent `#FF6A3D` as ink:** measured 1.9:1 on the light map's ground, against the
  vermilion's 2.7:1 on the same frame (VERIFIED, desk). Neither clears 3:1 on both maps in the corner,
  where the film's vignette darkens all chrome; that is in the review as an open question.
- **Pressing in the upper centre:** brighter there (3.1:1 on dark), but on the road it lands on the
  trail and the arriving town's name. Under the pill it stays clear of the car and the trail, though it
  can cover a town name for its beat. Shown in the review.
- **A separate `OverlayContent` case:** it could not know the pill's fitted size, which depends on
  the place beside the day.
- **A stamp for the first day:** nothing turns there, and the title card opens the film.

## Consequences
- New: `DayStampConfig`, `LinearTimelineDayStamp`, `RecapStyleDayStamp`, `RecapOverlayDayStampDrawing`;
  `.hud` gains `dayStamp` (nil leaves the HUD drawn exactly as before).
- Hand-built test configs default to `.off`, so the films pinned before the stamp keep their frames.
- Review: `Docs/design-reviews/2026-10-28-day-stamp.md`; renders in `~/Kamome-films/2026-10-28-day-stamp/`.
