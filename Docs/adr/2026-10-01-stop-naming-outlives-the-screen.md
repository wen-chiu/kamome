# Stop naming outlives the screen, and every Apple lookup shares one throttle

**Status:** Decided (Chiu, 2026-10-01)
**Supersedes:** nothing (it changes who owns the naming of ledger 2026-08-04, not what it does)

## Context

Issue #159, from the 2026-10-01 smoothness audit.

- `StopNamer` was owned by `TripDetailModel`. Leaving Trip Detail dropped its
  queue, and reopening started the wait again (VERIFIED, source).
- Three callers used Apple's geocoder and each throttled only itself:
  `StopNamer`, Journey Discovery's card naming, and `TripJourneyNaming`
  (VERIFIED, source). Opening a journey from Discovery ran two of them at once,
  up to about one lookup a second against `geocode.min_interval_s` = 2.
- Apple rate-limits per app and does not publish the limit. INFERRED: a refused
  lookup is what puts "Unnamed stop" in a film. UNKNOWN on a phone; settled by
  searching the diagnostics for `stop naming failed` after opening a 20+ stop
  journey from Discovery.

## Decision

Chiu, 2026-10-01: 「好 先做159」.

1. **`StopNamingCoordinator` owns naming**, one run per trip, the shape
   `RouteMatchCoordinator` has. A screen asks; the run carries on when the
   screen goes; a screen that opens mid-run joins it and hears its progress.
2. **`GeocodeGate` is the one door to Apple's geocoder.** One lookup at a time,
   the next no sooner than `geocode.min_interval_s` after the last finished,
   whoever asks. Stop names go first, then a new trip's flag, then Discovery's
   cards. Two asks for one coordinate that wait together are one request.
3. **What is sent, to whom and what starts it are unchanged** (§0). The same
   stop points go to Apple, started by the same screens. They may now be sent
   after the screen has closed. Deleting the trip stops the run
   (`TripDeletion`). The gate holds coordinates in memory while they wait and
   never logs them.

## Rejected

- **Sharing one `GeocodePolicy` between the callers.** It would share the clock
  but not the order: stop names would take turns with cards.
- **A retry for a stop whose lookup failed.** Proposed in #159 and left out:
  `StopNamerTests.testAFailedLookupStillCostsTheThrottle` pins "a failed stop is
  finished, not pending", so a retry restates a test and needs Chiu's word.
- **Starting naming when the trip is created.** A timing decision, #160.

## Consequences

- New: `App/Services/GeocodeGate.swift`, `StopNamingCoordinator.swift`.
  `CLGeocoderStopGeocoder` and `CLPlaceGeocoder` go through the gate.
  `StopGeocoding.pacesItself` tells `StopNamer` the gate does the waiting, so a
  stub in a test is still throttled by `StopNamer` itself.
- No config key added or changed. No pixel changes.
- Owed: the phone check above (#112), and Chiu's word on the retry (#160).
