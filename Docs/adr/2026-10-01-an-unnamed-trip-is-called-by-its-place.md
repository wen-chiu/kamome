# A trip nobody named is called by its place on every screen: flag and town, region, or country

**Status:** Decided (Chiu, 2026-10-01)
**Supersedes:** nothing in the ledger. It replaces the rule in `TripTitle`'s own comment (Chiu 2026-09-22 and 2026-09-27: flag + country), which no ADR recorded.

## Context

Found while preparing Journey Discovery to leave beta (#164, #165, #166).

- VERIFIED (source): a journey opened from Discovery stored the card's headline
  as the trip's title. Before the place lookup answered, that was the month
  ("September 2026"). `TripTitle.isFallback` did not recognise it, so the trip
  kept it for good.
- VERIFIED (source): the screens disagreed about an unnamed trip. Home and the
  film said flag + country. The Discovery list and the diary used
  `JourneyNaming` (town, region or country). Trip Detail's bar showed the
  stored title, which is the start date.
- VERIFIED (source): the Discovery list drew the geocoded place over a trip's
  real name.

## Decision

Chiu, 2026-10-01: 「『新增旅程』前如果地名還沒查到 可以先用國家名 但如果有查到
我還是想要國家旗幟加城鎮名」, and for a wide trip at home, of three options:
「全部顯示縣市」.

- **A real name always wins**: an album's, or one the person typed. This now
  holds on the Discovery list too.
- **A trip nobody named is called by `JourneyNaming`'s rule, with its flag, on
  Home, Trip Detail, the Discovery list, the diary and the film:**
  - it stayed in one place (`discovery.single_place_extent_m`): flag + town;
  - wider, at home: flag + region (「🇹🇼 花蓮縣」);
  - wider, abroad: flag + country.
- **A trip made from Discovery is stored unnamed**, like one from the import
  sheet. Its place is looked up at the tap, ahead of the queue, and the lookup
  finishes even if the screen closes. It is the same single lookup of the
  journey's busiest stop that the queue would have made (§0 unchanged).
- **A trip already stored under its month title counts as unnamed**, so it is
  named by its place after all.
- **A failed open says why** in an alert.

*(eng)* Whether a trip stayed in one place is recorded beside the cached place
(`JourneyNameCache`, a set of trip keys in `UserDefaults`). It is written at
creation and each time Trip Detail reads the trip, because merges and stop
deletions happen there. Home's row holds only the trip record, and a read per
row was the alternative.

## Rejected

- Storing the resolved name as the title: it freezes the language and the
  moment, and the flag is not part of it.
- Country for every wide trip: Chiu chose the region at home.
- Leaving each screen its own rule: one trip, three names.

## Consequences

- **Behaviour that changes for trips already on a phone:**
  - an unnamed wide trip at home reads 「🇹🇼 縣市」 on Home and in the film,
    where it read 「🇹🇼 台灣」;
  - an unnamed one-town trip reads flag + town once Trip Detail has opened it
    (the record is written there for trips made before this);
  - Trip Detail's bar shows the place instead of the start date.
- **INFERRED: the region is one stop's region.** A trip round the island is
  named after the county of its busiest stop (Discovery) or its first stop (the
  import sheet, `TripJourneyNaming`). Cheapest check: Chiu reads his own Home
  list after this lands.
- **Not built: the country before any lookup answers.** Until the lookup
  answers, the title is the start date, as for every unnamed trip. The lookup
  is one request sent at the tap, so the wait is normally about a second.
  Showing a country offline needs the bundled outlines to yield a displayable
  country: an alpha-3 → alpha-2 table, and a new use of codes that
  `CountryBoundaries` says are "never shown". Tracked in #165.
- **Copy is draft:** `journey_open_failed`, `journey_open_failed_not_a_trip`.
- **UNKNOWN whether `notATrip` can happen from Discovery.** A nine-photo
  journey in one place imported in the test. The store refusing a trip is the
  failure the test exercises.
- **Tests:** `TripTitleTests` (the three shapes, the month title, the record),
  `JourneyDiscoveryModelTests` (a real name wins; opened before its name is
  known; a refused save says so). One assertion is restated, not removed:
  `testOpeningAJourneyImportsItOnceAndFindsItAgain` pinned the card's name
  being copied into `trip.title`; it now pins the fallback title and
  「🇯🇵 Japan」 through `TripTitle`.
- #168 (the fallback title breaks on a language change) is untouched and now
  also applies to the month title.
