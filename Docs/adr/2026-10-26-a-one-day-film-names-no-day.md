# A one-day film names no day

**Status:** Decided (Chiu, 2026-10-26)
**Supersedes:** nothing. Narrows the HUD's day (Chiu 2026-07-31) to films of two or more days

## Context
The first-time-user walk (#295 item 6, 2026-10-10) watched the sample film: every
stop chip read 「第 1 天」 from 4 s to 52 s.
- VERIFIED (source): the day is the HUD pill's first half, `RecapTrip.Stop.dayLabel`,
  made by `RecapComposer.dayLabel` from `TripClock` (ADR 2026-10-01).
- VERIFIED (source): the HUD already drops an empty day
  (`RecapOverlayHUDDrawing.swift`), so the pill names only the place, or is not drawn.

## Decision
Chiu, on #295, 2026-10-26: *"(6) a one-day film shows no 「第 N 天」"*.
- A film whose trip covers one day sets every stop's day to `""`.
- One day is `RecapComposer.dayCount(trip:clock:)`: the end card's DAYS figure,
  counted by the same clock as the chip. That clock uses local dates in each stop's
  own zone (ADR 2026-10-01). So "1 DAY" on the card and no day in the pill always
  come together, and there is no second rule.
- Two days or more: each stop keeps its Day N, unchanged.
- The end card is untouched (#287 stays as it is).

## Rejected
- **Counting the film's own stops instead of the trip:** that would be a second
  day rule beside the card's. A two-day trip whose film kept only day-one stops
  would name no day under a card that says 2 DAYS.
- **Hiding it in the renderer when every label is equal:** that puts a story
  decision into rendering (CHARTER §3).
- **An optional `dayLabel`:** a public interface change, for a meaning that `""`
  already has where the label is drawn.

## Consequences
- `RecapComposerDayLabelTests` pins it in both directions, in a zone that is
  neither UTC nor UTC+8.
- The bundled sample films were re-rendered (`Scripts/encode-sample-film.sh`).
  Their stops carry no town, so on the road the pill is now gone entirely.
  VERIFIED on both files, every 2 s.
- No config, schema or string change.
