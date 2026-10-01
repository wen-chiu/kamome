# A stop's time is the clock where it happened, not the phone's

**Status:** Decided (Chiu, 2026-10-01)
**Supersedes:** nothing (it extends ledger entry "2026-09-26" from the date to the hour)

## Context

Chiu's New Zealand import, read back in Taipei: Trip Detail listed a lakeside
morning stop at 03:23. The day chip above it was already the local date
(`TripClock`, ledger 2026-09-26); the hour beside it was not.

- VERIFIED (source): a stop's time was drawn by `Text(date, style: .time)` in
  two places — Trip Detail's list and the Journey Diary's stop row — which
  formats in the phone's current zone.
- VERIFIED (source): nothing else in the app or the film prints an hour of the
  trip. The film draws `Day N`, DAYS and boarding-pass dates, all through
  `TripClock` already.
- Each stop already stores the zone its naming lookup reported (schema v14
  `stop.time_zone`), so nothing new is asked and nothing new leaves the phone.

## Decision

Chiu, 2026-10-01: *"跨時區的照片 我認為應該要計算顯示出當地時間才有旅行回憶的意義"* —
a photograph from another zone shows the local time there; that is what makes
it a memory.

1. A stop's time is hour and minute **in the zone the stop happened in**
   (`TripClock.timeText(at:)`), in the device's own 12/24-hour style.
2. The zone is `TripClock.zone(at:)`, unchanged: the stop's own, else the stop
   nearest in time, else the phone's. One rule for the date and the hour, so a
   row can never disagree with its day chip.
3. Both screens read it through `TripDetailModel.arrivalTime(of:)`.

## Rejected

- **A zone suffix ("08:23 GMT+13"):** utility, not memory; the traveller knows
  where they were. Reopen if a trip across several zones reads as confusing.
- **Both clocks ("08:23 · 03:23 at home"):** the home hour is the number that
  was wrong.
- **The photograph's own EXIF offset:** not stored, absent on older and edited
  photographs, and it would give the hour a second source the date does not use.

## Consequences

- No schema, config or string change. `TripClockTests`, `TripDetailDaysTests`
  and `StopNamerTimeZoneTests` pin it.
- VERIFIED (simulator, 2026-10-01, the seeded Western Australia trip with the
  phone's zone set to New York): the rows read 7:27 PM … 12:00 AM, Perth's
  clock, where the phone's own gave 7:27 AM … 12:00 PM.
- VERIFIED (same run): a trip named before schema v14 got its zones on first
  open and the screen never read them — hours and day chips stayed the phone's
  until it was opened again. `StopNamer.fillMissingLocalities` now reports each
  one that lands and Trip Detail reloads. The fix itself has a test, not a render.
- INFERRED: while a fresh import is being named (~2 s a stop), a row shows the
  phone's hour until its zone lands, as the day chips do. Settled on the phone.
- UNKNOWN: how Chiu's New Zealand trip reads on his phone. Settled by opening
  it on a build of this PR (#112's run, or TestFlight).
- Still in the phone's zone, and not hours: the trip's date range on Home, in
  the merge sheet, and on the film's title card — #171.
