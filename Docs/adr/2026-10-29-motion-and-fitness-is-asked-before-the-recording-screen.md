# Motion & Fitness is asked on the record sheet, after location and before the recording screen

**Status:** Decided (Chiu, 2026-10-29)
**Supersedes:** nothing. Until now the recording asked by itself (`LocationService.startMotionUpdates`), and no ADR covered it.

## Context
- VERIFIED (#196, simulator, iOS 26.5; Release 1.0.0 (928) on 2026-10-28, Debug `main` at `eb7dbba` on 2026-10-29): on a first recording the Motion & Fitness prompt came up on Home about 1.5 s after End Trip. Its purpose string says "while recording".
- VERIFIED (tccd log, 2026-10-29): it was not queued behind the recording screen, as #196 had inferred. Nothing asked at the start, because on the simulator `isActivityAvailable()` is false. At End Trip, `stopActivityUpdates()` on that never-started manager sent the request (1 ms later), and the prompt was shown 16 ms after that.
- VERIFIED (probe build): a Motion request made at the start is shown at once, over the recording screen and on top of Kamome's "Keep recording with the screen off" card.
- INFERRED: a phone, where activity is available, asks from `startActivityUpdates` at the start, so its prompt lands on the card. UNKNOWN until a fresh install is recorded on a phone (#112, `Docs/device-runbook.md` §D).

## Decision
Chiu 2026-10-29, on #196: *fix it before submission. The Motion & Fitness prompt must appear while recording is starting, in its context, and never after the trip has ended. Denying it never blocks recording, as today.* The session chose how; this is what is built:

1. **Start Journey asks location, then Motion & Fitness, while the record sheet is up.** The recording screen, and Kamome's card with it, comes only after both are answered. The first recording's order: location → Motion & Fitness → recording screen and Kamome's card → (if chosen) the Always prompt the card explains.
2. **Either answer starts the recording.** Refused, the engine classifies modes from GPS alone, as before.
3. **Answered once, never asked again**, and the recording starts at once, as before.
4. **A recording never raises the prompt.** It reads motion only on an answered yes, and stops only what it started. A recording resumed after a relaunch, with Motion unanswered, records on GPS alone and says so in the log.

## Rejected
- **Ask on the recording screen once Kamome's card is gone.** It is the order #196 listed, and it starts the recording a few seconds sooner. But the card's own button raises the Always prompt. Motion would have to wait for that answer too, and whether iOS reports a "Keep Only While Using" answer by any callback is UNKNOWN (not measured). It would also ask while the user may already be driving.
- **Only stop calling `stopActivityUpdates` on a manager that never started.** It fixes the simulator, but on a phone the prompt would still land on Kamome's card (VERIFIED by the probe on the simulator).
- **Ask at first launch or on Home.** Out of context, which is what Chiu ruled out.

## Consequences
- `MotionPermission` / `MotionPermissionProviding` (`LocationService.swift`) and `TrackingSession.startOnceMotionIsAnswered`. `LocationService.readsMotionActivity` decides whether to read motion. Held by `RecordingMotionPromptTests`, which were watched red with the old start restored (5 of 8 tests).
- CoreMotion has no request call: a zero-length activity query raises the prompt. Its handler ran 13–21 ms after the answer on the simulator. If a phone never called back, a second Start Journey press starts the recording (tested).
- Owed on a phone: one fresh-install recording that notes the order of the three prompts (`Docs/device-runbook.md` §D, #112). The App Review demo video (#126 A4) is re-recorded from the build that will be submitted.
