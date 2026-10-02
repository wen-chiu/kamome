# Journey Discovery leaves beta as Footprints: an itinerary you read, beside the Journeys you make films from

**Status:** Draft (Chiu's answers 2026-09-30 and 2026-10-01; not built)
**Supersedes:** 2026-09-18 (b) in part (the toolbar button and the sheet), and
2026-09-17's "opening a journey imports it". S1 stays the home.

## Context

Journey Discovery has been a beta behind a toolbar button, presented as a
sheet (2026-09-18 (b)). It has its own list and its own detail, the diary.
Chiu wants it in the released app, and he wants both detail screens kept:
「我認為不用只留一個 可以兩個並存」.

- VERIFIED: the names nearly collide. S1 is 「我的旅程 / My Journeys」
  (`home_title`); the beta is 「你的旅程 / Your Journeys」 (`discovery_title`).
- VERIFIED: today, tapping a found journey **imports it**. The trip is written,
  routing starts, and stops are named. Browsing therefore spends relay
  requests and leaves trips behind.
- VERIFIED: the diary duplicates S3's editing: the stop editor, stop delete,
  the ride, films and the film button.
- VERIFIED: a preview and an import build the same stops. Both go through
  `PhotoImportClusterer.plan` with the same `photo_import` config
  (`ImportService.plan(for:)`, `summary(journey:)`).
- VERIFIED: S3's stop names live only in memory, in the `GeocodePolicy`
  owned by each `TripDetailModel`. A stop's time zone comes from the same
  lookup (`StopNamer`, schema v14).

## Decision

Chiu decided:
- 2026-09-30: 「足跡 Footprints，預設旅程，編輯直接進S3」.
- 2026-10-01: 大標題「足跡」. The diary's action is 「新增旅程 / Create
  Journey」, and export lives only in S3 (「兩邊也不重複」).
- A found journey is **previewed, not saved** (「足跡的行程更重要的是哪些
  時間走過的 itinerary」).
- Delete lives only in Journeys.
- How the data is handled was left to engineering (「你判斷清楚」). Those
  choices are marked *(eng)*.

**Home.** A segmented control, 旅程 | 足跡 / Journeys | Footprints, sits at
`.principal`. It never shares `.topBarTrailing` with the info button: two
trailing items lost that licence button on relaunch (2026-09-02). Journeys is
the default, and the last choice is remembered per device. The beta's toolbar
button and its sheet are removed.

| | 旅程 Journeys (S1 → S3) | 足跡 Footprints (list → diary) |
|---|---|---|
| Holds | stored trips: imported, recorded, the sample | every journey the library shows, stored or only found |
| For | making: import, record, edit, merge, delete, **export** | reading: when you went where, by year |
| Detail | S3, unchanged | the diary, **read-only** |
| Swipe | delete | hide, and only on a found journey |

**The diary is an itinerary.** It shows the masthead (place, dates, days),
then each day, its places with their times and towns, and the photographs
taken there. The transport glyph between places is marked as inferred.

The diary has **no** map, no kilometres, no stop editing, no ride, no films
and no film button. All of those live in S3. Its one action is:
- 「新增旅程 / Create Journey」 on a found journey;
- 「在旅程中打開 / Open in Journeys」 on a stored one.

Both actions switch the control to Journeys and push S3.

**"Kept" means "stored".** Nothing new is added to the schema. A found
journey is drawn as unsaved on the rail.

**Data.** These are engineering choices, made for stability and speed.

1. *(eng)* **One value, two sources.** The diary draws a `JourneyItinerary`
   value, not a `TripDetailModel`. A found journey's itinerary is built from
   its cluster plan. A stored trip's itinerary is built from its stored
   stops, which may have been edited. The stored version always wins for a
   stored trip. S3 and `TripDetailModel` are untouched.
2. *(eng)* **Plan once, off the main actor.** The detached detection task
   computes each journey's cluster plan with the journey itself. The list,
   the preview and the import all reuse that one plan, instead of
   re-clustering on the main actor for every summary.
3. *(eng)* **One lookup per stop, ever.** Opening a preview names its stops
   through the existing throttle. That is the same stop-point exception, at
   the same moment it happens today, because the person tapped the journey.
   - Leaving the preview cancels whatever is still queued.
   - The answers (name, town, zone) are kept in memory for the session,
     keyed like `GeocodePolicy`. They are never written to disk.
   - 「新增旅程」 writes those answers onto the new stops before S3 opens.
     S3 then names only what the preview never reached, so the film is not
     held behind a second 2 s-per-stop wait.
4. *(eng)* **Routing starts only at 「新增旅程」.** It starts through the
   unchanged `ImportService → RouteMatchCoordinator` path, with the existing
   duplicate check (`existingTrip(for:)`) first.
5. **§0 is unchanged.** The scan and the journey-name lookups start when
   Footprints is **first shown**, never at launch. A segmented view must not
   build Footprints early. Home is still never looked up (2026-09-18 (c)).

## Rejected

- Import on tap, plus a "kept" column: this means a schema bump, relay
  requests for every trip that is only browsed, and stored trips that no
  screen admits to.
- One detail screen: rejected by Chiu. The diary is for reading; S3 is for
  making.
- Export or editing in the diary: the same flow would live in two places,
  which is the drift 2026-09-18 (b) warned about.
- A bottom tab bar: there are only two items over one set of trips, and a
  segmented control fits that better.
- Footprints as the default: that promotes the beta over S1, which is a
  separate decision.
- 「旅行足跡 / Chronicle」 as the name: the two languages would name
  different things.
- Marking album or date imports apart from discovered trips: the same code
  rebuilds both from photographs.

## Consequences

**Copy is draft, and Chiu finalises it.** The strings are:
- segments 旅程 / 足跡 and Journeys / Footprints;
- the title 足跡 / Footprints;
- 新增旅程 / Create Journey and 在旅程中打開 / Open in Journeys;
- the unsaved-journey wording.

`discovery_title` and `discovery_open` are retired.

**Tests owed:**
- a preview's itinerary equals the imported trip's stops;
- a geocoder stub counts exactly one lookup per stop across preview and
  import;
- no scan or lookup runs at launch;
- a stored trip in Footprints has no delete;
- the diary has no export path.

**Owed before this ships** (analysis 2026-09-30, filed 2026-10-01):
1. #167 — hidden journeys cannot be restored.
2. #165, the part left open — the country before any lookup answers.

Already decided and built in `2026-10-01-an-unnamed-trip-is-called-by-its-place`:
the list calls a stored trip by its own name (#164), a trip made here is
stored unnamed and named by its place (#165), and a failed 「新增旅程」 says
why (#166).

**Related, not blocking:** #168 (the fallback title breaks on a language
change), #169 (the list is stale after the diary), #170 (keys move when a
threshold changes). Preview naming (Data, point 3) should run through the
shared geocode queue of #159 rather than add a fourth geocoder. The
main-thread cost of the list is measured in #163.

**Render owed:** both segments, a preview, 「新增旅程」 → S3, and a stored
trip's diary. Render them in light and dark on the simulator with
`-demo-discover`.

**Snapshot:** the PR that builds this updates `Docs/current-state.md`'s
"Last synced" line to name this ADR.
