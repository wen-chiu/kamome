# An empty 旅程 offers 足跡's 「找出我的旅程」, a short one says the next step, and a trip with a film is marked

**Status:** Decided (Chiu, 2026-10-26)
**Supersedes:** ADR 2026-09-28-sample-trip, "Entry", in part: import is no longer the empty Home's hero (the sample button stays)

## Context
The first-time-user walk of 2026-10-10 (#290, #295), VERIFIED on the simulator:
- Kamome finds journeys by itself only from 足跡, the second segment. 旅程, where every launch opens, offered import alone.
- With one trip, Home was mostly blank, and nothing said what to do next. That is the screen after the sample, which hides the empty state.
- A trip with a film looked the same in the list as one without.
- 足跡's welcome bird was SF Symbols' `bird`, a songbird, not the gull of the icon and the export's wait. In code that gull is `GullPose` (`ExportGullView.swift`); `KamomeGull` was the songbird.
- The privacy note under 「找出我的旅程」 was tertiary, the faintest text in the app.

## Decision
Chiu, 2026-10-26, on #290: 「選項 1」: 旅程's empty state carries 足跡's welcome card with 「找出我的旅程」, and import stays the manual route. On #295, items 1–4: a next-step hint when Home has few trips; a film mark; the welcome bird becomes `KamomeGull` without restyling `VehicleMarker.seagull`; the privacy note in secondary.
- **Empty 旅程** shows `WelcomeCard`, the same view 足跡 shows, then 「先看一支範例影片」. 「找出我的旅程」 is the screen's one filled button. Import and record sit at the foot as a bordered pair, and import is filled again from the first trip *(design)*.
- **「找出我的旅程」 in 旅程** switches to 足跡 and asks for Photos there, in one tap (`JourneyDiscoveryModel.findJourneys()`). If 足跡 has not been shown yet, its first look asks; if it has and nobody has answered, it asks now; once answered, it does nothing. The library is asked for once and scanned once (tests). §0 is unchanged: nothing is read or looked up until the person presses it or opens 足跡.
- **The next step:** under a list of 1 to `home.next_step_max_trips` trips, one footnote line. If any finished trip has no film: 「打開一趟旅程，就能製作旅程影片。」. Otherwise: 「從照片找出更多旅程」, which does what the card's button does.
- **The film mark** is the `film` glyph (that of 「製作旅程影片」) in the accent, at the end of the trip's name. VoiceOver says 「已有旅程影片」. It is never put on the cover (`CHARTER.md` §7, rule ④).
- **The gull:** `KamomeGull` draws `GullPose` at rest, the brand double arc, in `BrandTeal`, on all three 足跡 cards. `VehicleMarker.seagull` is not touched. The recording HUD's head marker is still `bird.fill`.

## Rejected
- Opening 足跡 on first launch while 旅程 is empty (#290 option 2): not chosen, and every launch opens on 旅程 (ADR 2026-09-30-footprints-sits-beside-journeys).
- Import kept filled under the card: two filled buttons on one screen (§7 rule ①).
- A card button that only switches segment: the person would press 「找出我的旅程」 twice.
- The hint on every list: past a few rows the list fills the screen and says enough.

## Consequences
- **Copy is draft, and Chiu finalises it:** `home_next_make_film`, `home_next_find_journeys`, `home_trip_has_film`. `empty_state_pitch` and `empty_state_import_hint` are retired.
- `home.next_step_max_trips` = 3, INFERRED. On an iPhone 17 Pro, one row takes about 70 pt of the ~570 pt above the buttons (read off the screenshot), so three fill about a third. Chiu's look at a two- or three-trip Home on the phone settles it.
- Tests: `HomeNextStepTests`, `JourneyDiscoveryModelTests+Find`.
- Screenshots in the PR. The App Store note A4 ("tap *See a sample film first*") stays true.
