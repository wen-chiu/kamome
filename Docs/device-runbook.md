# Device runbook — every check that only a phone can answer

**Created 2026-09-28** by pulling the "owed on the phone" items out of eleven
documents where each was the last line of its own section. This is the actual
critical path: no desk session can close any row below, and most of the open
work in `HANDOFF.md` waits on one of them.

**How to use it:** one TestFlight or Debug build, one sitting, top to bottom.
Tick a row by writing the date and the evidence (a log line, a screenshot path
outside the repo, or "Chiu judged"). The detail document is where the full
steps are. When every row in a group is ticked, archive the detail document in
the same PR (`HANDOFF.md` rule).

§0 applies: screenshots and films of real trips stay in `~/Kamome-films/`, and
no coordinate goes into this file. Numbers only.

Before starting: About → **Export diagnostics** carries every log line named
below, numbers only (ADR 2026-09-24 (d)). Confirm first, on a **Release** build,
what `OSLogStore` returns outside a debugger.

---

## A. Release gate — D1–D5 (`Docs/release-readiness.md` Tier 3)

| # | check | pass means | detail |
|---|---|---|---|
| D1 | start an export, **lock the screen**, wait | the export survives, or fails loudly and a second export can start | `release-readiness.md` D1; iOS 26 cannot render MapLibre in the background, so "survives" means pause/resume (`handoff-export-performance.md` §9) |
| D2 | per-trip export time and peak memory at full frame count | numbers recorded for three trips; feeds the export estimate | `render cost:` line; also judges `prefetch_depth` / `composite_concurrency` |
| D3 | seconds per snapshot on current hardware | `render substrate:` mean recorded; `snapshot_timeout_s` = 60 checked against it | `handoff-export-performance.md` §9 — owed: the `render network` line after the one-download-per-tile fix (#105) |
| D4 | Limited Photo Library | import and export work with a limited selection | `device-test-P3.md` H |
| D5 | the S5 export sheet, device half | the desk review's items hold on a phone | `design-reviews/2026-09-25-s5-export-sheet.md`, `device-test-P3.md` G |

## B. TestFlight verifications (`handoff-testflight.md`)

| # | check | pass means |
|---|---|---|
| T4 | S3, the recap screen, the Discovery beta — light and dark; one film per mode | captures taken; report what reads badly, do not restyle |
| T5 | fresh install, dismiss the first-run notice | the app does not background itself |

## C. Films fixed in code, owed a phone export

| check | pass means | detail |
|---|---|---|
| Miyakojima re-export | log reads `film type one destination abroad` and the homecoming line; Chiu judges | `handoff-type2-round-trip.md` |
| MapLibre snapshotter crash | three full exports of the longest trip, no new `Kamome-*.ips` | same |
| Iceland day 12, plane over land | the Skógar → pool leg draws no plane | `handoff-known-bugs.md` |
| Vietnam: Taiwan → Vietnam leg | the stored verdict is read from the log; which of the three causes it is | `handoff-vietnam-crossing.md` |
| Stop-zone days (schema v14) | a trip opened after v14 has every stop's zone; an Iceland film exported in Taipei shows the same `Day N` | `_archive/handoff-arch-review-2026-09-24.md` round 2 |

## D. Features with device numbers UNKNOWN

| check | pass means | detail |
|---|---|---|
| Vision auto-pick | probe run on Iceland, local and iCloud; before/after screenshots for Chiu | `handoff-photo-analysis.md` (full steps) |
| Photo picks (ADR 2026-09-25 (b)) | pick 1–5 per stop and hide a stop; the film follows | same |
| iCloud photo download | transfer size, peak memory of a full-mode film, cellular cost, Optimize Storage on | ADR 2026-09-19 (b) |
| Country rule scan time | seconds per 50k photos on a phone (Mac: 0.32 s) | ADR 2026-09-25 |
| Crash-safe recording | kill the app mid-recording; the trip comes back | `handoff-long-recording.md` |
| Merge-gap pacing | a multi-day `merge_gap` leg paces acceptably; is `merge_gap_min_m` = 500 right | same |
| Export after backgrounding (P0-1) | backgrounding mid-export fails the export, a second one can start | `_archive/handoff-arch-review-2026-09-24.md` |
| Subject lookup miss rate | count fallback badges over ten exports (desk: 1 in 5) | `handoff-subject-lookup.md` |

## E. Chiu's own steps, in this order (`HANDOFF.md` 🔴)

1. `./check.sh --release <.xcarchive>` with the real key in the environment.
2. **Then** rotate the Geoapify key (S7). Never the other way round.
