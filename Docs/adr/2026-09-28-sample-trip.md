# An empty Home offers a sample trip: Hualien to Taitung, with drawings for photographs

**Status:** Decided (Chiu, 2026-09-28)
**Supersedes:** nothing

## Context

A new user, and an App Store reviewer, open Kamome with no trips. The
reviewer's phone has no geotagged photographs, and `DemoSeeder` is DEBUG-only,
so nobody sees a film until they have imported something
(release review 2026-09-28, A4, #126). Chiu chose, from three options each:
- the photo cards show **Kamome hand-drawn illustrations**;
- the route is **a stretch of Taiwan's coast**;
- the sample appears **behind a button on the empty Home**, never automatically.

## Decision

- **Entry.** While Home is empty, below the import pitch, a quiet
  `sample_open_action` link creates the sample and opens it. Import stays the
  hero. The sample is a trip like any other and can be deleted. It is created
  again only if Home is empty again.
- **What it is.** Five public places on the Hualien–Taitung coast (七星潭, 石梯坪,
  三仙台, 都蘭, 鐵花村), on one fixed day, 2025-11-15, in Asia/Taipei. Two drawings
  per stop. Stop names come from the manifest, in the app's language, and are
  never geocoded.
- **The road ships with the app.** Each leg is stored as `matched_polyline` with
  routability `road`, so routing never asks about it, no request goes to the
  relay, and no quota is spent.
  - VERIFIED on the iOS 17.5 simulator: the export log reads
    `0/4 legs routable … 0 never asked`.
  - The geometry is OpenStreetMap data (ODbL), routed once through the public
    OSRM demo server. It is **not** a Geoapify result, because Geoapify's terms
    say nothing about redistributing results (checked 2026-09-28).
- **Honest provenance.** The trip source is `TripSource.sample` and each leg is
  `SegmentSource.sample`.
  - Its label is **"Sample / 範例"** (Home's mark and Trip Detail's chip), never
    "From photos".
  - `isReconstructed` stays true, so nothing treats it as a recording.
- **Nothing that works over the person's trips touches it.**
  - Excluded: Discovery, merge (both directions), photo matching (including the
    limited-library re-match), and photo analysis.
- **Drawings.** Photo ids use the `kamome-sample/` prefix. They resolve to bundled
  PNGs in the two places an id becomes pixels, and nowhere else:
  `PhotoLibraryPhotoResolver` (the film) and `PhotoThumbnail` (every screen).

## Rejected

- Created on first launch: a trip the person did not ask for, mixed in with their own.
- Routed on first export: about 4 relay requests per install, against a shared
  2,000/day ceiling (A5), and no film offline.
- Shipping the Geoapify geometry: redistribution rights UNKNOWN.
- Chiu's own photographs: the repository is public.
- No photos: hides the product's core, photographs becoming a film.

## Consequences

- **The drawings are PLACEHOLDERS** (`Scripts/draw-sample-placeholders.swift`),
  until the real ones land (#134).
- **Copy is draft:** `sample_open_action`, `sample_badge`, `sample_note`,
  `sample_failed` (en and zh-Hant). The final wording is Chiu's.
- **The App Store review notes (A4) can now say:** "tap *See a sample film
  first*".
- **Tests:** `SampleTripTests` and `JourneyDiscoveryModelTests.testTheSampleTripIsNeverAJourney`.
- **Rendered:** a 60 s film on the iOS 17.5 simulator, in 148 s (simulator
  time). The frames show the title card, the drawings and a solid coast road.
  The film is at `~/Kamome-films/2026-09-28-sample-trip/`.

## Addendum — 2026-09-29 (Chiu)

- **The drawings are Chiu's.** Eight illustrations replace the placeholders,
  two each for 七星潭, 石梯坪, 三仙台 and 都蘭, at 543×724 (3:4).
  - `Scripts/draw-sample-placeholders.swift` is deleted.
  - The originals are kept outside the repository.
- **鐵花村 is a stop with no drawing** (「鐵花村就只有停留點不要放照片」). The
  sample now has 8 drawings for 5 stops, pinned by
  `SampleTripTests.testTiehuaIsTheOneStopWithoutADrawing`.
- **VERIFIED from a render**: 543 px is enough. On the iOS 17.5 simulator, the
  三仙台 card at 36 s is sharp at full 1080×1920: the railing, the waves and the
  bird's outline are all clean. The four stops show their cards, and the film
  reaches 鐵花村 without one. The end card reads 179 KM · 1 DAY · 5 STOPS. The
  film is at `~/Kamome-films/2026-09-29-sample-illustrations/`.
