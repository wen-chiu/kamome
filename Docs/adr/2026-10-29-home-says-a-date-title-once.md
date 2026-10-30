# Home says a trip's date once when the date is its title

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** nothing. It narrows the facts line of ADR 2026-10-07-home-reads-like-footprints for one case; the trip-title rule (2026-10-01) is unchanged.

## Context
- VERIFIED (#331, simulator, Release 1.0.0 (928), 2026-10-28; again on Debug `main`, 2026-10-29): a recording with no stop has no place to be named by, so Home titles it by its dates (`HomeTripRow.headline` falls back to `dateRangeText`). The line under the title always starts with the dates: 「Oct 28, 2026」 over 「Oct 28, 2026 · 4 km · 0 places」.
- The fallback title itself looks intended and is not changed here. Whether a stop-less recording should be named from its route instead is a separate question, not asked.

## Decision
Chiu 2026-10-29, choosing between dropping the repeated date and leaving it: *省略重複的日期*.
- When the headline is the dates, the facts line leaves them out: 「5 km · 0 places」. VoiceOver says the dates once too.
- A trip with a name or a place keeps its dates on the line, as before.

## Rejected
- **Leave it.** The row says the same thing twice in its first two lines.
- **Name a stop-less recording from its route.** That changes the title rule, which is a larger decision than #331.

## Consequences
- `HomeTripRow.factsDates(headline:dates:)`; held by `TripTitleTests.testATripTitledByItsDatesDoesNotSayThemTwice`, which fails with the date always kept (watched red).
- The next-step card's 「Turn "Oct 28, 2026" into a film」 still names the trip by its title, unchanged.
