# The render time is shown in Debug builds only

**Status:** Decided (Chiu, 2026-10-10)
**Supersedes:** "stays in Release" (Chiu 2026-09-26), as kept by ADR 2026-10-02-the-finished-screen-is-the-film (Rejected, third bullet)

## Context
The finished screen's caption read 「算圖耗時 213.5 秒」 under the film on a first-time-user walk (VERIFIED, simulator, 2026-10-10, #288). It is the §4.5 render-budget readout, a developer's measurement, shown at the one moment the app means to delight. The film player sheet printed the same number.

## Decision
Chiu, asked whether to reopen it: 「Release 隱藏，只留 Debug」.
- **The finished screen and the film player show the render time in Debug builds only.**
- **The export log still records every render's time**, and Debug builds still show it on screen.
- **A leg with no road still gets its caption line in Release**, unchanged (ADR 2026-10-02 point 3).

## Rejected
- **Keeping it in Release:** a developer's number at the moment meant to delight.
- **Moving it into ⋯:** a menu item nobody needs is still noise.

## Consequences
- `RecapFinishedView.renderReadout` and `FilmPlayerSheet` gate on `#if DEBUG`. No test pinned the Release readout.
- On a phone, the render budget is read from the Debug build or the export log (`ExportLogHistory`).
