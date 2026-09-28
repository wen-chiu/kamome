# Architecture review before TestFlight — 2026-09-24

Reviewer: Arch session, against `main` at PR #89 (`fcdd912`). `./check.sh` exit 0
on that tree (609 tests, 30 skipped, iPhone 17 simulator). The findings are about
paths the tests did not exercise.

**Status, branch `claude/p0-stability-fixes` (Chiu 2026-09-24: fix P0 1, 2, 4 and
P1 7):** P0-1, P0-2, P0-4 and P1-7 are **fixed** there, each with a test.
P0-3 and P2-12 were **closed by PR #90** (recording journal, End Trip confirm),
which merged while this review was being written. **Second round (Chiu: 「剩下的5 6
8-11你也一起把他妥善處理」):** P1-5, 6, 8, 9, 10 fixed, P1-11 decided (ADR
2026-09-24 (d)). **What is left is device-only**, listed at the end.

Evidence labels (`CLAUDE.md` rule 4): **VERIFIED** = read in the code at the
line named, **INFERRED** = follows from the code but not provoked, **UNKNOWN**.

## P0 — fix before handing a build to testers

1. ✅ **Fixed** — `RecapEncoderTests.testAppendAfterTheWriterStoppedThrowsInsteadOfWaitingForever`
   was red before the fix (5 s timeout) and green after.
   **The encoder can spin forever and lock out every later export.**
   `Core/ExportEngine/RecapVideoEncoder.swift:56` loops on
   `!input.isReadyForMoreMediaData` with `Thread.sleep` and never reads
   `writer.status`. A writer that has failed never becomes ready, so the loop
   never exits (VERIFIED by reading). The cancel flag is read only *before*
   `append` (`RecapExporter.swift:106`), so Cancel and background-assertion
   expiry cannot stop it, `RecapExportCoordinator.running` never clears, and
   every later export is refused ("a film is already rendering") until the
   process dies. The trigger most likely on a phone is the app being
   backgrounded mid-encode, which invalidates the hardware encoder session:
   INFERRED. **Cheapest settlement:** a unit test that calls `cancelWriting()` on
   the writer and then `append`. It hangs today. Fix: throw on `.failed`/`.cancelled`
   inside the loop.

2. ✅ **Fixed** — `TripDeletion` (one delete for Home and Discovery) cancels the
   export and routing first; the job re-checks its flag on the main actor before
   storing; a failed `film` insert deletes the moved file. `TripDeletionTests`.
   Merge already refused a rendering trip (`trip_merge_busy`).
   **Deleting a trip while its film renders or its legs route.**
   `TrackingSession.deleteTrip` (Home swipe) and `JourneyDiscoveryModel.delete`
   never consult `RecapExportCoordinator` or `RouteMatchCoordinator` (VERIFIED).
   The export can be left running by design (ADR 2026-09-10), so this is
   reachable. When the render ends, `persistFilm` moves the MP4 into `Films/`
   first and then inserts a `film` row whose `trip_id` no longer exists. With
   `foreignKeysEnabled` that insert should fail (INFERRED; a unit test settles it),
   the export reports `.failed`, and the moved file is orphaned. `cleanup` targets
   the tmp path, which is already empty (VERIFIED).

3. ✅ **Closed by PR #90** (`Docs/handoff-long-recording.md`): write-ahead journal,
   resume on relaunch, a failed save keeps the journal. Still open from here: the
   user is not told when a save fails (logged only; the next launch retries).
   **A recording lived only in memory until End Trip, and saving it swallowed the
   error.** `TrackingSession` holds the whole trace in `TrackingEngine`, and the
   first write is `saveCompletedTrip` in `end()`, under `try?` (VERIFIED,
   `TrackingSession.swift:107`). A crash, a jetsam or a force-quit during a
   multi-hour drive loses the trip, and a failed save loses it silently. No ADR
   accepts this (searched `decisions.md` and `release-readiness.md`). Recording is
   reachable from S1 (ADR 2026-09-23 (d)). Checkpointing is a design change, so it
   is Chiu's to decide (rule 2). Logging and surfacing the save failure is not a
   design change.

