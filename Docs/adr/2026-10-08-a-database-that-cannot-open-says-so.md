# A database that cannot open says so on screen instead of crashing the launch

**Status:** Decided (Chiu, 2026-10-08)
**Supersedes:** nothing

## Context
`AppConfig.openDatabaseOrDie` ended in `fatalError` (#245). Opening `kamome.sqlite`
can fail for reasons that last: a full disk at a migration, a damaged file.
Then every launch crashed, and the only way out was deleting the app, which
deletes the trips with it. INFERRED from the code, never provoked on a phone.
The cheapest check is a phone with almost no free storage, running a build
that adds a migration.

Two cases are separate:
- A phone restarted and still locked cannot read the file at all. PR #249
  waits for the first unlock, so that case never reaches this screen.
- A broken `TrackingConfig.json` is a bundle bug, not the person's. It still
  crashes, as spec §0 rule 2 requires.

## Decision
Chiu, 2026-10-08: 「改成顯示錯誤畫面」.
- If the database cannot open while the phone is unlocked, the app shows
  `DatabaseFailureView` instead of crashing. The screen has a title, one
  sentence (nothing was deleted; free up space, then try again), the error's
  `domain · code`, and a **Try Again** button.
- Try Again opens the database once more and does nothing else. Kamome never
  retries on its own and never deletes, resets or replaces the file.
- The failure is logged under `storage` with its code public. The description
  stays private, because it names a file path.
- The wording is a draft, so it joins Chiu's wording batch (#118).

## Rejected
- Keep the crash: it loops on every launch and leaves deleting the app as the
  only way out.
- Offer "start fresh" (delete or move the file): it trades the person's trips
  for a working app without asking what they want.
- Retry automatically on a timer: it hides the cause and changes nothing on a
  full disk.

## Consequences
- `openDatabaseOrDie` becomes `openDatabase() throws`.
- `ProtectedDataLaunch` holds `failure` and exposes `retry()`.
- Three strings are added in both languages.
- `ProtectedDataLaunchTests` cover the failure, Try Again, and the absence of
  any automatic retry.
