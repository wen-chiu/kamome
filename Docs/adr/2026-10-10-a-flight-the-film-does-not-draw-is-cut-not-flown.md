# A flight the film does not draw is cut, not flown

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** nothing — carries out ledger entry "2026-09-01" Option 1 ("cuts straight into the local trip") for the frozen-card form, keeping "2026-09-02"'s departure photographs

## Context
Past `crossing_flight_max_longitude_deg` (70°) a type-2 film opens on a frozen
card instead of drawing its flight (`CrossingFraming`). The trim still kept the
departure stop and the crossing, so the film swept from the destination's frame
back to the departure airport, flew a 7,300 km arc mid-film with the seagull,
and ended on a 22,000 km reveal re-centred on the equator, at 4.5 snapshot
stations a second against ≤1.9 for every other shape (VERIFIED, desk,
`ExportQualityMatrixTests`, #275).

## Decision
Chiu: option 2 of #275, now; a long-haul pass and plane later. Its shape:
title card over the destination's frozen frame; then the departure airport's
photographs (capped at `departure_stop_max_photos`) on a card over **the same
frame** — no camera move, no pin, no name; then the camera closes into the
destination. The camera, the route and the end reveal hold the destination
alone. The frozen frame is held for `title_card_s` plus the departure stop's own
priced hold, so the film's length plan is unchanged.

## Rejected
- Option 1, the departure photographs dropped: they are where the trip began
  (2026-09-02).
- A hard cut to the departure airport's own map for its photographs: two cuts
  and one more snapshot for a place the film then leaves.

## Consequences
- `LinearTimelineDepartureCut`; `RecapPhotoDeck.coordinate` is optional (nil:
  no pin, card centred); `export` gains the copy `withTitleCardS`.
- A stop between the departure and the landing (a photograph from the air) is
  not shown in this form.
- Measured on the matrix: 312 → 84 stations for a 63 s long-haul film.
- Open for a later round (Chiu): the boarding pass and its aircraft over the
  frozen card — the pass needs no map frame (#275).
