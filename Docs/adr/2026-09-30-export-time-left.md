# The export sheet says how long is left, from the export's own pace, after a warm-up

**Status:** Decided (Chiu, 2026-09-30)
**Supersedes:** nothing (it answers `Docs/_archive/pre-launch.md` item 5 and `Docs/release-readiness.md` C2)

## Context

Issue #151. Pre-launch item 5 made an export-time estimate mandatory ("a
six-minute export with no estimate reads as broken"). None was built: the sheet
showed a percentage (VERIFIED, `RecapView`).

- Per-snapshot cost has been measured from 0.72 s (simulator) to 7.40 s (phone,
  D3, old build). It depends on device, network and thermal state (VERIFIED,
  `Docs/handoff-export-performance.md`, device runbook D2/D3).
- D2: a 298.7 s Standard film, 670 stations, took 745.9 s on a phone, 508 s of
  it at thermal `serious` or above (VERIFIED, old build 0.2 (1)).
- Stations cluster at stop beats: one station can serve a whole held stop,
  while a crossing arc spends about one per two frames (`Docs/camera-arcs.md` §9).

## Decision

Chiu, 2026-09-30: *build it, as a live estimate, not a pre-start prediction.*

1. **What it shows:** while drawing, after the percentage — "42% · About 5 minutes
   left" / 「42% · 約剩 5 分鐘」; under a minute, "Less than a minute left" /
   「剩不到 1 分鐘」. Wording is a draft for the #118 batch.
2. **How it is measured:** stations delivered per second since drawing began,
   extrapolated over the stations left (`RecapExportTimeLeft`). The station plan
   is the render's own (`RecapRenderLoop.stations`), handed over as drawing starts.
3. **When it appears:** only after `export.pipeline.estimate_warmup_s` (60 s,
   Chiu's "the first minute") and at least one whole station.
4. **It does not flicker up:** a falling estimate shows at once; a rising one
   only when it exceeds the shown minutes by more than
   `estimate_rise_tolerance_min` (1). A real slowdown still gets through.
5. **The photo download is labelled, not estimated:** it precedes drawing and
   keeps its own "N / M" count; the estimate's clock starts after it, so iCloud
   time never distorts the pace. Road finding is likewise outside it.

## Rejected

- **A pre-start prediction:** off several-fold across the measured 0.72–7.4 s range.
- **Frames per second:** a stop beat's hundreds of frames on one station would
  read as half the work done (pinned by `RecapExportTimeLeftTests`).
- **Estimating the iCloud download too:** its cost is per photo and per network,
  unrelated to the render's pace; its count already says how far along it is.

## Consequences

- Two tunables in `Config/TrackingConfig.json` → `export.pipeline`.
- INFERRED: at D2's pace (~0.9 stations/s) the warm-up holds ~50 stations, enough
  to average over. Settled by one phone export on a `main` build (#112, D2).
- UNKNOWN: how far the whole-run average lags a thermal slowdown on a phone. The
  same D2 run, read against the sheet, settles it.
- VERIFIED on the simulator (2026-09-30, one cold run, 57 stations, 155.3 s):
  where the render is **not** snapshot-bound (wait 52 s of 155 s; composite and
  encode dominate), stations are the wrong unit. At 86% of frames the sheet said
  "about 2 minutes" and the film finished within about a minute. D2 on the phone
  was snapshot-bound (wait 522 s of 746 s), which is the case this design is for.
  If the phone disagrees, the fix is to blend the frame and station fractions,
  not to go back to frames alone.
