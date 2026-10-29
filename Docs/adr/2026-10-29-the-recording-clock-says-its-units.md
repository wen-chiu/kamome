# The recording screen's time says its units: 「12分鐘」, "1 hr, 5 min"

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** nothing. The format `%d:%02d` (hours:minutes) was never decided; it came with the first recording HUD.

## Context
- VERIFIED (#332, Release 1.0.0 (928), simulator, 2026-10-28): the HUD's Time is hours and minutes with no unit. One minute in it reads **0:01** beside "1.4 km", which reads as minutes and seconds, as if the clock had stalled. App Review sees it in the demo video (#126 A4).
- INFERRED that people read it as m:ss; not asked of anyone.

## Decision
Chiu 2026-10-29, choosing between units and an m:ss / h:mm:ss clock: *帶單位*, in the system's own format.
- `DateComponentsFormatter`, `.short`, hours and minutes, the way `RecordingView.resumedText` already says a gap: 「1分鐘」「1小時5分鐘」 / "1 min", "1 hr, 5 min". The first minute reads 「0分鐘」 / "0 min".
- Hours keep counting past a day ("26 hr, 2 min"): the HUD has no room for days, and a trip can run across several.

## Rejected
- **m:ss for the first hour, then h:mm:ss.** It ticks every second and still has no unit; at 1:05:12 it is again a clock to decode.
- **Keep h:mm.** It is the bug.

## Consequences
- `RecordingView.elapsedText(seconds:calendar:)`. Held by `RecordingElapsedTextTests`, which fail with the old format (watched red).
- Seen on the simulator during a simulated drive: 「1分鐘 時間 · 2.4 km · 0 地點」 on one row, and the widest English value, "26 hr, 1 min", still on one row (a temporary offset, not committed). Narrower phones fall back to the HUD's one-figure-per-line layout (#191).
- The App Review demo video is re-recorded from the submitted build anyway (ADR 2026-10-29-motion-and-fitness-is-asked-before-the-recording-screen).
