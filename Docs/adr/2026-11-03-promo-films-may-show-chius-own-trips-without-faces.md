# Promo films may show Chiu's own trips, from photos with no face in them

**Status:** Decided (Chiu, 2026-11-03)
**Supersedes:** nothing. §0 lists "one user-initiated share of one trip"; publishing a trip as marketing was never decided.

## Context
- Chiu wants marketing, demo and promotion videos made at the desk. Their footage is Kamome's own films and screen captures; App Store previews may show only captures of the app (Apple's App Review Guidelines 2.3.4). VERIFIED that the guideline says this; not tested against App Review.
- A film of a real trip shows where a real person went, and the stop photos can show other people. Neither is a §0 exception today.
- VERIFIED (2026-11-03, desk): Apple Vision (`VNDetectFaceRectanglesRequest`) runs on this Mac and passed 4 face-free images. UNKNOWN: how many faces it misses in real trip photos (profiles, far away, in shadow). The cheapest check is to run `Tools/face-free-photos.swift` on one trip and look through what it keeps.

## Decision
Chiu 2026-11-03: *其實我覺得可以做真實旅程 但你要幫我幫人臉的照片過濾掉 只要沒有人臉照片我的旅程拿來分享應該不錯*.
- A promo film may show one of **Chiu's own** trips. The film is built only from photos with no detected face: `Tools/face-free-photos.swift` copies the face-free ones, and the fixture is made from that copy so no stop borrows another stop's photo.
- Chiu looks through every kept photo before anything is published. The detector is a filter, not a guarantee.
- No other user's trip, ever. No AI-generated scenery (Chiu 2026-11-03: *我不用AI做風景鏡頭 可以拿我自己的照片*). AI is used only where the app's own pictures cannot do the job, it runs on this Mac, and it is never presented as the app's output.
- Every tool runs on this Mac (`Tools/kamome-promo.sh`). Trip photos, fixtures and props files stay under `~/Kamome-promo/` and `Tests/Fixtures/trips/local/`, never in the repository.

## Rejected
- Synthetic demo trip only: safest, but Chiu prefers a real trip.
- A cloud video model for scenery: Chiu declined it, and it would send trip photos off the Mac.

## Consequences
- New desk tools: `Tools/kamome-promo.sh`, `Tools/face-free-photos.swift`, `Tools/promo/` (a Remotion template). No app code changes.
- Owed by Chiu before each publish: a look through the kept photos, and stripping EXIF from any still published on its own.
