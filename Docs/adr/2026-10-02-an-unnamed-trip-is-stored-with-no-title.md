# A trip nobody named is stored with an empty title

**Status:** Decided (Chiu, 2026-10-02)
**Supersedes:** nothing. It amends one line of 2026-10-01-an-unnamed-trip-is-called-by-its-place ("until the lookup answers, the title is the start date"): the date is still what is shown, but it is no longer what is stored.

## Context
- VERIFIED (source, #168): an unnamed trip's stored title was its start date
  as a string, written in the language and time zone of the moment.
  `TripTitle.isFallback` rebuilt that string in **today's** language and
  compared.
- VERIFIED (render, #168 comment 2026-10-02): a trip imported under English
  and opened under zh-Hant was titled `Sep 30, 2026` on Home. The old date had
  become a name, so the place never showed.
- VERIFIED (render, #177): the rename dialog opened on that date, which no
  screen shows, and typing added to it.
- Once a version is on the App Store, whatever shape is stored is on other
  people's phones for good. That is why this is settled before submission.

## Decision
Chiu 2026-10-02, shown three options: 「未命名 = 空標題」.

- **"Nobody named this" is an empty `trip.title`.** Import, Discovery and a
  recording all store it. No schema change: the column stays `NOT NULL`.
- **Every screen and the film go through `TripTitle`.** An unnamed trip is
  called by its place; with no place, by its start date in today's language.
  No screen prints the blank.
- **Titles already stored as a date are recognised and rewritten at launch**:
  the start date in either shipped language (with and without the phone's
  region), or a day either side for a phone that has changed time zone; and
  the month title on a Discovery trip, as before.
- **The rename field starts empty for an unnamed trip**, with the name the
  screen shows as its placeholder (#177).

## Rejected
- A flag column: clearest, but a migration and a wider `TripRecord` for a fact
  an empty string already states.
- Comparing against every shipped language's date and storing nothing new:
  the smallest change, and it still breaks on a region format or a time zone.

## Consequences
- `TripTitle.unnamed`, `isLegacyFallback`, `clearLegacyFallbacks` (called from
  `TrackingSession.init`), `plain`. `setTripTitle` may now be passed `""`.
- INFERRED: a date title written under a region format outside en / zh-Hant ×
  the phone's current region is not recognised and stays a name. Only
  TestFlight builds have written any. Cheapest check: Chiu's own Home list.
- Restated, not removed (Chiu's decision above): `ImportTitleTests` and
  `JourneyDiscoveryModelTests` pinned the stored title as the date string;
  they now pin the empty title and the date as what the trip is called.
- A person cannot yet clear a name to get the place back; renaming to an
  empty string still changes nothing. Not asked for.
- #171 is untouched: the fallback date is still read in the phone's zone.
