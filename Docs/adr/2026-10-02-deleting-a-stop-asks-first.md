# Deleting a stop asks first

**Status:** Decided (Chiu, 2026-10-02)
**Supersedes:** nothing

## Context
- VERIFIED (#188, Release build 0.2.1 (692), simulator): one full swipe to the
  left on a Trip Detail row deleted the stop at once. No dialog, no undo.
- VERIFIED (source): `TripRepository.deleteStop` removes the row. The stop's
  name, note and film choices go; its photos stay in the trip, attached to
  the route. A recorded stop cannot be made again.
- Home had the same shape for a whole trip until the arch review of
  2026-09-24 (P0-4), and has asked first since.

## Decision
Chiu 2026-10-02, shown three options: 「跟首頁一樣先問一次」.

A stop is deleted only after a confirmation dialog, on both ways in: the
timeline's swipe and the Stop Editor's 「刪除停留點」 button. The dialog says what
goes and what stays.

## Rejected
- `allowsFullSwipe: false` alone: a tap on the red button still deletes with
  no way back.
- Both: one more step for the same protection.
- Undo: nothing in the app has it, and it would be a new pattern.

## Consequences
- New string `stop_delete_confirm`. **Copy is draft** — wording is Chiu's.
- The full swipe still works as a gesture; it now opens the dialog.
- "Merge with previous" is unchanged and still immediate. It keeps the
  photos and the earlier stop's name; the absorbed stop's name and note go.
  UNKNOWN whether that wants a confirmation too. Not asked.
