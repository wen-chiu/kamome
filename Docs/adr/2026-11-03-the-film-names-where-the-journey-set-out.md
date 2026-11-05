# The film names where the journey set out, over the opening, when it does not stop there

**Status:** Decided (Chiu, 2026-11-03)
**Supersedes:** nothing. It adds to ADR 2026-10-02-the-film-names-the-trips-own-towns and leaves Chiu's 2026-10-29 rule in #337 as it stands: town names stay on the map from the opening.

## Context
- Chiu, from a short film of a photo-imported trip: the opening reads as if the trip set out from a town it only reaches at the end. He called it a bug.
- VERIFIED from the exported MP4: the car waits at the start for about 3 s with nothing marking it. The only place named in the frame is a town where a later stop is (ADR 2026-10-02 names every stop's town from the opening). The HUD pill gave the **first held stop's** day and town (「第 2 天 · …」) before the car had moved.
- VERIFIED at the desk on the same photographs: the highlight cut drops the trip's first stop (two photographs), so the film's first stop is a day later and about 110 km away. `LinearTimeline.dayLabel` was documented as "before the first stop the trip is on its first day", but it read the first *film* stop.
- The same film's trail also begins on water (#362). That is a separate cause, still UNKNOWN, and this decision does not move it.

## Decision
Chiu 2026-11-03, choosing among a label over the opening, the departure's town kept on the map all film, or both: *開場標出發點*.
- `RecapTrip.departure` is the trip's first stop when the film does not hold it. The composer sets it; a film that holds its first stop has none, because that stop names itself.
- Over the opening, the departure gets a quiet stop's label: the same pin and name drawing. It rises as the car fades in and falls over `deck_zoom_s` once the car sets off. No pause, no new tunable, and the film's length is unchanged.
- Until the first stop, the HUD gives the departure's day and town, never the first held stop's.
- **The car waits right at the pin and is never hidden by it** (Chiu 2026-11-04: 「車子應該更靠近…可以重疊一點只要點還看得見」, 「car should be on the top of the spot」). The car is drawn just below the pin's dot, overlapping only its white ring, and slides back onto its road as it sets off. Stop pins and the towns' dots and names now draw **under** the car everywhere in the film; photo cards and the HUD stay over it.
- No label when a stop is held at the start, on a route-only film (no stop labels at all), or on a type-2 film, whose departure airport is never named (ADR 2026-09-05 (c)).

## Rejected
- **The departure's town on the map all film:** it adds a name to every frame and changes which names survive overlap (ADR 2026-10-02 §3).
- **Take the later town's name off until it is reached:** Chiu ruled on 2026-10-29 that names stay from the opening.

## Consequences
- `Core/ExportEngine/LinearTimelineDeparture.swift`; `RecapTrip.departure`; `RecapComposer.trip`; `SubjectState.pinToClear`; `VehicleSubjectRenderer.clearing` (placed by the art's own opaque rows, not its canvas); `FrameCompositor.drawsBelowSubject`.
- Held by `LinearTimelineDepartureTests` (6), `SubjectPinClearanceTests` (5) and `FilmLengthExportTests.testAFilmThatDropsTheFirstStopCarriesItAsTheDeparture`.
- Films already made do not change. #362 (the trail beginning on water) stays open and needs the phone's record of that trip.