4. ✅ **Fixed** — a confirmation dialog; a recorded trip is warned it cannot be
   recovered (`trip_delete_recorded_confirm`, **draft wording, Chiu's**), an
   imported one reuses Discovery's copy. Edge: a merged trip containing any import
   is marked reconstructed and gets the imported wording.
   **Home swipe-to-delete had no confirmation.** A full swipe deletes the trip and
   its films (`HomeView.swift:190`). A recorded trip cannot be recovered.
   Discovery and the film player both confirm (`confirmationDialog`), so Home is
   the odd one out. That makes it a UX call (DESIGNER/Chiu), and the change is trivial.

## P1 — before or during TestFlight

5. ✅ **Fixed** — `Stored.write` / `Stored.read` log every repository failure under
   `KamomeLog.storage` (fixed-string labels only); import says `import_error_save`
   (draft wording) when the database refuses; Trip Detail deletes a film's file only
   after its row. `ImportSaveFailureTests`. DemoSeeder (DEBUG) left as it was.
   **48 swallowed repository errors in App/UI**, against `Arch.md` §5 ("no silent
   fallbacks"). The ones that mislead:
   - `ImportFlowModel.save`: its comment says the only thrown error is
     `notEnoughGeotaggedPhotos`. That is false, because `saveImportedTrip` throws
     database errors, and those reach the user as "no geotagged photos".
   - Two `deleteFilm` implementations with opposite semantics:
     `TripDetailModel.deleteFilm` ignores a DB failure and deletes the file anyway
     (the row outlives its file), while `RecapModel.deleteFilm` logs and keeps the file.
6. ✅ **Fixed** — logged (text private), screen shows `domain · code`.
   `ExportFailureCodeTests`.
   **An export failure reaches the screen as raw `String(describing: error)` and
   is never logged** (`RecapExportJob+Render.swift:158`). TestFlight exists to run
   D1–D5, and this is the one failure a device session most needs recorded. Log it
   `privacy: .private`, because a MapLibre error can carry a tile URL whose z/x/y is
   a location (§0).
7. ✅ **Fixed** — a switch: build setting `KAMOME_SIDELOAD_REGIONS` (Debug YES,
   Release NO) adds the two keys post-build; the tile search reads
   `UIFileSharingEnabled` back and skips Documents / Application Support when off;
   `check-archive.sh` fails an archive that carries them. A testing archive
   passes `KAMOME_SIDELOAD_REGIONS=YES`. Release plist VERIFIED without the keys,
   and with them when switched on. `SideloadSwitchTests`.
   **The dogfood side-load shipped in every configuration.** `UIFileSharingEnabled` and
   `LSSupportsOpeningDocumentsInPlace` (`project.yml` ~l.91) are set for Release
   as well. A `.pmtiles` file placed in Documents takes precedence over OpenFreeMap:
   the film is fixed dark and credits OSM only, with no terrain clause.
   `snapshotProvider`'s doc comment says this path is "dormant" and that the export
   "no longer falls through to it", but the code checks the region **first**
   (VERIFIED, `RecapExportJob+Render.swift` `snapshotProvider`). The comment and the
   code disagree. Whether the side-load ships is a product decision.
8. ✅ **Decided and built** (ADR (d)) — About → "Export diagnostics": this
   launch's Kamome log lines as a shared text file. `DiagnosticsLogTests`.
   **TestFlight is a Release build, so `DriveTestLog` and the debug export menu
   (`#if DEBUG`) are absent.** What a D1–D5 run leaves behind is `KamomeLog`
   (os_log), readable only through Console or a sysdiagnose. Decide how the data
   comes off the phone *before* the device session, not during it.
9. ✅ **Fixed** — `export.pipeline.prefetch_depth` / `composite_concurrency`.
   `ExportPipelineConfigTests` (every copy helper keeps them).
   **Render-loop tunables are hard-coded.** `RecapRenderLoop.prefetchDepth = 8`
   and `compositeConcurrency = 4` (about 100 MB peak "named, not measured") are
   tunables under rule 7, and memory on older phones is the jetsam risk D2 is
   meant to price.
10. ✅ **Fixed** — `export.pipeline.snapshot_timeout_s` (60, INFERRED) via
    `SnapshotDeadline`, for any substrate. `SnapshotDeadlineTests`, and an export
    over a provider that never answers fails instead of hanging (`RecapEncoderTests`).
    **`MLNMapSnapshotter` has no completion timeout, and a stuck snapshot makes
    Cancel inert** (the flag is read only at frame delivery). INFERRED:
    MapLibre's own HTTP timeouts probably bound it. UNKNOWN on device.
11. ✅ **Decided, no code** (ADR (d)): stays in device backup — the user's own
    backup, not Kamome syncing; the journal stays excluded.
    **`kamome.sqlite` (every trackpoint) goes into the device's iCloud Backup.**
    It lives in Application Support, and no exclusion is set. The ADR (2026-09-08 §5)
    decided backup for *films* only. Whether device backup counts as "synced"
    under §0 is Chiu's call, not an implementation detail.

## P2 — small bugs and drift

12. ✅ Closed by PR #90 (`resetHUD`). `TrackingSession.start` reset `distanceM` but not `lastCoordinate`. On a second
    recording in the same app session, the live distance jumps by the gap from the
    previous trip's end. Display only: the saved stats are recomputed from segments (VERIFIED).
13. `TripDetailModel.reload` reads every trackpoint synchronously on the main
    thread. A long recording can hitch S3 (INFERRED).
14. Doc drift: `Arch.md` says ExportEngine has 36 files (there are 59).
    `AppDatabase.swift:41` cites `Docs/kamome-poc-spec.md`, which is now under
    `_archive/`. `current-state.md` says "No release is in flight" while TestFlight
    preparation is under way. The staleness check is one PR behind (#89), which is
    within the floor.

15. **Found while fixing, on `main` after PRs #90–#92:** `./check.sh` failed on a
    clean `main`. The test-count baseline read 627 against 637 tests, because one
    of two concurrent bumps was lost in a merge (no test disappeared), and
    `current-state.md` named PR #89. Both are corrected on this branch. PR #91 adds
    schema v8 (`photo_ref.is_excluded`) and a Stop Editor behaviour change with
    **no ADR**. Owed by that PR's author, not reconstructed here.

## Held up well (Architecture verified by reading)

- The dependency graph is gated (`Config/architecture.json`), and GRDB, MapLibre
  and AVFoundation are each confined to their one place.
- Single-flight export and routing coordinators. The lifecycle guard is released
  on one exit path.
- No coordinate reaches a log with `.public` (grep of every `KamomeLog` call).
- Migrations are forward-only, and v7 is data-only and idempotent.

## Still owed — needs a phone, no session can do it

- **P0-1's trigger.** Background the app mid-export on a device and confirm the
  export now *fails* (and a second export can start) rather than hanging.
- **`snapshot_timeout_s` = 60** against real per-snapshot times (D3), and
  **`prefetch_depth` / `composite_concurrency`** against peak memory (D2). The
  diagnostics export carries the `render cost` line both are read from.
- **The diagnostics file on a Release build.** Confirm what `OSLogStore` returns
  outside a debugger (redaction of private values) before relying on it.
- **Draft wording, Chiu's:** `trip_delete_recorded_confirm`, `import_error_save`,
  `about_export_diagnostics*`.

## Round 2 — review of PRs #94–#101, 2026-09-26

Against `main` at PR #101 (`19040af`): `./check.sh` exit 0, 718 tests, 30 skipped.
Staleness passes (synced to PR #99; one behind is the floor). Nothing below is a
test failure: these are the gaps the gates do not see.

1. **`UI/` is never linted.** `.swiftlint.yml` includes App, Core and Tests only,
   and it has done so since 2026-07-12. Linting `UI/` under the same rules finds
   12 errors (VERIFIED, run with a temporary config):
   - `RecapView.swift` 549 lines and `TripDetailView.swift` 420, both over
     `file_length` 400
   - four `type_body_length` (including `TripDetailView` at 340 of 250, and
     `JourneyDiscoveryModel` at 281)
   - four `line_length`, one `function_body_length`, one `shorthand_operator`

   Fix: add `UI` to `included` and split the export sheet (`RecapView`) by
   section. That is a build-gate change (rule 2) → Chiu.
2. **"Day N" follows the phone's current zone, so the film depends on where the
   phone is at export time** (VERIFIED: `RecapComposer.dayLabel` and `dayCount`
   use `Calendar.current`). ADR 2026-09-25 accepted only the +1 h case (Japan
   seen from Taipei).
   - Iceland seen from Taipei puts the day boundary at 16:00 local.
   - The same trip exported in Taipei and in Reykjavík gets different HUD days
     and a different DAYS figure.

   Proposal: keep the zone that `CLGeocoder`'s placemark already returns in the
   stop lookup Kamome already makes (an allowed §0 flow, no new data leaves), and
   store it on the stop. Needs a product decision and a schema change → Chiu.
3. **Routing verdicts can only be revised by a data migration.** v7 and v11 each
   cleared `no_road` because a stored verdict is never re-asked. ADR (f) says
   retuning the pace numbers will not re-judge `beyond_driving`. The photo
   analysis already solves this shape with `PhotoAnalysisVersion`. Proposal:
   store a rules version next to `routability`, so a rule change becomes a
   version bump that re-asks only the legs it affects.
4. **ADR 2026-09-24 (f) is implemented, merged and marked DRAFT.**
   - Its three numbers (150 km/h, 100 km, a 2 h clock margin) still need Chiu's
     sign-off.
   - It is absent from HANDOFF's "Awaiting Chiu".
   - Because of point 3, the numbers a TestFlight build writes are permanent on
     the phone.
5. **Photo analysis can run during an export.** Vision runs at background
   priority, and whether that slows a render is **INFERRED** (ADR (d)'s own
   table). Cheap guard: don't start or continue a photo-analysis run while
   `RecapExportCoordinator.running` is set. The rows resume on their own.
6. **Three copies of one lock-guarded cancel flag** (`RouteMatchCoordinator`,
   `PhotoAnalysisCoordinator`, `ExportCancelFlag`). Low value on its own;
   consolidate the next time one of these files is touched.

Held up (read, not re-derived):
- PR #93's fixes survived every later merge, and `TripDeletion` now also cancels
  photo analysis.
- The walk re-ask throws when nobody answers, rather than storing a crossing.
- The analysis pick falls back to the old pick exactly when there is no signal
  (`PhotoSignalPickTests`).
- The probe screen is `#if DEBUG`.
- No bare `try? repository` has come back.

**Round 2 status (branch `claude/arch-review-2`, ADR 2026-09-26).** Points 1, 2,
3, 5 and 6 are built, each with tests. Point 4, ADR (f)'s pace numbers, was
measured, and Chiu decided 160 km/h (ADR 2026-09-26 (b)):
- **The measurement.** The rule was replayed over the three local real-trip
  dumps (Iceland 2,300 photos, New Zealand 160, Miyakojima 53), taking every
  consecutive photo pair ≥ 30 km apart. That is a superset of the real legs.
- **No false positives.** The fastest driven pair judged 24 km/h (raw 63)
  against the 150 threshold.
- **What the dumps cannot test.** They hold no flight, so a missed flight is
  untested here.
- **Worked cases, INFERRED.** High-speed rail trips the plane when photos
  bracket the ride tightly:
  - Beijing → Shanghai, 1,200 km in 4.5 h, judges about 176 km/h.
  - Paris → Marseille by TGV, 750 km in 3 h, judges about 147 km/h, just under.

Owed on a phone: a trip opened after v14 shows each stop's zone filled (the
back-fill), and an Iceland film exported in Taipei draws the same `Day N` as the
Reykjavík count.
