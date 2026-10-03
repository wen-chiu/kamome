# The film button waits only for the stops the film shows, and a failed lookup is asked once more

**Status:** Decided (Chiu, 2026-10-01)
**Supersedes:** nothing. It narrows the gate of ledger 2026-08-04 (the film button is off while stops are named) from the whole trip to the film's stops.

## Context
From the smoothness audit of 2026-10-01 (#160).

- VERIFIED (source, config): the film button was off while **any** stop in the
  trip was unnamed. Naming asks one stop every `geocode.min_interval_s` (2 s),
  so 26 stops waited about 52 s and 45 stops about 90 s, plus Apple's replies.
- VERIFIED (source): the film uses only the names of the stops it shows
  (`RecapComposer` builds its stops from the deck plan), 8–21 by trip size.
- VERIFIED (source): a failed lookup marked the stop finished and unnamed, so
  the film said "Unnamed stop" unless the trip was opened again.

## Decision
Chiu, 2026-10-01, on #160: 「好」 to waiting only for the film's stops, and
「允許每站重試一次」.

1. **The stops a film shows are named first, and the film button waits only
   for them.** "A film" is either length: the length is chosen after the
   button, on the export sheet. The rest of the trip is named behind them, and
   Trip Detail's banner keeps counting every stop.
2. **A stop whose lookup failed is asked once more**, after every other stop,
   through the same throttle. A second failure is final.
3. *(eng)* **The export sheet's Export button waits for a stop the person puts
   into the film while it is still unnamed**, and that stop is named next.
   Without it, item 1 would let "Unnamed stop" into a film from the sheet.

## Rejected
- Lowering `min_interval_s`: Apple publishes no limit; it needs a phone
  measurement first. Not decided, not built.
- Naming a recorded trip before it is first opened: timing of what is sent to
  Apple is a product decision (ADR 2026-09-17). Not decided, not built.

## Consequences
- `StopNamer.prioritise`, `pendingNameIds`, one retry; `StopNamingCoordinator`
  `start(first:)`, `isNaming(_:anyOf:)`, `nameFirst`; `TripDetailModel`
  `filmStopIds`, `isNamingFilmStops` (Trip Detail and the diary).
- Restated by Chiu's word: `testAFailedLookupStillCostsTheThrottle` now counts
  six lookups for five stops; its spacing assertion covers all six. Its other
  property, "a failed stop is finished, not pending", moved to
  `testAStopThatFailsTwiceIsFinishedAndUnnamed`.
- INFERRED, accepted with the decision: day counting (`TripClock`) reads every
  stop's time zone, so on a trip that crosses zones a stop not yet named could
  move a "Day N" label in a film exported early. Cheapest check: export a
  two-zone trip the moment the button comes on.
- UNKNOWN on a phone: the wait itself. Runbook D2's export is the check.
