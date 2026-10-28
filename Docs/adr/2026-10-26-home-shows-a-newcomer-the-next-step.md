# An empty 旅程 offers 足跡's 「找出我的旅程」, a short one offers the next step, and a trip with a film says so

**Status:** Decided (Chiu, 2026-10-26; amended by Chiu's review, 2026-10-27)
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

**Chiu 2026-10-27 review** (PR #320, from its screenshots; four changes, all approved):
1. The film mark is a state, not a control. The teal glyph read as "make a film here".
2. The next step is a card you can press, not a footnote that explains. **Home's new path to a trip's film sheet is approved.**
3. On an empty 旅程, the manual route steps down below the sample.
4. The gull beats its wings once as it appears. Standing still, the double arc reads as an "m".

What is built:
- **Empty 旅程** reads in three levels: `WelcomeCard` (the same view 足跡 shows), with 「找出我的旅程」 as the one filled button; then 「先看一支範例影片」; then 「或手動加入」 over two small bordered buttons, 「從照片匯入」｜「記錄旅程」. They stack when a large text size leaves no room. From the first trip, the foot is as before: filled import, bordered record.
- **「找出我的旅程」 in 旅程** switches to 足跡 and asks for Photos there, in one tap (`JourneyDiscoveryModel.findJourneys()`). Before 足跡 is shown, its first look asks; once shown, it asks only if nobody has answered. The library is asked for once and scanned once (tests). §0 is unchanged: nothing is read until the person presses it or opens 足跡.
- **The next step:** under 1 to `home.next_step_max_trips` trips, one compact card with a bordered button. Import stays the one filled button (§7 rule ①).
  - The newest finished trip without a film gets 「把「<name>」做成旅程影片」 and 「製作旅程影片」. The name is the row's own (`HomeTripRow.headline`).
  - The button pushes Trip Detail with its film sheet open (`HomeRoute.tripMakingFilm`). That is Trip Detail's own sheet, opened when its button could be pressed (`canMakeFilm`, which waits for the film's stops to be named, #160). One film at a time stays `RecapExportCoordinator`'s.
  - Otherwise: the gull, 「你的照片裡，還有更多旅程。」 and 「找出更多旅程」, which does what the welcome card's button does.
  - Unlike the welcome card, these cards sit on white with a hairline in light mode. A bordered label on its grey is 4.21 : 1 (ADR 2026-10-26-text-and-controls-take-a-deeper-teal).
- **The film mark** ends the figures line in its grey: 「· 已有影片」. It stacks with that line at a large size (#191). VoiceOver says 「已有旅程影片」. It is never on the cover (`CHARTER.md` §7, rule ④).
- **The gull:** `KamomeGull` draws `GullPose`, the brand double arc, in `BrandTeal`. On appear it beats once, over one `GullPose.beatS` (0.8 s, the wait's own beat), and rests in the brand pose. With Reduce Motion it never moves. `VehicleMarker.seagull` is not touched. The recording HUD's head marker is still `bird.fill`.

## Rejected
- Opening 足跡 on first launch while 旅程 is empty (#290 option 2): not chosen, and every launch opens on 旅程 (ADR 2026-09-30-footprints-sits-beside-journeys).
- A card button that only switches segment: the person would press 「找出我的旅程」 twice.
- A one-line hint (this PR's first round): it explained instead of doing (§7 ③).
- The film glyph by the chevron (first round): it read as a control.
- Opening the film sheet from Home in a new component: Trip Detail's sheet, with its gate, is the one path.

## Consequences
- **Copy is draft, and Chiu finalises it:** `home_trip_film_made`, `home_trip_has_film`, `home_next_film_card`, `home_next_find_title`, `home_next_find_action`, `home_manual_title`, `home_manual_import`, `home_manual_record`. Retired: `empty_state_pitch` and `empty_state_import_hint`, and the first round's `home_next_make_film` and `home_next_find_journeys`.
- `home.next_step_max_trips` = 3, INFERRED. One row is about 70 pt of the ~570 pt above the buttons, so three fill about a third. A two- or three-trip Home on the phone settles it.
- Tests: `HomeNextStepTests`, `JourneyDiscoveryModelTests+Find`.
- Screenshots in the PR. The App Store note A4 ("tap *See a sample film first*") stays true.
