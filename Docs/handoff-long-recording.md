# Long recordings — a two-week trip on one recording

Opened 2026-09-24, before a tester's two-week New Zealand road trip on
TestFlight. Question from Chiu: is live recording stable enough to run a whole
journey, and can the result become a film?

## What was wrong

**A recording lived only in memory until End Trip.** `TrackingEngine` held
every fix; `TrackingSession.end` was the only write to the database; launch had
no recovery. Anything that ended the process first lost the whole trip, with no
message: an app-switcher swipe, an iOS memory kill, a TestFlight or iOS update,
a flat battery. VERIFIED from code (`TrackingSession`, `KamomeApp.init`).

**End Trip was one tap**, destructive, on a phone that sits in a car mount.
VERIFIED from code.

## What changed (this PR)

- **`RecordingJournal`** (`Core/TrackingEngine`) — a write-ahead journal of the
  engine's *inputs*: start, every sample with its motion activity, end. The
  engine is pure and clock-free, so replaying the journal reproduces its state
  exactly. `RecordingJournalTests` cuts a 9-day fixture at 12 points and at
  every dwell transition and asserts state, segments, stops and mode match.
  VERIFIED.
- **`RecordingJournalFile`** (`App/Services`) — one file in Application
  Support, `completeUntilFirstUserAuthentication` so it is writable while
  locked, excluded from backup, deleted when the trip is saved (§0).
- **`TrackingSession` recovers on launch.** No end line → resume (engine
  replayed, GPS restarted, dwell region re-armed) and S2 says once that the
  app was closed and how long has no track. End line → save as ended (End Trip
  pressed, save never finished). A failed save keeps the journal for the next
  launch. `RecordingRecoveryTests`.
- **Dwell region state check.** `pauseForDwell` now calls `requestState`; an
  `.outside` answer resumes GPS. A region armed with the phone already outside
  never fires an exit. This matters for a recovery at a stop the car has since
  left.
- **End Trip asks first**, and the dialog says an ended trip cannot be continued
  and that stopping for the night does not need an ending.
- `KamomeLog.recording`: recoveries and journal failures, with counts only,
  because `DriveTestLog` is DEBUG-only and TestFlight had no recording log at all.

## Measured and unmeasured

- **Replay time.** VERIFIED on the Mac: 200 000 samples (7 MB) in **2.1 s**
  (debug build). That count is roughly two weeks, which is INFERRED from the
  sampling table. **UNKNOWN on a phone.** Replay runs in `App.init` on the main
  thread, and a background relaunch gets seconds. Cheapest check: a device
  run of `testTwoWeeksOfJournalReplaysQuickly`. If it is too slow, the fix is a
  periodic engine snapshot, and it needs Chiu's approval first.
- **Relaunch after an app-switcher swipe.** Significant-change monitoring
  should relaunch a terminated app in the background. Whether it does after the
  *user* force-quits is **UNKNOWN** on iOS 26. Device test: start recording,
  swipe the app away, drive 2 km, and without opening Kamome check the
  `recording` log for `recovery: resumed`. Either way, nothing recorded before
  the swipe is lost: the worst case is a gap until the user next opens the app.
- **The gap itself** reaches the trip as GPS silence. `StopDeriver` already
  handles silence the same way (the 2026-07-19 32-minute gap). How it draws
  after a *multi-hour* gap across a long distance is **UNKNOWN**. Settle it by
  replaying a journal with a 3 h / 150 km hole through the desk render.

## Still open, for the long trip

- **S2 redraws the whole path every second** (`RecordingView`'s 1 s clock plus
  a full `MapPolyline`). Across two weeks that is tens of thousands of
  coordinates. INFERRED heat and lag; decimate the display path.
- **No trip merge.** One recording is one film. A tester who ends a recording
  each night gets 14 films and no film of the whole journey. Chiu wants a merge
  feature (2026-09-24). Its open questions are product decisions:
  ① merging a recorded trip with a photo-reconstructed one, where provenance is
  per segment (`segment.source` exists since v2); ② how the gap between two
  merged trips is drawn; ③ what happens to films already made of the parts.
- **Reminders** (forgot to start recording) — deferred by Chiu 2026-09-24.
