# A recording starts only once location is allowed, and says so when it is not

**Status:** Decided (Chiu, 2026-10-02)
**Supersedes:** nothing

## Context

A simulator pass on 2026-10-02 (`main` 979ac8e, iOS 26.5) refused the location
prompt after Start Journey (#190).

- VERIFIED (captures): the recording screen stayed up — map, 0:00, 0.0 km, End
  Trip — and said nothing. The "Change to Always Allow" card was raised behind
  the system prompt and offered again after the refusal.
- VERIFIED (code): `TrackingSession.start` began the engine and the journal
  before any answer, and no view read a refused state.
- INFERRED: a drive started this way is lost with no warning. Not provoked on a
  phone; the code path has no device-only branch.

## Decision

Chiu, 2026-10-02: *「那紀錄畫面要有提醒或乾脆不給他用 有訊息讓他知道我們需要有定位訊息
才有辦法提供這個功能」*. He allowed either form; this is how the session built it.

1. **Start Journey asks first.** With the prompt unanswered, the record sheet
   stays up while iOS asks; a yes starts the recording, and only then.
2. **Refused: nothing starts.** The sheet shows, in place of the picker and the
   button, that recording needs location and an Open Settings button. No
   engine, no journal, nothing for a relaunch to resume.
3. **Refused in the middle of a trip** (in Settings, or before a relaunch
   resumed the recording): the recording is kept and the HUD carries a notice
   with Open Settings for as long as it is true.
4. The Always card is raised only over When In Use — where there is something
   to upgrade.

## Rejected

- Start anyway and warn on the recording screen only: a trip that cannot record
  is still opened, and ending it saves nothing.
- An alert: CHARTER §7 rule ⑤, errors are conversations.
- End a recording when location is refused mid-trip: the track so far is the
  user's, and Settings can give location back.

## Consequences

- `LocationAccess`, `LocationPermission` and `TrackingSession.requestStart`;
  `start` is unchanged underneath. Held by `RecordingLocationAccessTests`,
  watched red with the gate removed.
- VERIFIED on the simulator: refusal, Settings and back, a start, location off
  and on again mid-trip with the distance resuming (0.7 → 1.6 km), one process.
- UNKNOWN: whether iOS resumes fixes by itself when location returns; the
  service asks again, which is a no-op if it does.
- UNKNOWN on a phone: where Open Settings lands (the simulator opened Settings'
  root once, Kamome's page once). One tap on a TestFlight build settles it.
- Wording: the zh-Hant sentences and the button, 「開啟定位設定」, are Chiu's
  (2026-10-02). The English follows them and is the session's draft (#118).
